//
//  CastClient.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 19/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation
import SwiftProtobuf
import SwiftyJSON
import Result

public enum CastPayload {
  case json([String: Any])
  case data(Data)
  
  init(_ json: [String: Any]) {
    self = .json(json)
  }
  
  init(_ data: Data) {
    self = .data(data)
  }
}

typealias CastMessage = Extensions_Api_CastChannel_CastMessage
typealias CastResponseHandler = (Result<JSON, CastError>) -> Void

public enum CastError: Error {
  case connection(String)
  case write(String)
  case session(String)
  case request(String)
  case launch(String)
  case load(String)
}

final class CastRequest: NSObject {
  var id: Int
  var namespace: String
  var destinationId: String
  var payload: CastPayload
  
  init(id: Int, namespace: String, destinationId: String, payload: [String: Any]) {
    self.id = id
    self.namespace = namespace
    self.destinationId = destinationId
    self.payload = CastPayload(payload)
  }
  
  init(id: Int, namespace: String, destinationId: String, payload: Data) {
    self.id = id
    self.namespace = namespace
    self.destinationId = destinationId
    self.payload = CastPayload(payload)
  }
}

@objc public protocol CastClientDelegate: class {
  
  @objc optional func castClient(_ client: CastClient, willConnectTo device: CastDevice)
  @objc optional func castClient(_ client: CastClient, didConnectTo device: CastDevice)
  @objc optional func castClient(_ client: CastClient, didDisconnectFrom device: CastDevice)
  @objc optional func castClient(_ client: CastClient, connectionTo device: CastDevice, didFailWith error: Error?)
  
  @objc optional func castClient(_ client: CastClient, deviceStatusDidChange status: CastStatus)
  @objc optional func castClient(_ client: CastClient, mediaStatusDidChange status: CastMediaStatus)
  
}

public final class CastClient: NSObject {
  
  public let device: CastDevice
  public weak var delegate: CastClientDelegate?
  public var connectedApp: CastApp?
  
  public init(device: CastDevice) {
    self.device = device
    
    super.init()
  }
  
  deinit {
    disconnect()
  }
  
  // MARK: - Socket
  
  public var isConnected = false {
    didSet {
      if oldValue != isConnected {
        if isConnected {
          DispatchQueue.main.async { self.delegate?.castClient?(self, didConnectTo: self.device) }
        } else {
          DispatchQueue.main.async { self.delegate?.castClient?(self, didDisconnectFrom: self.device) }
        }
      }
    }
  }
  
  private var inputStream: InputStream! {
    didSet {
      if let inputStream = inputStream {
        reader = CastV2PlatformReader(stream: inputStream)
      } else {
        reader = nil
      }
    }
  }
  
  private var outputStream: OutputStream!
  
  public private(set) var currentStatus: CastStatus? {
    didSet {
      guard let status = currentStatus else { return }
      
      if oldValue != status {
        DispatchQueue.main.async {
          self.delegate?.castClient?(self, deviceStatusDidChange: status)
          self.statusDidChange?(status)
        }
      }
    }
  }
  
  public private(set) var currentMediaStatus: CastMediaStatus? {
    didSet {
      guard let status = currentMediaStatus else { return }
      
      if oldValue != status {
        DispatchQueue.main.async {
          self.delegate?.castClient?(self, mediaStatusDidChange: status)
          self.mediaStatusDidChange?(status)
        }
      }
    }
  }
  
  public var statusDidChange: ((CastStatus) -> Void)?
  public var mediaStatusDidChange: ((CastMediaStatus) -> Void)?
  
  fileprivate lazy var socketQueue = DispatchQueue.global(qos: .userInitiated)
  
  public func connect() {
    socketQueue.async {
      do {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        let settings: [String: Any] = [
          kCFStreamSSLValidatesCertificateChain as String: false,
          kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelTLSv1,
          kCFStreamPropertyShouldCloseNativeSocket as String: true
        ]
        
        CFStreamCreatePairWithSocketToHost(nil, self.device.hostName as CFString, UInt32(self.device.port), &readStream, &writeStream)
        
        guard let readStreamRetained = readStream?.takeRetainedValue() else {
          throw CastError.connection("Unable to create input stream")
        }
        
        guard let writeStreamRetained = writeStream?.takeRetainedValue() else {
          throw CastError.connection("Unable to create output stream")
        }
        
        DispatchQueue.main.async { self.delegate?.castClient?(self, willConnectTo: self.device) }
        
        CFReadStreamSetProperty(readStreamRetained, CFStreamPropertyKey(kCFStreamPropertySSLSettings), settings as CFTypeRef!)
        CFWriteStreamSetProperty(writeStreamRetained, CFStreamPropertyKey(kCFStreamPropertySSLSettings), settings as CFTypeRef!)
        
        self.inputStream = readStreamRetained
        self.outputStream = writeStreamRetained
        
        self.inputStream.delegate = self
        
        self.inputStream.schedule(in: .current, forMode: .defaultRunLoopMode)
        self.outputStream.schedule(in: .current, forMode: .defaultRunLoopMode)
        
        self.inputStream.open()
        self.outputStream.open()
        
        RunLoop.current.run()
      } catch {
        DispatchQueue.main.async { self.delegate?.castClient?(self, connectionTo: self.device, didFailWith: error as NSError) }
      }
    }
  }
  
  public func disconnect() {
    if isConnected {
      isConnected = false
    }
    
    channels.values.forEach(removeChannel)
    
    socketQueue.async {
      if self.inputStream != nil {
        self.inputStream.close()
        self.inputStream.remove(from: RunLoop.current, forMode: .defaultRunLoopMode)
        self.inputStream = nil
      }
      
      if self.outputStream != nil {
        self.outputStream.close()
        self.outputStream.remove(from: RunLoop.current, forMode: .defaultRunLoopMode)
        self.outputStream = nil
      }
    }
  }
  
  // MARK: - Socket
  
  private func write(data: Data) throws {
    var payloadSize = UInt32(data.count).bigEndian
    let packet = NSMutableData(bytes: &payloadSize, length: MemoryLayout<UInt32>.size)
    packet.append(data)
    
    let streamBytes = packet.bytes.bindMemory(to: UInt8.self, capacity: data.count)
    
    if outputStream.write(streamBytes, maxLength: packet.length) < 0 {
      if let error = outputStream.streamError {
        throw CastError.write("Error writing \(packet.length) byte(s) to stream: \(error)")
      } else {
        throw CastError.write("Unknown error writing \(packet.length) byte(s) to stream")
      }
    }
  }
  
  
  fileprivate func sendConnectMessage() throws {
    guard outputStream != nil else { return }
    
    _ = connectionChannel
    
    DispatchQueue.main.async {
      _ = self.receiverControlChannel
      _ = self.mediaControlChannel
      _ = self.heartbeatChannel
    }
  }
  
  private var reader: CastV2PlatformReader?
  
  fileprivate func readStream() {
    do {
      reader?.readStream()
      
      while let payload = reader?.nextMessage() {
        let message = try CastMessage(serializedData: payload)
        
        guard let channel = channels[message.namespace] else {
          print("No channel attached for namespace \(message.namespace)")
          return
        }
        
        switch message.payloadType {
        case .string:
          if let messageData = message.payloadUtf8.data(using: .utf8) {
            let json = JSON(messageData)
            channel.handleResponse(json,
                                   sourceId: message.sourceID)
            
            if let requestId = json[CastJSONPayloadKeys.requestId].int {
              callResponseHandler(for: requestId, with: Result(value: json))
            }
          } else {
            NSLog("Unable to get UTF8 JSON data from message")
          }
        case .binary:
          channel.handleResponse(message.payloadBinary,
                                 sourceId: message.sourceID)
        }
      }
    } catch {
      NSLog("Error reading: \(error)")
    }
  }
  
  //MARK: - Channels
  
  private var channels = [String: CastChannel]()
  
  private lazy var heartbeatChannel: HeartbeatChannel = {
    let channel = HeartbeatChannel()
    self.addChannel(channel)
    
    return channel
  }()
  
  private lazy var connectionChannel: DeviceConnectionChannel = {
    let channel = DeviceConnectionChannel()
    self.addChannel(channel)
    
    return channel
  }()
  
  private lazy var receiverControlChannel: ReceiverControlChannel = {
    let channel = ReceiverControlChannel()
    self.addChannel(channel)
    
    return channel
  }()
  
  private lazy var mediaControlChannel: MediaControlChannel = {
    let channel = MediaControlChannel()
    self.addChannel(channel)
    
    return channel
  }()
  
  public func addChannel(_ channel: CastChannel) {
    let namespace = channel.namespace
    guard channels[namespace] == nil else {
      print("Channel already attached for \(namespace)")
      return
    }
    
    channels[namespace] = channel
    channel.client = self
  }
  
  public func removeChannel(_ channel: CastChannel) {
    let namespace = channel.namespace
    guard let channel = channels.removeValue(forKey: namespace) else {
      print("No channel attached for \(namespace)")
      return
    }
    
    channel.client = nil
  }
  
  // MARK: - Message builder
  
  private let senderName: String = "sender-\(UUID().uuidString)"
  
  private lazy var currentRequestId = Int(arc4random_uniform(800))
  
  private func nextRequestId() -> Int {
    currentRequestId += 1
    
    return currentRequestId
  }
  
  func request(withNamespace namespace: String, destinationId: String, payload: [String: Any]) -> CastRequest {
    var payload = payload
    let requestId = nextRequestId()
    payload[CastJSONPayloadKeys.requestId] = requestId
    
    return  CastRequest(id: requestId,
                        namespace: namespace,
                        destinationId: destinationId,
                        payload: payload)
  }
  
  func request(withNamespace namespace: String, destinationId: String, payload: Data) -> CastRequest {
    return  CastRequest(id: nextRequestId(),
                        namespace: namespace,
                        destinationId: destinationId,
                        payload: payload)
  }
  
//  private func closeMessage() throws -> Data {
//    return try CastMessage.encodedMessage(payload: [CastJSONPayloadKeys.type: CastMessageType.close.rawValue],
//                                          namespace: CastNamespace.connection,
//                                          sourceId: senderName,
//                                          destinationId: CastConstants.receiver)
//  }
  
  
  
  // MARK - Request response
  
  private var responseHandlers = [Int: CastResponseHandler]()
  
  func send(_ request: CastRequest, response: CastResponseHandler? = nil) {
    if let response = response {
      responseHandlers[request.id] = response
    }
    
    do {
      let messageData = try CastMessage.encodedMessage(payload: request.payload,
                                                       namespace: request.namespace,
                                                       sourceId: senderName,
                                                       destinationId: request.destinationId)
      
      try write(data: messageData)
    } catch {
      callResponseHandler(for: request.id, with: Result(error: .request(error.localizedDescription)))
    }
  }
  
  private func callResponseHandler(for requestId: Int, with result: Result<JSON, CastError>) {
    DispatchQueue.main.async {
      if let handler = self.responseHandlers.removeValue(forKey: requestId) {
        handler(result)
      }
    }
  }
  
  // MARK: - Public messages
  
  public func getAppAvailability(apps: [CastApp], completion: @escaping (Result<AppAvailability, CastError>) -> Void) {
    receiverControlChannel.getAppAvailability(apps: apps, completion: completion)
  }
  
  public func join(app: CastApp? = nil, completion: @escaping (Result<CastApp, CastError>) -> Void) {
    guard let target = app ?? currentStatus?.apps.first else {
      completion(Result(error: CastError.session("No Apps Running")))
      return
    }
    
    if target == connectedApp {
      completion(Result(value: target))
    } else if let existing = currentStatus?.apps.first(where: { $0.id == target.id }) {
      connect(to: existing)
      completion(Result(value: existing))
    } else {
      receiverControlChannel.requestStatus { [weak self] result in
        switch result {
        case .success(let status):
          guard let app = status.apps.first else {
            completion(Result(error: CastError.launch("Unable to get launched app instance")))
            return
          }
          
          self?.connect(to: app)
          completion(Result(value: app))
          
        case .failure(let error):
          completion(Result(error: error))
        }
      }
    }
  }
  
  public func launch(appId: CastAppIdentifier, completion: @escaping (Result<CastApp, CastError>) -> Void) {
    receiverControlChannel.launch(appId: appId) { [weak self] result in
      switch result {
      case .success(let app):
        self?.connect(to: app)
        fallthrough
        
      default:
        completion(result)
      }
    }
  }
  
  public func stopCurrentApp() {
    guard let app = currentStatus?.apps.first else { return }
    
    receiverControlChannel.stop(app: app)
  }
  
  public func leave(_ app: CastApp) {
    connectionChannel.leave(app)
    connectedApp = nil
  }
  
  public func load(media: CastMedia, with app: CastApp, completion: @escaping (Result<CastMediaStatus, CastError>) -> Void) {
    guard outputStream != nil else { return }
    
    mediaControlChannel.load(media: media, with: app, completion: completion)
  }
  
  public func requestMediaStatus(for app: CastApp, mediaSessionId: Int? = nil, completion: ((Result<CastMediaStatus, CastError>) -> Void)? = nil) {
    guard outputStream != nil else { return }
    
    mediaControlChannel.requestMediaStatus(for: app)
  }
  
  private func connect(to app: CastApp) {
    connectionChannel.connect(to: app)
    connectedApp = app
  }
  
  public func pause() {
    guard let app = connectedApp else { return }
    
    if let mediaStatus = currentMediaStatus {
      mediaControlChannel.sendPause(for: app, mediaSessionId: mediaStatus.mediaSessionId)
    } else {
      mediaControlChannel.requestMediaStatus(for: app) { result in
        switch result {
        case .success(let mediaStatus):
          self.mediaControlChannel.sendPause(for: app, mediaSessionId: mediaStatus.mediaSessionId)
        
        case .failure(let error):
            print(error)
        }
      }
    }
  }
  
  public func play() {
    guard let app = connectedApp else { return }
    
    if let mediaStatus = currentMediaStatus {
      mediaControlChannel.sendPlay(for: app, mediaSessionId: mediaStatus.mediaSessionId)
    } else {
      mediaControlChannel.requestMediaStatus(for: app) { result in
        switch result {
        case .success(let mediaStatus):
          self.mediaControlChannel.sendPlay(for: app, mediaSessionId: mediaStatus.mediaSessionId)
          
        case .failure(let error):
          print(error)
        }
      }
    }
  }
  
  public func stop() {
    guard let app = connectedApp else { return }
    
    if let mediaStatus = currentMediaStatus {
      mediaControlChannel.sendStop(for: app, mediaSessionId: mediaStatus.mediaSessionId)
    } else {
      mediaControlChannel.requestMediaStatus(for: app) { result in
        switch result {
        case .success(let mediaStatus):
          self.mediaControlChannel.sendStop(for: app, mediaSessionId: mediaStatus.mediaSessionId)
          
        case .failure(let error):
          print(error)
        }
      }
    }
  }
  
  public func seek(to currentTime: Float) {
    guard let app = connectedApp else { return }
    
    if let mediaStatus = currentMediaStatus {
      mediaControlChannel.sendSeek(to: currentTime, for: app, mediaSessionId: mediaStatus.mediaSessionId)
    } else {
      mediaControlChannel.requestMediaStatus(for: app) { result in
        switch result {
        case .success(let mediaStatus):
          self.mediaControlChannel.sendSeek(to: currentTime, for: app, mediaSessionId: mediaStatus.mediaSessionId)
          
        case .failure(let error):
          print(error)
        }
      }
    }
  }
  
  public func setVolume(_ volume: Float) {
    receiverControlChannel.setVolume(volume)
  }
  
  public func setMuted(_ muted: Bool) {
    receiverControlChannel.setMuted(muted)
  }
}

extension CastClient: StreamDelegate {
  
  public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case Stream.Event.openCompleted:
      guard !isConnected else { return }
      socketQueue.async {
        do {
          try self.sendConnectMessage()
          
        } catch {
          NSLog("Error sending connect message: \(error)")
        }
      }
    case Stream.Event.errorOccurred:
      NSLog("Stream error occurred: \(aStream.streamError.debugDescription)")
      
      DispatchQueue.main.async {
        self.delegate?.castClient?(self, connectionTo: self.device, didFailWith: aStream.streamError)
      }
    case Stream.Event.hasBytesAvailable:
      socketQueue.async {
        self.readStream()
      }
    case Stream.Event.endEncountered:
      NSLog("Input stream ended")
      disconnect()
  
    default: break
    }
  }
  
}

extension CastClient: ReceiverControlChannelDelegate {
  func channel(_ channel: ReceiverControlChannel, didReceive status: CastStatus) {
    currentStatus = status
  }
}

extension CastClient: MediaControlChannelDelegate {
  func channel(_ channel: MediaControlChannel, didReceive mediaStatus: CastMediaStatus) {
    currentMediaStatus = mediaStatus
  }
}

extension CastClient: HeartbeatChannelDelegate {
  func channelDidTimeout(_ channel: HeartbeatChannel) {
    disconnect()
    currentStatus = nil
    currentMediaStatus = nil
    connectedApp = nil
  }
}

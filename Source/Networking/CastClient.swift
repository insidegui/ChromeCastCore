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
  @objc optional func castClient(_ client: CastClient, connectionTo device: CastDevice, didFailWith error: NSError)
  
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
        if let status = currentStatus, let oldStatus = oldValue {
          handleStatusChange(from: oldStatus, to: status)
        }
        
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
    //    stopBeating()
    
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
  
  public func sendAuthChallenge() throws {
    guard outputStream != nil else { return }
    
    let message = Extensions_Api_CastChannel_DeviceAuthMessage.with({ (message) in
      message.challenge = Extensions_Api_CastChannel_AuthChallenge()
    })
    
    let request = CastRequest(id: nextRequestId(), namespace: .auth, destinationId: CastConstants.receiver, payload: try message.serializedData())
    send(request: request)
  }
  
  
  fileprivate func sendConnectMessage() throws {
    guard outputStream != nil else { return }
    
    do {
      let message = try connectMessage()
      
      try write(data: message)
      
      //            NSLog("CONNECT")
      
      DispatchQueue.main.async {
        self.startBeating()
        self.requestStatus()
      }
    } catch {
      NSLog("Error sending connect message: \(error)")
    }
  }
  
  public func sendCloseMessage() throws {
    guard outputStream != nil else { return }
    
    do {
      let message = try closeMessage()
      
      try write(data: message)
      
      //            NSLog("CLOSE")
    } catch {
      NSLog("Error sending connect message: \(error)")
    }
  }
  
  private var reader: CastV2PlatformReader?
  
  fileprivate func readStream() {
    do {
      reader?.readStream()
      
      while let payload = reader?.nextMessage() {
        let message = try CastMessage(serializedData: payload)
        
        switch message.payloadType {
        case .string:
          if let messageData = message.payloadUtf8.data(using: .utf8) {
            handleJSONMessage(with: messageData, originalMessage: message)
          } else {
            NSLog("Unable to get UTF8 JSON data from message")
          }
        case .binary:
          if let response = try? Extensions_Api_CastChannel_AuthResponse(serializedData: message.payloadBinary) {
            print(response)
          } else if let message = try? Extensions_Api_CastChannel_DeviceAuthMessage(serializedData: message.payloadBinary) {
            print(message)
          } else {
            print("Unhandled binary response")
          }
        }
      }
    } catch {
      NSLog("Error reading: \(error)")
    }
  }
  
  //MARK: - Channels
  
  private var channels = [String: CastChannel]()
  
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
    guard let channel = channels.removeValue(forKey: channel.namespace) else {
      print("No channel attached for \(channel.namespace)")
      return
    }
    
    channel.client = nil
  }
  
  // MARK: - Heartbeat
  
  let heartbeatChannel = HeartbeatChannel()
  
  private func startBeating() {
    addChannel(heartbeatChannel)
  }
  
  // MARK: - Message builder
  
  private func encodePayload(with dict: [String:Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: dict, options: [])
    
    return String(data: data, encoding: .utf8)!
  }
  
  private let senderName: String = "sender-\(UUID().uuidString)"
  
  private func jsonMessage(with payload: [String: Any], namespace: String, destinationId: String) throws -> Data {
    let load = try encodePayload(with: payload)
    
    //        NSLog("\(effectivePayload)")
    
    let message = CastMessage.with {
      $0.protocolVersion = .castv210
      $0.sourceID = senderName
      $0.destinationID = destinationId
      $0.namespace = namespace
      $0.payloadType = .string
      $0.payloadUtf8 = load
    }
    
    return try message.serializedData()
  }
  
  private func jsonMessage(with payload: Data, namespace: String, destinationId: String) throws -> Data {
    let message = CastMessage.with {
      $0.protocolVersion = .castv210
      $0.sourceID = senderName
      $0.destinationID = destinationId
      $0.namespace = namespace
      $0.payloadType = .binary
      $0.payloadBinary = payload
    }
    
    return try message.serializedData()
  }
  
  private lazy var currentRequestId = Int(arc4random_uniform(800))
  
  private func nextRequestId() -> Int {
    currentRequestId += 1
    
    return currentRequestId
  }
  
  func createRequest(withNamespace namespace: String, destinationId: String, payload: [String: Any]) -> CastRequest {
    return  CastRequest(id: nextRequestId(),
                        namespace: namespace,
                        destinationId: destinationId,
                        payload: payload)
  }
  
  private func connectMessage() throws -> Data {
    return try jsonMessage(with: [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue], namespace: .connection, destinationId: CastConstants.receiver)
  }
  
  private func closeMessage() throws -> Data {
    return try jsonMessage(with: [CastJSONPayloadKeys.type: CastMessageType.close.rawValue], namespace: .connection, destinationId: CastConstants.receiver)
  }
  
  // MARK - Request response
  
  private var responseHandlers = [Int: CastResponseHandler]()
  
  func send(request: CastRequest, response: CastResponseHandler? = nil) {
    if let response = response {
      responseHandlers[request.id] = response
    }
    
    do {
      let messageData: Data
      
      switch request.payload {
      case .json(var effectivePayload):
        if effectivePayload[CastJSONPayloadKeys.requestId] == nil,
          let type = (effectivePayload[CastJSONPayloadKeys.type] as? String).flatMap({ CastMessageType(rawValue: $0) }), type.needsRequestId {
          effectivePayload[CastJSONPayloadKeys.requestId] = request.id
        }
        
        //        print("SENDING: \(effectivePayload)")
        messageData = try jsonMessage(with: effectivePayload, namespace: request.namespace, destinationId: request.destinationId)
        
      case .data(let data):
        messageData = try jsonMessage(with: data, namespace: request.namespace, destinationId: request.destinationId)
      }
      
      try write(data: messageData)
    } catch {
      callResponseHandler(for: request.id, with: Result(error: .request(error.localizedDescription)))
    }
  }
  
  private func callResponseHandler(for requestId: Int, with result: Result<JSON, CastError>) {
    DispatchQueue.main.async {
      if let handler = self.responseHandlers[requestId] {
        handler(result)
        self.responseHandlers[requestId] = nil
      }
    }
  }
  
  // MARK: - Public messages
  
  public func getAppAvailability(apps: [CastApp], completion: @escaping (Result<AppAvailability, CastError>) -> Void) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.availableApps.rawValue,
      CastJSONPayloadKeys.appId: apps.map { $0.id }
    ]
    
    let request = CastRequest(id: nextRequestId(), namespace: .receiver, destinationId: CastConstants.receiver, payload: payload)
    
    send(request: request) { result in
      switch result {
      case .success(let json):
        completion(Result(value: AppAvailability(json: json)))
      case .failure(let error):
        completion(Result(error: CastError.launch(error.localizedDescription)))
      }
    }
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
      requestStatus() { [weak self] result in
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
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.launch.rawValue,
      CastJSONPayloadKeys.appId: appId.rawValue
    ]
    
    let request = CastRequest(id: nextRequestId(), namespace: .receiver, destinationId: CastConstants.receiver, payload: payload)
    
    send(request: request) { [weak self] result in
      switch result {
      case .success(let json):
        guard let app = CastStatus(json: json).apps.first else {
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
  
  @nonobjc public func stop(app: CastApp) {
    let requestId = nextRequestId()
    
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.stop.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId,
      CastJSONPayloadKeys.requestId: requestId
    ]
    let request = CastRequest(id: requestId, namespace: .receiver, destinationId: CastConstants.receiver, payload: payload)
    
    send(request: request)
  }
  
  public func stopCurrentApp() {
    guard let app = currentStatus?.apps.first else { return }
    
    stop(app: app)
  }
  
  public func leave(_ app: CastApp) {
    do {
      let payload = [CastJSONPayloadKeys.type: CastMessageType.close.rawValue]
      let message = try jsonMessage(with: payload, namespace: .connection, destinationId: app.transportId)
      
      try write(data: message)
      
      connectedApp = nil
    } catch {
      NSLog("Error connecting to app: \(error)")
    }
  }
  
  public func load(media: CastMedia, with app: CastApp, completion: @escaping (Result<CastMediaStatus, CastError>) -> Void) {
    guard outputStream != nil else { return }
    
    var payload = media.dict
    payload[CastJSONPayloadKeys.type] = CastMessageType.load.rawValue
    payload[CastJSONPayloadKeys.sessionId] = app.sessionId
    
    let request = CastRequest(id: nextRequestId(), namespace: .media, destinationId: app.transportId, payload: payload)
    send(request: request) { result in
      switch result {
      case .success(let json):
        completion(Result(value: CastMediaStatus(json: json)))
        
      case .failure(let error):
        completion(Result(error: CastError.load(error.localizedDescription)))
      }
    }
  }
  
  public func requestMediaStatus(for app: CastApp, mediaSessionId: Int? = nil, completion: ((Result<CastMediaStatus, CastError>) -> Void)? = nil) {
    guard outputStream != nil else { return }
    
    var payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId
    ]
    
    if let mediaSessionId = mediaSessionId {
      payload[CastJSONPayloadKeys.mediaSessionId] = mediaSessionId
    }
    
    let request = CastRequest(id: nextRequestId(), namespace: .media, destinationId: app.transportId, payload: payload)
    
    if let completion = completion {
      send(request: request) { result in
        switch result {
        case .success(let json):
          completion(Result(value: CastMediaStatus(json: json)))
          
        case .failure(let error):
          completion(Result(error: error))
        }
      }
    } else {
      send(request: request)
    }
  }
  
  public func requestStatus(completion: ((Result<CastStatus, CastError>) -> Void)? = nil) {
    guard outputStream != nil else { return }
    
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue
    ]
    
    let request = CastRequest(id: nextRequestId(), namespace: .receiver, destinationId: CastConstants.receiver, payload: payload)
    
    if let completion = completion {
      send(request: request) { result in
        switch result {
        case .success(let json):
          completion(Result(value: CastStatus(json: json)))
        case .failure(let error):
          completion(Result(error: CastError.launch(error.localizedDescription)))
        }
      }
    } else {
      send(request: request)
    }
  }
  
  public func requestDeviceInfo() {
    guard outputStream != nil else { return }
    
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.getDeviceInfo.rawValue,
      ]
    
    let request = CastRequest(id: nextRequestId(), namespace: .discovery, destinationId: CastConstants.receiver, payload: payload)
    
    send(request: request) { result in
      switch result {
      case .success(let json):
        print(json)
        
      case .failure(let error):
        print(error)
      }
    }
    //      guard let completion = completion else {
    //        if let error = error {
    //          print(error.localizedDescription)
    //        }
    //
    //        return
    //      }
    
    //      guard error == nil, let json = json else {
    //        if let error = error {
    //          completion(CastError.launch(error.localizedDescription), nil)
    //        } else {
    //          completion(CastError.launch("Unkown error"), nil)
    //        }
    //
    //        return
    //      }
    //
    //      completion(nil, CastStatus(json: json))
  }
  
  public func requestDeviceConfig() {
    guard outputStream != nil else { return }
    
    let params = [
      "version",
      "name",
      "build_info.cast_build_revision",
      "net.ip_address",
      "net.online",
      "net.ssid",
      "wifi.signal_level",
      "wifi.noise_level"
    ]
    
    let requestId = nextRequestId()
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.getDeviceConfig.rawValue,
      "params": params,
      "data": [:],
      "request_id": requestId
    ]
    
    let request = CastRequest(id: requestId, namespace: .setup, destinationId: CastConstants.receiver, payload: payload)
    
    send(request: request) { result in
      switch result {
      case .success(let json):
        print(json)
        
      case .failure(let error):
        print(error)
      }
    }
  }
  
  public func requestSetDeviceConfig() {
    guard outputStream != nil else { return }
    
    let data: [String: Any] = [
      "name": "JUNK",
      "settings": [
        
      ]
    ]
    
    let requestId = nextRequestId()
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.getDeviceConfig.rawValue,
      "data": [:],
      "request_id": requestId
    ]
    
    let request = CastRequest(id: requestId, namespace: .setup, destinationId: CastConstants.receiver, payload: payload)
    
    send(request: request) { result in
      switch result {
      case .success(let json):
        print(json)
        
      case .failure(let error):
        print(error)
      }
    }
  }
  
  public func requestAppDeviceId(app: CastApp) {
    guard outputStream != nil else { return }
    
    let requestId = nextRequestId()
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.getAppDeviceId.rawValue,
      "data": ["app_id": app.id],
      "request_id": requestId
    ]
    
    let request = CastRequest(id: requestId, namespace: .setup, destinationId: CastConstants.receiver, payload: payload)
    
    send(request: request) { result in
      switch result {
      case .success(let json):
        print(json)
        
      case .failure(let error):
        print(error)
      }
    }
  }
  
  
  // MARK: - Message handling
  
  private var disconnectTimer: Timer? {
    willSet {
      disconnectTimer?.invalidate()
    }
    didSet {
      guard let timer = disconnectTimer else { return }
      
      RunLoop.main.add(timer, forMode: .commonModes)
    }
  }
  
  private let disconnectTimeout: TimeInterval = 10
  private var greatestEncounteredRequestId = 0
  
  private func handleJSONMessage(with json: Data?, originalMessage: CastMessage) {
    guard let data = json else { return }
    guard data.count > 0 else { return }
    
    let json = try! JSON(data: data)
    //    print(json)
    if let requestId = json[CastJSONPayloadKeys.requestId].int {
      guard requestId > greatestEncounteredRequestId else {
        return
      }
      
      greatestEncounteredRequestId = requestId
      
      //            NSLog("Received response for previously sent request \(requestId), calling handler")
      callResponseHandler(for: requestId, with: Result(value: json))
    }
    
    guard let rawType = json["type"].string else { return }
    
    guard let type = CastMessageType(rawValue: rawType) else {
      print("Unknown type: \(rawType)")
      print(json)
      return
    }
    
    switch type {
    case .ping:
      print("PING from \(originalMessage.sourceID)")
      
      do {
        let message = try jsonMessage(with: [CastJSONPayloadKeys.type: CastMessageType.pong.rawValue],
                                      namespace: originalMessage.namespace,
                                      destinationId: originalMessage.sourceID)
        
        try write(data: message)
      } catch {
        NSLog("Error sending heartbeat message to \(originalMessage.sourceID): \(error)")
      }
    case .pong:
      // connection confirmed with pong
      if !isConnected {
        isConnected = true
      }
      
      //      print("PONG from \(originalMessage.sourceID)")
      
      if originalMessage.sourceID == CastConstants.receiver {
        disconnectTimer = Timer(timeInterval: disconnectTimeout,
                                target: self,
                                selector: #selector(handleTimeout),
                                userInfo: nil,
                                repeats: false)
      }
      
    case .close:
      switch (originalMessage.sourceID) {
      case CastConstants.receiver:
        DispatchQueue.main.async(execute: disconnect)
        
        fallthrough
        
      case connectedApp?.transportId ?? "":
        currentStatus = nil
        currentMediaStatus = nil
        connectedApp = nil
        
      default:
        print(originalMessage.sourceID)
        break
      }
      
    case .status:
      currentStatus = CastStatus(json: json)
    case .mediaStatus:
      currentMediaStatus = CastMediaStatus(json: json["status"])
    default:
      print(originalMessage.payloadUtf8)
      break
    }
  }
  
  @objc private func handleTimeout() {
    disconnect()
    currentStatus = nil
    currentMediaStatus = nil
    connectedApp = nil
  }
  
  private func connect(to app: CastApp) {
    //        NSLog("Connecting to \(app.displayName)")
    
    do {
      let payload = [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue]
      let request = CastRequest(id: nextRequestId(), namespace: .connection, destinationId: app.transportId, payload: payload)
      
      send(request: request)
      connectedApp = app
    } catch {
      NSLog("Error connecting to app: \(error)")
    }
  }
  
  private func handleStatusChange(from oldStatus: CastStatus, to newStatus: CastStatus) {
    if let oldApp = oldStatus.apps.first {
    }
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
        self.delegate?.castClient?(self, connectionTo: self.device, didFailWith: aStream.streamError as! NSError)
      }
    case Stream.Event.hasBytesAvailable:
      socketQueue.async {
        self.readStream()
      }
    case Stream.Event.endEncountered:
      NSLog("Input stream ended")
      disconnect()
      
      socketQueue.async {
        //        self.connect()
      }
    default: break
    }
  }
  
}

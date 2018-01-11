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

typealias CastMessage = Extensions_Api_CastChannel_CastMessage

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
  var namespace: CastNamespace
  var destinationId: String
  var payload: [String: Any]
  
  init(id: Int, namespace: CastNamespace, destinationId: String, payload: [String: Any]) {
    self.id = id
    self.namespace = namespace
    self.destinationId = destinationId
    self.payload = payload
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
  
  private var cancelled = false
  
  private var inputStream: InputStream!
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
    heartbeatTimers.forEach({ self.stopBeating(id: $0.key) })
    
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
    
    cancelled = true
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
    
    do {
      let message = try connectMessage()
      
      try write(data: message)
      
      //            NSLog("CONNECT")
      
      DispatchQueue.main.async {
        self.startBeating(id: CastConstants.receiverName)
        do {
          try self.requestStatus()
        } catch {
          NSLog("Unable to send initial status request: \(error)")
        }
      }
    } catch {
      NSLog("Error sending connect message: \(error)")
    }
  }
  
  private lazy var reader: CASTV2PlatformReader = {
    return CASTV2PlatformReader(stream: self.inputStream)
  }()
  
  fileprivate func readStream() {
    do {
      reader.readStream()
      
      while let payload = reader.nextMessage() {
        let message = try CastMessage(serializedData: payload)
        
        if message.payloadType == .string {
          if let messageData = message.payloadUtf8.data(using: .utf8) {
            handleJSONMessage(with: messageData, originalMessage: message)
          } else {
            NSLog("Unable to get UTF8 JSON data from message")
          }
        }
      }
    } catch {
      NSLog("Error reading: \(error)")
    }
  }
  
  // MARK: - Heartbeat
  
  private var heartbeatTimers = [String: Timer]()
  
  private func startBeating(id: String) {
    guard heartbeatTimers["id"] == nil else {
      NSLog("Tried to start heartbeat to \(id), but another heartbeat is already in effect for this endpoint")
      return
    }
    
    sendPing(to: id)
    
    heartbeatTimers[id] = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(sendPing(_:)), userInfo: ["id": id], repeats: true)
  }
  
  private func stopBeating(id: String) {
    guard heartbeatTimers[id] != nil else { return }
    
    heartbeatTimers[id]!.invalidate()
    heartbeatTimers[id] = nil
  }
  
  @objc private func sendPing(_ sender: Timer?) {
    guard outputStream != nil else { return }
    guard let info = sender?.userInfo as? [String: String] else { return }
    guard let id  = info["id"] else { return }
    
    sendPing(to: id)
  }
  
  private func sendPing(to destinationId: String) {
    do {
      let message = try heartbeatMessage(to: destinationId)
      
      try write(data: message)
    } catch {
      NSLog("Error sending heartbeat message to \(destinationId): \(error)")
    }
  }
  
  // MARK: - Message builder
  
  private func encodePayload(with dict: [String:Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: dict, options: [])
    
    return String(data: data, encoding: .utf8)!
  }
  
  private lazy var senderName: String = {
    let rand = arc4random_uniform(90)
    return "sender-\(rand)"
  }()
  
  private func jsonMessage(with payload: [String: Any], namespace: CastNamespace, destinationId: String = CastConstants.receiverName) throws -> Data {
    var effectivePayload = payload
    
    // fill in the request id if needed
    if payload[CastJSONPayloadKeys.requestId] == nil {
      if let rawType = payload[CastJSONPayloadKeys.type] as? String {
        if let type = CastMessageType(rawValue: rawType), type.needsRequestId {
          effectivePayload[CastJSONPayloadKeys.requestId] = nextRequestId()
        }
      }
    }
    
    let load = try encodePayload(with: effectivePayload)
    
    //        NSLog("\(effectivePayload)")
    
    let message = CastMessage.with {
      $0.protocolVersion = .castv210
      $0.sourceID = senderName
      $0.destinationID = destinationId
      $0.namespace = namespace.rawValue
      $0.payloadType = .string
      $0.payloadUtf8 = load
      // even though we are not using the binary payload for anything, the builder will crash if we don't specify one
      $0.payloadBinary = Data()
    }
    
    
    return try message.serializedData()
  }
  
  private lazy var currentRequestId = Int(arc4random_uniform(800))
  
  private func nextRequestId() -> Int {
    currentRequestId += 1
    
    return currentRequestId
  }
  
  private func connectMessage() throws -> Data {
    return try jsonMessage(with: [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue], namespace: .connection)
  }
  
  private func heartbeatMessage(to destinationId: String) throws -> Data {
    return try jsonMessage(with: [CastJSONPayloadKeys.type: CastMessageType.ping.rawValue], namespace: .heartbeat, destinationId: destinationId)
  }
  
  private func statusMessage() throws -> Data {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue
    ]
    
    return try jsonMessage(with: payload, namespace: .receiver)
  }
  
  // MARK - Request response
  
  private typealias CastResponseHandler = (CastError?, JSON?) -> Void
  
  private var responseHandlers = [Int: CastResponseHandler]()
  
  private func send(request: CastRequest, response: CastResponseHandler?) {
    responseHandlers[request.id] = response
    
    do {
      //Don't want requestId for connect
      if request.namespace != .connection {
        request.payload[CastJSONPayloadKeys.requestId] = request.id
      }
      
      
      let message = try jsonMessage(with: request.payload, namespace: request.namespace, destinationId: request.destinationId)
      try write(data: message)
    } catch {
      callResponseHandler(for: request.id, with: .request(error.localizedDescription), response: nil)
    }
  }
  
  private func callResponseHandler(for requestId: Int, with error: CastError?, response: JSON?) {
    DispatchQueue.main.async {
      self.responseHandlers[requestId]?(error, response)
      self.responseHandlers[requestId] = nil
    }
  }
  
  // MARK: - Public messages
  
  public func getAppAvailability(apps: [CastApp], completion: @escaping (CastError?, AppAvailability?) -> Void) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.availableApps.rawValue,
      CastJSONPayloadKeys.appId: apps.map { $0.id }
    ]
    
    let request = CastRequest(id: nextRequestId(), namespace: .receiver, destinationId: CastConstants.receiverName, payload: payload)
    
    send(request: request) { (error, json) in
      guard error == nil, let json = json else {
        if let error = error {
          completion(CastError.launch(error.localizedDescription), nil)
        } else {
          completion(CastError.launch("Unkown error"), nil)
        }
        
        return
      }
      
      let availability = AppAvailability(json: json)
      
      completion(nil, availability)
    }
  }
  
  public func join(app: CastApp? = nil, completion: @escaping (CastError?, CastApp?) -> Void) {
    guard let target = app ?? currentStatus?.apps.first else {
      completion(CastError.session("No Apps Running"), nil)
      return
    }
    
    if target == connectedApp {
      completion(nil, target)
    } else if let existing = currentStatus?.apps.first(where: { $0.id == target.id }) {
      connect(to: existing)
      completion(nil, existing)
    } else {
      let payload: [String: Any] = [
        CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue
      ]
      
      let request = CastRequest(id: nextRequestId(), namespace: .receiver, destinationId: CastConstants.receiverName, payload: payload)
      
      send(request: request) { [weak self] (error, json) in
        guard error == nil, let json = json else {
          if let error = error {
            completion(CastError.launch(error.localizedDescription), nil)
          } else {
            completion(CastError.launch("Unkown error"), nil)
          }
          
          return
        }
        
        let status = CastStatus(json: json)
        
        guard let app = status.apps.first else {
          completion(CastError.launch("Unable to get launched app instance"), nil)
          return
        }
        
        self?.connect(to: app)
        completion(nil, app)
      }
    }
  }
  
  public func launch(appId: CastAppIdentifier, completion: @escaping (CastError?, CastApp?) -> Void) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.launch.rawValue,
      CastJSONPayloadKeys.appId: appId.rawValue
    ]
    
    let request = CastRequest(id: nextRequestId(), namespace: .receiver, destinationId: CastConstants.receiverName, payload: payload)
    
    send(request: request) { [weak self] (error, json) in
      guard error == nil, let json = json else {
        if let error = error {
          completion(CastError.launch(error.localizedDescription), nil)
        } else {
          completion(CastError.launch("Unkown error"), nil)
        }
        
        return
      }
      
      let status = CastStatus(json: json)
      
      guard let app = status.apps.first else {
        completion(CastError.launch("Unable to get launched app instance"), nil)
        return
      }
      
      self?.connect(to: app)
      completion(nil, app)
    }
  }
  
  public func launchApp(identifier: String, completionHandler: @escaping @convention(block) (NSError?, CastApp?) -> Void) {
    // this method is provided for objective-c compatibility
    guard let id = CastAppIdentifier(rawValue: identifier) else {
      NSLog("Invalid app identifier: \(identifier)")
      return
    }
    
    launch(appId: id) { (error, app) in
      if let error = error {
        completionHandler(error as NSError, nil)
      } else {
        completionHandler(nil, app)
      }
    }
  }
  
  public func leave(app: CastApp? = nil) {
    guard let target = app ?? currentStatus?.apps.first else { return }
    
    disconnect(app: target)
  }
  
  @nonobjc public func stop(app: CastApp) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.stop.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId
    ]
    let request = CastRequest(id: nextRequestId(), namespace: .receiver, destinationId: CastConstants.receiverName, payload: payload)
    
    send(request: request, response: nil)
  }
  
  public func stopApp(_ app: CastApp) {
    // this method is provided for objective-c compatibility
    stop(app: app)
  }
  
  public func stopCurrentApp() {
    guard let app = currentStatus?.apps.first else { return }
    
    stop(app: app)
  }
  
  public func load(media: CastMedia, with app: CastApp, completion: @escaping (CastError?, CastMediaStatus?) -> Void) {
    guard outputStream != nil else { return }
    
    var payload = media.dict
    payload[CastJSONPayloadKeys.type] = CastMessageType.load.rawValue
    payload[CastJSONPayloadKeys.sessionId] = app.sessionId
    
    let request = CastRequest(id: nextRequestId(), namespace: .media, destinationId: app.transportId, payload: payload)
    send(request: request) { error, json in
      guard error == nil, let json = json else {
        if let error = error {
          completion(CastError.load(error.localizedDescription), nil)
        } else {
          completion(CastError.load("Unkown error"), nil)
        }
        
        return
      }
      
      let mediaStatus = CastMediaStatus(json: json)
      completion(nil, mediaStatus)
    }
  }
  
  public func loadMedia(_ media: CastMedia, usingApp app: CastApp, completionHandler: @escaping @convention(block) (NSError?, CastMediaStatus?) -> Void) {
    // this method is provided for objective-c compatibility
    load(media: media, with: app, completion: { error, status in
      if let error = error {
        completionHandler(error as NSError, nil)
      } else {
        completionHandler(nil, status)
      }
    })
  }
  
  public func requestMediaStatus(for app: CastApp, mediaSessionId: Int? = nil, completion: ((CastError?, CastMediaStatus?) -> Void)? = nil) {
    guard outputStream != nil else { return }
    
    var payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId
    ]
    
    if let mediaSessionId = mediaSessionId {
      payload[CastJSONPayloadKeys.mediaSessionId] = mediaSessionId
    }
    
    let request = CastRequest(id: nextRequestId(), namespace: .media, destinationId: app.transportId, payload: payload)
    send(request: request) { error, json in
      guard error == nil, let json = json else {
        if let error = error {
          completion?(CastError.load(error.localizedDescription), nil)
        } else {
          completion?(CastError.load("Unkown error"), nil)
        }
        
        return
      }
      
      let mediaStatus = CastMediaStatus(json: json)
      completion?(nil, mediaStatus)
    }
  }
  
  public func requestMediaStatusForApp(_ app: CastApp, mediaSessionId: Int) {
    // this method is provided for objective-c compatibility
    requestMediaStatus(for: app, mediaSessionId: mediaSessionId, completion: nil)
  }
  
  public func requestStatus() throws {
    guard outputStream != nil else { return }
    
    let message = try statusMessage()
    
    try write(data: message)
  }
  
  
  // MARK: - Message handling
  
  private func handleJSONMessage(with json: Data?, originalMessage: CastMessage) {
    guard let data = json else { return }
    guard data.count > 0 else { return }
    
    let json = try! JSON(data: data)
    
    if let requestId = json[CastJSONPayloadKeys.requestId].int {
      //            NSLog("Received response for previously sent request \(requestId), calling handler")
      callResponseHandler(for: requestId, with: nil, response: json)
    }
    
    guard let rawType = json["type"].string else { return }
    
    guard let type = CastMessageType(rawValue: rawType) else { return }
    
    switch type {
    case .pong:
      // connection confirmed with pong
      if !self.isConnected {
        self.isConnected = true
      }
    //            NSLog("PONG from \(originalMessage.sourceId)")
    case .close:
      if originalMessage.sourceID == CastConstants.receiverName {
        // device disconnected
        if self.isConnected {
          self.isConnected = false
        }
      }
    case .status:
      self.currentStatus = CastStatus(json: json)
    case .mediaStatus:
      self.currentMediaStatus = CastMediaStatus(json: json["status"])
    default: break
    }
  }
  
  private func connect(to app: CastApp) {
    //        NSLog("Connecting to \(app.displayName)")
    
    do {
      let payload = [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue]
      let message = try jsonMessage(with: payload, namespace: .connection, destinationId: app.transportId)
      
      try write(data: message)
      startBeating(id: app.transportId)
      connectedApp = app
    } catch {
      NSLog("Error connecting to app: \(error)")
    }
  }
  
  private func disconnect(app: CastApp) {
    //        NSLog("Disconnecting \(app.displayName)")
    
    do {
      let payload = [CastJSONPayloadKeys.type: CastMessageType.close.rawValue]
      let message = try jsonMessage(with: payload, namespace: .connection, destinationId: app.transportId)
      
      try write(data: message)
      stopBeating(id: app.transportId)
      connectedApp = nil
    } catch {
      NSLog("Error connecting to app: \(error)")
    }
  }
  
  private func handleStatusChange(from oldStatus: CastStatus, to newStatus: CastStatus) {
    if let oldApp = oldStatus.apps.first {
      if oldApp.transportId != newStatus.apps.first?.transportId {
        // stop sending heartbeats to closed app
        stopBeating(id: oldApp.transportId)
      }
    }
  }
  
}

extension CastClient: StreamDelegate {
  
  public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case Stream.Event.openCompleted:
      socketQueue.async {
        do {
          try self.sendConnectMessage()
        } catch {
          NSLog("Error sending connect message: \(error)")
        }
      }
    case Stream.Event.errorOccurred:
      NSLog("Stream error occurred: \(aStream.streamError.debugDescription)")
    case Stream.Event.hasBytesAvailable:
      socketQueue.async {
        self.readStream()
      }
    case Stream.Event.endEncountered:
      NSLog("Input stream ended")
      self.disconnect()
      self.connect()
    default: break
    }
  }
  
}

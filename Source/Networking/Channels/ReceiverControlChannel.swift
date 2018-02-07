//
//  ReceiverControlChannel.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation
import Result
import SwiftyJSON

class ReceiverControlChannel: CastChannel {
  override weak var sink: RequestDispatchable! {
    didSet {
      if let _ = sink {
        requestStatus()
      }
    }
  }
  
  private var delegate: ReceiverControlChannelDelegate? {
    return sink as? ReceiverControlChannelDelegate
  }
  
  init() {
    super.init(namespace: CastNamespace.receiver)
  }
  
  override func handleResponse(_ json: JSON, sourceId: String) {
    guard let rawType = json["type"].string else { return }
    
    guard let type = CastMessageType(rawValue: rawType) else {
      print("Unknown type: \(rawType)")
      print(json)
      return
    }
    
    switch type {
    case .status:
      delegate?.channel(self, didReceive: CastStatus(json: json))
      
    default:
      print(rawType)
    }
  }
  
  public func getAppAvailability(apps: [CastApp], completion: @escaping (Result<AppAvailability, CastError>) -> Void) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.availableApps.rawValue,
      CastJSONPayloadKeys.appId: apps.map { $0.id }
    ]
    
    let request = sink.request(withNamespace: namespace,
                                       destinationId: CastConstants.receiver,
                                       payload: payload)
    
    send(request) { result in
      switch result {
      case .success(let json):
        completion(Result(value: AppAvailability(json: json)))
      case .failure(let error):
        completion(Result(error: CastError.launch(error.localizedDescription)))
      }
    }
  }
  
  public func requestStatus(completion: ((Result<CastStatus, CastError>) -> Void)? = nil) {
    let request = sink.request(withNamespace: namespace,
                                       destinationId: CastConstants.receiver,
                                       payload: [CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue])
    
    if let completion = completion {
      send(request) { result in
        switch result {
        case .success(let json):
          completion(Result(value: CastStatus(json: json)))
          
        case .failure(let error):
          completion(Result(error: error))
        }
      }
    } else {
      send(request)
    }
  }
  
  func launch(appId: CastAppIdentifier, completion: @escaping (Result<CastApp, CastError>) -> Void) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.launch.rawValue,
      CastJSONPayloadKeys.appId: appId.rawValue
    ]
    
    let request = sink.request(withNamespace: namespace,
                                       destinationId: CastConstants.receiver,
                                       payload: payload)
    
    send(request) { result in
      switch result {
      case .success(let json):
        guard let app = CastStatus(json: json).apps.first else {
          completion(Result(error: CastError.launch("Unable to get launched app instance")))
          return
        }
        
        completion(Result(value: app))
        
      case .failure(let error):
        completion(Result(error: error))
      }
      
    }
  }
  
  public func stop(app: CastApp) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.stop.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId
    ]
    
    let request = sink.request(withNamespace: namespace,
                                       destinationId: CastConstants.receiver,
                                       payload: payload)
    
    send(request)
  }
  
  public func setVolume(_ volume: Float) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.setVolume.rawValue,
      CastJSONPayloadKeys.volume: [CastJSONPayloadKeys.level: volume]
    ]
    
    let request = sink.request(withNamespace: namespace,
                                 destinationId: CastConstants.receiver,
                                 payload: payload)
    
    send(request)
  }
  
  public func setMuted(_ isMuted: Bool) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.setVolume.rawValue,
      CastJSONPayloadKeys.volume: [CastJSONPayloadKeys.muted: isMuted]
    ]
    
    let request = sink.request(withNamespace: namespace,
                                 destinationId: CastConstants.receiver,
                                 payload: payload)
    
    send(request)
  }
}

protocol ReceiverControlChannelDelegate: RequestDispatchable {
  func channel(_ channel: ReceiverControlChannel, didReceive status: CastStatus)
}

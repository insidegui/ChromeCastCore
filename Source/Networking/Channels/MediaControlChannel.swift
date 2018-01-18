//
//  MediaControlChannel.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation
import Result
import SwiftyJSON

class MediaControlChannel: CastChannel {
  private var delegate: MediaControlChannelDelegate? {
    return sink as? MediaControlChannelDelegate
  }
  
  init() {
    super.init(namespace: CastNamespace.media)
  }
  
  override func handleResponse(_ json: JSON, sourceId: String) {
    guard let rawType = json["type"].string else { return }
    
    guard let type = CastMessageType(rawValue: rawType) else {
      print("Unknown type: \(rawType)")
      print(json)
      return
    }
    
    switch type {
    case .mediaStatus:
      delegate?.channel(self, didReceive: CastMediaStatus(json: json))
      
    default:
      print(rawType)
    }
  }
  
  public func requestMediaStatus(for app: CastApp, completion: ((Result<CastMediaStatus, CastError>) -> Void)? = nil) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId
    ]
    
    let request = sink.request(withNamespace: namespace,
                                       destinationId: app.transportId,
                                       payload: payload)
    
    if let completion = completion {
      send(request) { result in
        switch result {
        case .success(let json):
          completion(Result(value: CastMediaStatus(json: json)))
          
        case .failure(let error):
          completion(Result(error: error))
        }
      }
    } else {
      send(request)
    }
  }
  
  public func sendPause(for app: CastApp, mediaSessionId: Int) {
    send(.pause, for: app, mediaSessionId: mediaSessionId)
  }
  
  public func sendPlay(for app: CastApp, mediaSessionId: Int) {
    send(.play, for: app, mediaSessionId: mediaSessionId)
  }
  
  public func sendStop(for app: CastApp, mediaSessionId: Int) {
    send(.stop, for: app, mediaSessionId: mediaSessionId)
  }
  
  public func sendSeek(to currentTime: Float, for app: CastApp, mediaSessionId: Int) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.seek.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId,
      CastJSONPayloadKeys.currentTime: currentTime,
      CastJSONPayloadKeys.mediaSessionId: mediaSessionId
    ]
    
    let request = sink.request(withNamespace: namespace,
                                 destinationId: app.transportId,
                                 payload: payload)
    
    send(request)
  }
  
  private func send(_ message: CastMessageType, for app: CastApp, mediaSessionId: Int) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: message.rawValue,
      CastJSONPayloadKeys.mediaSessionId: mediaSessionId
    ]
    
    let request = sink.request(withNamespace: namespace,
                                 destinationId: app.transportId,
                                 payload: payload)
    
    send(request)
  }
  
  public func load(media: CastMedia, with app: CastApp, completion: @escaping (Result<CastMediaStatus, CastError>) -> Void) {
    var payload = media.dict
    payload[CastJSONPayloadKeys.type] = CastMessageType.load.rawValue
    payload[CastJSONPayloadKeys.sessionId] = app.sessionId
    
    let request = sink.request(withNamespace: namespace,
                                       destinationId: app.transportId,
                                       payload: payload)

    send(request) { result in
      switch result {
      case .success(let json):
        completion(Result(value: CastMediaStatus(json: json)))
        
      case .failure(let error):
        completion(Result(error: CastError.load(error.localizedDescription)))
      }
    }
  }
}

protocol MediaControlChannelDelegate: class {
  func channel(_ channel: MediaControlChannel, didReceive mediaStatus: CastMediaStatus)
}

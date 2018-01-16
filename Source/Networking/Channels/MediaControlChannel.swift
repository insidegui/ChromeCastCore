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
  init() {
    super.init(namespace: .media)
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
      client.channel(self, didReceive: CastMediaStatus(json: json["status"]))
      
    default:
      print(rawType)
    }
  }
  
  public func requestMediaStatus(for app: CastApp, completion: ((Result<CastMediaStatus, CastError>) -> Void)? = nil) {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue,
      CastJSONPayloadKeys.sessionId: app.sessionId
    ]
    
    let request = client.request(withNamespace: namespace,
                                       destinationId: app.transportId,
                                       payload: payload)
    
    if let completion = completion {
      client.send(request) { result in
        switch result {
        case .success(let json):
          completion(Result(value: CastMediaStatus(json: json)))
          
        case .failure(let error):
          completion(Result(error: error))
        }
      }
    } else {
      client.send(request)
    }
  }
  
  public func load(media: CastMedia, with app: CastApp, completion: @escaping (Result<CastMediaStatus, CastError>) -> Void) {
    var payload = media.dict
    payload[CastJSONPayloadKeys.type] = CastMessageType.load.rawValue
    payload[CastJSONPayloadKeys.sessionId] = app.sessionId
    
    let request = client.request(withNamespace: namespace,
                                       destinationId: app.transportId,
                                       payload: payload)

    client.send(request) { result in
      switch result {
      case .success(let json):
        completion(Result(value: CastMediaStatus(json: json)))
        
      case .failure(let error):
        completion(Result(error: CastError.load(error.localizedDescription)))
      }
    }
  }
}

protocol MediaControlChannelDelegate {
  func channel(_ channel: MediaControlChannel, didReceive mediaStatus: CastMediaStatus)
}

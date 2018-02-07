//
//  CastMediaStatus.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation
import SwiftyJSON

public enum CastMediaPlayerState: String {
  case buffering = "BUFFERING"
  case playing = "PLAYING"
  case paused = "PAUSED"
  case stopped = "STOPPED"
}

public final class CastMediaStatus: NSObject {
  
  public var mediaSessionId: Int = 0
  public var playbackRate: Int = 1
  public var playerState: CastMediaPlayerState = .buffering
  public var currentTime: Double = 0
  public var metadata: JSON?
  public var contentID: String?
  
  public var state: String {
    return playerState.rawValue
  }
  
  public override var description: String {
    return "MediaStatus(mediaSessionId: \(mediaSessionId), playbackRate: \(playbackRate), playerState: \(playerState.rawValue), currentTime: \(currentTime))"
  }
  
}

extension CastMediaStatus {
  
  convenience init(json: JSON) {
    self.init()
    
    if let sessionId = json[CastJSONPayloadKeys.mediaSessionId].int {
      self.mediaSessionId = sessionId
    }
    
    if let playbackRate = json[CastJSONPayloadKeys.playbackRate].int {
      self.playbackRate = playbackRate
    }
    
    if let rawState = json[CastJSONPayloadKeys.playerState].string {
      if let state = CastMediaPlayerState(rawValue: rawState) {
        self.playerState = state
      }
    }
    
    if let currentTime = json[CastJSONPayloadKeys.currentTime].double {
      self.currentTime = currentTime
    }
    
    metadata = json[CastJSONPayloadKeys.media][CastJSONPayloadKeys.metadata]
    
    if let contentID = json[CastJSONPayloadKeys.media][CastJSONPayloadKeys.contentId].string, let data = contentID.data(using: .utf8) {
      self.contentID = (try? JSON(data: data))?[CastJSONPayloadKeys.contentId].string ?? contentID
    }
  }
}

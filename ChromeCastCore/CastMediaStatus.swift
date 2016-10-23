//
//  CastMediaStatus.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

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
        
        guard let status = json.array?.first else { return }
        
        if let sessionId = status["mediaSessionId"].int {
            self.mediaSessionId = sessionId
        }
        
        if let playbackRate = status["playbackRate"].int {
            self.playbackRate = playbackRate
        }
        
        if let rawState = status["playerState"].string {
            if let state = CastMediaPlayerState(rawValue: rawState) {
                self.playerState = state
            }
        }
        
        if let currentTime = status["currentTime"].double {
            self.currentTime = currentTime
        }
    }
    
}

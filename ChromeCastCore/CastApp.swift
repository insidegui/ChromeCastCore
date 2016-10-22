//
//  CastApp.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

public enum CastAppIdentifier: String {
    case defaultMediaPlayer = "CC1AD845"
    case youTube = "YouTube"
}

public final class CastApp: NSObject {
    
    public var id: String = ""
    public var displayName: String = ""
    public var isIdleScreen: Bool = false
    public var sessionId: String = ""
    public var statusText: String = ""
    public var transportId: String = ""
    
}

extension CastApp {
    
    convenience init(json: JSON) {
        self.init()
        
        if let id = json[CastJSONPayloadKeys.appId].string {
            self.id = id
        }
        
        if let displayName = json[CastJSONPayloadKeys.displayName].string {
            self.displayName = displayName
        }
        
        if let isIdleScreen = json[CastJSONPayloadKeys.isIdleScreen].bool {
            self.isIdleScreen = isIdleScreen
        }
        
        if let sessionId = json[CastJSONPayloadKeys.sessionId].string {
            self.sessionId = sessionId
        }
        
        if let statusText = json[CastJSONPayloadKeys.statusText].string {
            self.statusText = statusText
        }
        
        if let transportId = json[CastJSONPayloadKeys.transportId].string {
            self.transportId = transportId
        }
    }
    
    public override var description: String {
        return "CastApp(id: \(id), displayName: \(displayName), isIdleScreen: \(isIdleScreen), sessionId: \(sessionId), statusText: \(statusText), transportId: \(transportId))"
    }
    
}

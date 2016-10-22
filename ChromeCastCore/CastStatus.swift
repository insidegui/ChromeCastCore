//
//  CastStatus.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

public final class CastStatus: NSObject {
    
    public var volume: Double = 0.976
    public var muted: Bool = false
    public var apps: [CastApp] = []
    
    public override var description: String {
        return "CastStatus(volume: \(volume), muted: \(muted), apps: \(apps))"
    }
    
}

extension CastStatus {
    
    convenience init(json: JSON) {
        self.init()
        
        let status = json[CastJSONPayloadKeys.status]
        let volume = status[CastJSONPayloadKeys.volume]
        
        if let volume = volume[CastJSONPayloadKeys.level].double {
            self.volume = volume
        }
        if let muted = volume[CastJSONPayloadKeys.muted].bool {
            self.muted = muted
        }
        
        if let apps = status[CastJSONPayloadKeys.applications].array {
            self.apps = apps.flatMap(CastApp.init)
        }
    }
    
}

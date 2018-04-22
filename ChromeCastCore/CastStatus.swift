//
//  CastStatus.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

public final class CastStatus: NSObject, Codable {
    
    public var volume: Double = 0.976
    public var muted: Bool = false
    public var apps: [CastApp] = []
    
    public override var description: String {
        return "CastStatus(volume: \(volume), muted: \(muted), apps: \(apps))"
    }

    public enum CodingKeys: String, CodingKey {
        case volume = "volume"
        case muted = "muted"
        case apps = "applications"
    }
    
}

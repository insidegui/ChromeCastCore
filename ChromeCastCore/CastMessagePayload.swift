//
//  CastMessagePayload.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 22/04/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

final class CastMessagePayload: NSObject, Codable {
    var type: CastMessageType = CastMessageType.ping
    var requestId: String = ""
    var mediaStatus: [CastMediaStatus]?

    enum CodingKeys: String, CodingKey {
        case type
        case requestId
        case mediaStatus = "status"
    }
}

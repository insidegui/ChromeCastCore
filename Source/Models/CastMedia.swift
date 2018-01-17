//
//  CastMedia.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

public let CastMediaStreamTypeBuffered = "BUFFERED"
public let CastMediaStreamTypeLive = "LIVE"

public enum CastMediaStreamType: String {
    case buffered = "BUFFERED"
    case live = "LIVE"
}

public final class CastMedia: NSObject {
    
    public var title: String
    public var url: URL
    public var poster: URL
    
    public var autoplay: Bool = true
    public var currentTime: Double = 0.0
    
    public var contentType: String
    public var streamType: CastMediaStreamType = .buffered
    
    public init(title: String, url: URL, poster: URL, contentType: String, streamType: CastMediaStreamType = .buffered, autoplay: Bool = true, currentTime: Double = 0) {
        self.title = title
        self.url = url
        self.poster = poster
        self.contentType = contentType
        self.streamType = streamType
        self.autoplay = autoplay
        self.currentTime = currentTime
    }
    
    public convenience init(title: String, url: URL, poster: URL, contentType: String, streamType: String, autoplay: Bool, currentTime: Double) {
        guard let type = CastMediaStreamType(rawValue: streamType) else {
            fatalError("Invalid media stream type \(streamType)")
        }
        self.init(title: title, url: url, poster: poster, contentType: contentType, streamType: type, autoplay: autoplay, currentTime: currentTime)
    }
    
}

extension CastMedia {
    
    var dict: [String: Any] {
        return [
            CastJSONPayloadKeys.autoplay: autoplay,
            CastJSONPayloadKeys.activeTrackIds: [],
            CastJSONPayloadKeys.repeatMode: "REPEAT_OFF",
            CastJSONPayloadKeys.currentTime: currentTime,
            CastJSONPayloadKeys.media: [
                CastJSONPayloadKeys.contentId: url.absoluteString,
                CastJSONPayloadKeys.contentType: contentType,
                CastJSONPayloadKeys.streamType: streamType.rawValue,
                CastJSONPayloadKeys.metadata: [
                    CastJSONPayloadKeys.type: 0,
                    CastJSONPayloadKeys.metadataType: 0,
                    CastJSONPayloadKeys.title: title,
                    CastJSONPayloadKeys.images: [
                        [CastJSONPayloadKeys.url: poster.absoluteString]
                    ]
                ]
            ]
        ]
    }
    
}

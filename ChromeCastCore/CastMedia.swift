//
//  CastMedia.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

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
    
}

extension CastMedia {
    
    var dict: [String: Any] {
        return [
            "autoplay": autoplay,
            "activeTrackIds": [],
            "repeatMode": "REPEAT_OFF",
            "currentTime": currentTime,
            "media": [
                "contentId": url.absoluteString,
                "contentType": contentType,
                "streamType": streamType.rawValue,
                "metadata": [
                    "type": 0,
                    "metadataType": 0,
                    "title": title,
                    "images": [
                        ["url": poster.absoluteString]
                    ]
                ]
            ]
        ]
    }
    
}

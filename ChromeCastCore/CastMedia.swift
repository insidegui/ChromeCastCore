//
//  CastMedia.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 21/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

@objc public let CastMediaStreamTypeBuffered = "BUFFERED"
@objc public let CastMediaStreamTypeLive = "LIVE"

@objc public enum CastMediaStreamType: String {
    case buffered = "BUFFERED"
    case live = "LIVE"
}

@objc public final class CastMedia: NSObject {
    
    @objc public var title: String
    @objc public var url: URL
    @objc public var poster: URL
    
    @objc public var autoplay: Bool = true
    @objc public var currentTime: Double = 0.0
    
    @objc public var contentType: String
    @objc public var streamType: CastMediaStreamType = .buffered
    
    @objc public init(title: String, url: URL, poster: URL, contentType: String, streamType: CastMediaStreamType = .buffered, autoplay: Bool = true, currentTime: Double = 0) {
        self.title = title
        self.url = url
        self.poster = poster
        self.contentType = contentType
        self.streamType = streamType
        self.autoplay = autoplay
        self.currentTime = currentTime
    }
    
    @objc public convenience init(title: String, url: URL, poster: URL, contentType: String, streamType: String, autoplay: Bool, currentTime: Double) {
        guard let type = CastMediaStreamType(rawValue: streamType) else {
            fatalError("Invalid media stream type \(streamType)")
        }
        self.init(title: title, url: url, poster: poster, contentType: contentType, streamType: type, autoplay: autoplay, currentTime: currentTime)
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

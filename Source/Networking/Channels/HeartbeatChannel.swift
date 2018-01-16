//
//  CastHeartbeatChannel.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation
import SwiftyJSON

class HeartbeatChannel: CastChannel {
  private lazy var timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(sendPing), userInfo: nil, repeats: true)
  
  private let disconnectTimeout: TimeInterval = 10
  private var disconnectTimer: Timer? {
    willSet {
      disconnectTimer?.invalidate()
    }
    didSet {
      guard let timer = disconnectTimer else { return }
      
      RunLoop.main.add(timer, forMode: .commonModes)
    }
  }
  
  override weak var client: CastClient! {
    didSet {
      if let _ = client {
        startBeating()
      } else {
        timer.invalidate()
      }
    }
  }
  
  init() {
    super.init(namespace: .heartbeat)
  }
  
  override func handleResponse(_ json: JSON, sourceId: String) {
    if !client.isConnected {
      client.isConnected = true
    }
    
    guard let rawType = json["type"].string else { return }
    
    guard let type = CastMessageType(rawValue: rawType) else {
      print("Unknown type: \(rawType)")
      print(json)
      return
    }
    
    if type == .ping {
      print("PING from \(sourceId)")
    }

    disconnectTimer = Timer(timeInterval: disconnectTimeout,
                            target: self,
                            selector: #selector(handleTimeout),
                            userInfo: nil,
                            repeats: false)
  }

  private func startBeating() {
    _ = timer
    sendPing()
  }
  
  @objc private func sendPing() {
    let request = client.request(withNamespace: namespace,
                                       destinationId: CastConstants.transport,
                                       payload: [CastJSONPayloadKeys.type: CastMessageType.ping.rawValue])
    
    client.send(request)
  }
  
  @objc private func handleTimeout() {
    client.channelDidTimeout(self)
  }
}

protocol HeartbeatChannelDelegate {
  func channelDidTimeout(_ channel: HeartbeatChannel)
}

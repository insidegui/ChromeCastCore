//
//  CastHeartbeatChannel.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

class HeartbeatChannel: CastTextChannel {
  private lazy var timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(sendPing), userInfo: nil, repeats: true)
  
  override var client: CastClient! {
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

  private func startBeating() {
    _ = timer
    sendPing()
  }
  
  @objc private func sendPing() {
    let request = client.createRequest(withNamespace: namespace,
                                       destinationId: CastConstants.transport,
                                       payload: [CastJSONPayloadKeys.type: CastMessageType.ping.rawValue])
    
    client.send(request: request)
  }
}

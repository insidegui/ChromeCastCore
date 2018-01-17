//
//  DeviceConnectionChannel.swift
//  ChromeCastCore Mac
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

class DeviceConnectionChannel: CastChannel {
  override weak var client: CastClient! {
    didSet {
      if let _ = client {
        connect()
      }
    }
  }
  
  init() {
    super.init(namespace: CastNamespace.connection)
  }
  
  func connect() {
    let request = client.request(withNamespace: namespace,
                                 destinationId: CastConstants.receiver,
                                 payload: [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue])
    
    client.send(request)
  }
  
  func connect(to app: CastApp) {
    //        NSLog("Connecting to \(app.displayName)")
    
    let payload = [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue]
    let request = client.request(withNamespace: namespace,
                                 destinationId: app.transportId,
                                 payload: payload)
    
    client.send(request)
  }
  
  public func leave(_ app: CastApp) {
    let request = client.request(withNamespace: namespace,
                                 destinationId: app.transportId,
                                 payload: [CastJSONPayloadKeys.type: CastMessageType.close.rawValue])
    
    client.send(request)
  }
}

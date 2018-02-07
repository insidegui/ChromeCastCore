//
//  DeviceConnectionChannel.swift
//  ChromeCastCore Mac
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

class DeviceConnectionChannel: CastChannel {
  override weak var sink: RequestDispatchable! {
    didSet {
      if let _ = sink {
        connect()
      }
    }
  }
  
  init() {
    super.init(namespace: CastNamespace.connection)
  }
  
  func connect() {
    let request = sink.request(withNamespace: namespace,
                                 destinationId: CastConstants.receiver,
                                 payload: [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue])
    
    send(request)
  }
  
  func connect(to app: CastApp) {
    let request = sink.request(withNamespace: namespace,
                                 destinationId: app.transportId,
                                 payload: [CastJSONPayloadKeys.type: CastMessageType.connect.rawValue])
    
    send(request)
  }
  
  public func leave(_ app: CastApp) {
    let request = sink.request(withNamespace: namespace,
                                 destinationId: app.transportId,
                                 payload: [CastJSONPayloadKeys.type: CastMessageType.close.rawValue])
    
    send(request)
  }
}

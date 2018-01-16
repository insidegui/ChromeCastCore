//
//  DeviceAuthChannel.swift
//  ChromeCastCore Mac
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

class DeviceAuthChannel: CastChannel {
  init() {
    super.init(namespace: .auth)
  }
  
  public func sendAuthChallenge() throws {
    let message = Extensions_Api_CastChannel_DeviceAuthMessage.with({ (message) in
      message.challenge = Extensions_Api_CastChannel_AuthChallenge()
    })
    
    let request = client.request(withNamespace: namespace,
                                       destinationId: CastConstants.receiver,
                                       payload: try message.serializedData())

    client.send(request)
  }
}

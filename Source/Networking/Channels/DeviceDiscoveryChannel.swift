//
//  DeviceDiscoveryChannel.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

class DeviceDiscoveryChannel: CastChannel {
  init() {
    super.init(namespace: CastNamespace.discovery)
  }
  
  func requestDeviceInfo() {
    let payload: [String: Any] = [
      CastJSONPayloadKeys.type: CastMessageType.getDeviceInfo.rawValue,
      ]
    
    let request = client.request(withNamespace: namespace,
                                       destinationId: CastConstants.receiver,
                                       payload: payload)
    
    client.send(request) { result in
      switch result {
      case .success(let json):
        print(json)
        
      case .failure(let error):
        print(error)
      }
    }
  }
}

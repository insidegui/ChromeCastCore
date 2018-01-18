//
//  CastMultizoneStatus.swift
//  ChromeCastCore Mac
//
//  Created by Miles Hollingsworth on 1/18/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation
import SwiftyJSON

public class CastMultizoneStatus {
  public let devices: [CastMultizoneDevice]
  
  public init(devices: [CastMultizoneDevice]) {
    self.devices = devices
  }
}

extension CastMultizoneStatus {
  
  convenience init(json: JSON) {
    let status = json[CastJSONPayloadKeys.status]
    let devices = status[CastJSONPayloadKeys.devices].array?.map(CastMultizoneDevice.init) ?? []
    
    self.init(devices: devices)
  }
  
}

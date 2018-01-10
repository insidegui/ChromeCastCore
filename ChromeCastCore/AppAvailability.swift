//
//  AppAvailability.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/9/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Cocoa
import SwiftyJSON

public class AppAvailability: NSObject {
  public var availability = [String: Bool]()
}

extension AppAvailability {
  convenience init(json: JSON) {
    self.init()
    
    if let availability = json[CastJSONPayloadKeys.availability].dictionaryObject as? [String: String] {
      self.availability = availability.mapValues { $0 == "APP_AVAILABLE" }
    }
  }
}

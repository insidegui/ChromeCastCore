//
//  CastChannel.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation
import SwiftyJSON

public class CastChannel {
  let namespace: String
  weak var client: CastClient!
  
  init(namespace: String) {
    self.namespace = namespace
  }
  
  func handleResponse(_ json: JSON, sourceId: String) {
    print(json)
  }
  
  func handleResponse(_ data: Data, sourceId: String) {
    print("\n--Binary response--\n")
  }
}

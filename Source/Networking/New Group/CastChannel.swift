//
//  CastChannel.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

public class CastChannel {
  let namespace: String
  weak var client: CastClient!
  
  init(namespace: String) {
    self.namespace = namespace
  }
}

class CastTextChannel: CastChannel {
  func send(payload: [String: Any], toDestinationId destinationID: String, completion: CastResponseHandler?) {
    let request = client.createRequest(withNamespace: namespace,
                                       destinationId: CastConstants.transport,
                                       payload: payload)
  }
}

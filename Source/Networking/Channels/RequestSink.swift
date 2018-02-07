//
//  RequestDispatchable.swift
//  ChromeCastCore Mac
//
//  Created by Miles Hollingsworth on 1/17/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

protocol RequestDispatchable: class {
  func nextRequestId() -> Int
  
  func request(withNamespace namespace: String, destinationId: String, payload: [String: Any]) -> CastRequest
  func request(withNamespace namespace: String, destinationId: String, payload: Data) -> CastRequest
  
  func send(_ request: CastRequest, response: CastResponseHandler?)
}

extension RequestDispatchable {
  func request(withNamespace namespace: String, destinationId: String, payload: [String: Any]) -> CastRequest {
    var payload = payload
    let requestId = nextRequestId()
    payload[CastJSONPayloadKeys.requestId] = requestId
    
    return  CastRequest(id: requestId,
                        namespace: namespace,
                        destinationId: destinationId,
                        payload: payload)
  }
  
  func request(withNamespace namespace: String, destinationId: String, payload: Data) -> CastRequest {
    return  CastRequest(id: nextRequestId(),
                        namespace: namespace,
                        destinationId: destinationId,
                        payload: payload)
  }
}

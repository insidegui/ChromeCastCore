//
//  CastMessage.swift
//  ChromeCastCore
//
//  Created by Miles Hollingsworth on 1/16/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

extension CastMessage {
  static func encodedMessage(payload: [String: Any], namespace: String, sourceId: String, destinationId: String) throws -> Data {
    let json = try JSONSerialization.data(withJSONObject: payload, options: [])
    
    guard let jsonString = String(data: json, encoding: .utf8) else {
      fatalError("error forming json string")
    }
    
    let message = CastMessage.with {
      $0.protocolVersion = .castv210
      $0.sourceID = sourceId
      $0.destinationID = destinationId
      $0.namespace = namespace
      $0.payloadType = .string
      $0.payloadUtf8 = jsonString
    }
    
    return try message.serializedData()
  }
  
  static func encodedMessage(payload: Data, namespace: String, sourceId: String, destinationId: String) throws -> Data {
    let message = CastMessage.with {
      $0.protocolVersion = .castv210
      $0.sourceID = sourceId
      $0.destinationID = destinationId
      $0.namespace = namespace
      $0.payloadType = .binary
      $0.payloadBinary = payload
    }
    
    return try message.serializedData()
  }
}

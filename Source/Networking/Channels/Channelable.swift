//
//  Channelable.swift
//  ChromeCastCore Mac
//
//  Created by Miles Hollingsworth on 1/17/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Foundation

protocol Channelable: RequestDispatchable {
  var channels: [String: CastChannel] { get set }
  
  func addChannel(_ channel: CastChannel)
  func removeChannel(_ channel: CastChannel)
}

extension Channelable {
  public func addChannel(_ channel: CastChannel) {
    let namespace = channel.namespace
    guard channels[namespace] == nil else {
      print("Channel already attached for \(namespace)")
      return
    }
    
    channels[namespace] = channel
    channel.sink = self
  }
  
  public func removeChannel(_ channel: CastChannel) {
    let namespace = channel.namespace
    guard let channel = channels.removeValue(forKey: namespace) else {
      print("No channel attached for \(namespace)")
      return
    }
    
    channel.sink = nil
  }
}

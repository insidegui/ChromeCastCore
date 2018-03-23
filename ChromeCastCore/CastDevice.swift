//
//  CastDevice.swift
//  ChromeCastCore
//
//  Created by Guilherme Rambo on 19/10/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Foundation

@objc public final class CastDevice: NSObject, NSCopying {
    
    @objc public private(set) var id: String
    @objc public private(set) var name: String
    @objc public private(set) var hostName: String
    @objc public private(set) var address: Data
    @objc public private(set) var port: Int
    
    @objc init(id: String, name: String, hostName: String, address: Data, port: Int) {
        self.id = id
        self.name = name
        self.hostName = hostName
        self.address = address
        self.port = port
        
        super.init()
    }
    
    @objc public func copy(with zone: NSZone? = nil) -> Any {
        return CastDevice(id: self.id, name: self.name, hostName: self.hostName, address: self.address, port: self.port)
    }
    
    @objc public override var description: String {
        return "CastDevice(id: \(id), name: \(name), hostName:\(hostName), address:\(address), port:\(port))"
    }
    
}

//
//  CastV2PlatformReader.swift
//  ChromeCastCore Mac
//
//  Created by Miles Hollingsworth on 1/12/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

let maxBufferLength = 8192

import Foundation

class CastV2PlatformReader {
  let stream: InputStream
  var readPosition = 0
  var buffer = Data(capacity: maxBufferLength) {
    didSet {
      readPosition = 0
    }
  }
  
  init(stream: InputStream) {
    self.stream = stream
  }
  
  func readStream() {
    objc_sync_enter(self)
    defer { objc_sync_exit(self) }
    
    var totalBytesRead = 0
    let bufferSize = 32
    
    while self.stream.hasBytesAvailable {
      let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
      
      let bytesRead = self.stream.read(bytes, maxLength: bufferSize)
      
      if bytesRead < 0 { continue }
      
      self.buffer.append(Data(bytes: bytes, count: bytesRead))
      
      bytes.deallocate(capacity: bufferSize)
      
      totalBytesRead += bytesRead
    }
  }
  
  func nextMessage() -> Data? {
    objc_sync_enter(self)
    defer { objc_sync_exit(self) }
    
    let headerSize = MemoryLayout<UInt32>.size
    guard self.buffer.count - self.readPosition >= headerSize else { return nil }
    let header = self.buffer.withUnsafeBytes({ (pointer: UnsafePointer<Int8>) -> UInt32 in
      return pointer.advanced(by: self.readPosition).withMemoryRebound(to: UInt32.self, capacity: 1, { $0.pointee })
    })
    
    let payloadSize = Int(CFSwapInt32BigToHost(header))
    
    readPosition += headerSize
    
    let payloadEnd = self.readPosition + payloadSize

    guard self.buffer.count >= payloadEnd, self.buffer.count - self.readPosition >= payloadSize, payloadSize >= 0 else {
      //Message hasn't arrived
      self.readPosition -= headerSize
      return nil
    }
    
    let data = self.buffer.withUnsafeBytes({ (pointer: UnsafePointer<Int8>) -> Data in
      return Data(bytes: pointer.advanced(by: self.readPosition), count: payloadSize)
    })
    readPosition += payloadSize
    
    self.resetBufferIfNeeded()
    
    return data
  }
  
  private func resetBufferIfNeeded() {
    guard self.buffer.count >= maxBufferLength else { return }
    
    if readPosition == self.buffer.count {
      self.buffer = Data(capacity: maxBufferLength)
    } else {
      self.buffer = self.buffer.advanced(by: self.readPosition)
    }
  }
}

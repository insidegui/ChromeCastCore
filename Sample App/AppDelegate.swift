//
//  AppDelegate.swift
//  Sample App
//
//  Created by Miles Hollingsworth on 1/9/18.
//  Copyright © 2018 Guilherme Rambo. All rights reserved.
//

import Cocoa
import ChromeCastCore
import SwiftyJSON

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  let scanner = CastDeviceScanner()
  var clients = [String: CastClient]()
  
  @IBOutlet weak var window: NSWindow!
  
  var app: CastApp?
  
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    NotificationCenter.default.addObserver(forName: CastDeviceScanner.deviceListDidChange, object: scanner, queue: nil) { [unowned self] _ in
      for device in self.scanner.devices {
        if let existing = self.clients[device.id] {
          
        } else {
          let client = CastClient(device: device)
          self.clients[device.id] = client
          client.delegate = self
          client.connect()
        }
      }
    }
    
    scanner.startScanning()
  }
}

extension AppDelegate: CastClientDelegate {
  func castClient(_ client: CastClient, didConnectTo device: CastDevice) {
  }
  
  func castClient(_ client: CastClient, deviceStatusDidChange status: CastStatus) {
    guard client.connectedApp == nil else { return }
    
    guard let app = status.apps.first, app.id == CastAppIdentifier.googleAssistant.rawValue else { return }
    
    client.join(app: app) { (err, app) in
      guard let app = app else { return }
      
      client.requestMediaStatus(for: app)
    }
  }
  
  func castClient(_ client: CastClient, mediaStatusDidChange status: CastMediaStatus) {
    guard let title = status.metadata?["title"].string,
      let albumName = status.metadata?["albumName"].string else { return }
    
    let source = """
    tell application "iTunes"
      play (every track of playlist "Library" whose name is "\(title)" and album is "\(albumName)")
      set player position to \(status.currentTime)
    end tell
    """
    
    var error: NSDictionary?
    
    if let script = NSAppleScript(source: source) {
      let output = script.executeAndReturnError(&error)
      
      if let error = error {
        print("error: \(error)")
      } else {
        client.stopCurrentApp()
      }
    }
  }
}

//
//  StatusItemController.swift
//  CastSync
//
//  Created by Miles Hollingsworth on 1/10/18.
//  Copyright © 2018 Miles Hollingsworth. All rights reserved.
//

import Cocoa
import ChromeCastCore

class StatusItemController: NSObject {
  let statusItem = NSStatusBar.system.statusItem(withLength: 36)
  lazy var statusItemView = StatusItemView(statusItem: self.statusItem, controller: self)
  
  let scanner = CastDeviceScanner()
  var clients = [String: CastClient]()
  
  override init() {
    super.init()
    
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(devicesChanged),
                                           name: CastDeviceScanner.deviceListDidChange,
                                           object: scanner)
    
    
    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu
    setMenus()
    statusItem.title = ""
    statusItem.image = NSImage(named: NSImage.Name(rawValue: "Cast"))
    
    statusItem.highlightMode = true
  }
  
  func handleClick(_ event: NSEvent) {
    
  }
  
  @objc func devicesChanged() {
    setMenus(devices: scanner.devices)
  }
  
  func setMenus(devices: [CastDevice] = []) {
    guard let menu = statusItem.menu else { return }
    
    if menu.items.count > 0 {
      menu.removeAllItems()
    }
    
    if devices.count > 0 {
      let items = devices.map { NSMenuItem(title: $0.name, action: #selector(handleSelection(item:)), keyEquivalent: "") }
      
      for item in items {
        item.target = self
        menu.addItem(item)
      }
    } else {
      let item = NSMenuItem(title: "Scanning", action: #selector(handleSelection(item:)), keyEquivalent: "")
      menu.addItem(item)
    }
  }
  
  @objc func handleSelection(item: NSMenuItem) {
    guard let index = statusItem.menu?.items.index(of: item) else { return }
    
    let device = scanner.devices[index]
    
    let client = CastClient(device: device)
    self.clients[device.id] = client
    client.delegate = self
    client.connect()
  }
  
  @objc func handleRefresh() {
    print("refresh")
  }
  
  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    return true
  }
}

extension StatusItemController: NSMenuDelegate {
  func menuWillOpen(_ menu: NSMenu) {
    scanner.startScanning()
  }
}

extension StatusItemController: CastClientDelegate {
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

//
//  AppDelegate.swift
//  CastSync
//
//  Created by Miles Hollingsworth on 1/9/18.
//  Copyright © 2018 Miles Hollingsworth. All rights reserved.
//

import Cocoa
import ChromeCastCore

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  let scanner = CastDeviceScanner()
  var clients = [String: CastClient]()
  
  @IBOutlet weak var window: NSWindow!
  
  let menuBarController = StatusItemController()
  
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    
  }
  
  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }
}

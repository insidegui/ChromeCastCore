//
//  StatusItemView.swift
//  CastSync
//
//  Created by Miles Hollingsworth on 1/10/18.
//  Copyright © 2018 Miles Hollingsworth. All rights reserved.
//

import Cocoa

class StatusItemView: NSView {

  weak var statusItemController: StatusItemController!
  let iconView = IconView()
  var statusItem: NSStatusItem!
  
  var isSelected = false {
    didSet {
      setNeedsDisplay(bounds)
    }
  }
  
  convenience init(statusItem: NSStatusItem, controller: StatusItemController) {
    self.init()

    self.statusItem = statusItem
    self.statusItemController = controller
    
    addSubview(iconView)
    
    addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-4-[iconView]-4-|",
                                                  metrics: nil,
                                                  views: ["iconView": iconView]))
    
    addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-3-[iconView]-4-|",
                                                  metrics: nil,
                                                  views: ["iconView": iconView]))
  }
  
    override func draw(_ dirtyRect: NSRect) {
      NSGraphicsContext.saveGraphicsState()
      
      statusItem.drawStatusBarBackground(in: self.bounds, withHighlight: isSelected)
      
      NSGraphicsContext.restoreGraphicsState()
    }
  
  
//  override func mouseDown(with event: NSEvent) {
//    isSelected = !isSelected
//    
//    statusItemController.handleClick(event)
//  }
}

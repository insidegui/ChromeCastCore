//
//  IconView.swift
//  CastSync
//
//  Created by Miles Hollingsworth on 1/10/18.
//  Copyright © 2018 Miles Hollingsworth. All rights reserved.
//

import Cocoa

class IconView: NSView {

  let imageView = NSImageView(image: NSImage(named: NSImage.Name(rawValue: "Cast"))!)
  
  convenience init() {
    self.init(frame: .zero )
    
    translatesAutoresizingMaskIntoConstraints = false
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)
    
    addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[imageView]|",
                                                  metrics: nil, views: ["imageView": imageView]))
    addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[imageView]|",
                                                  metrics: nil, views: ["imageView": imageView]))
  }
  
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
}

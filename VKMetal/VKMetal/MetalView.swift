//
//  MetalView.swift
//  VKMetal
//
//  Created by Vivian Keating on 1/1/15.
//  Copyright (c) 2015 Vivian Keating. All rights reserved.
//

import UIKit

class MetalView: UIView {

    let metalLayer = CAMetalLayer()

    func prepareForDrawing(){
        
        metalLayer.device = MetalViewController.sharedInstance.device
        
        metalLayer.pixelFormat = .BGRA8Unorm
        metalLayer.framebufferOnly = true
        
        // These two lines set the number of pixels that the layer will render
        
        let contentScale = UIScreen.mainScreen().scale
        metalLayer.drawableSize = CGSize(width: bounds.size.width * contentScale,
            height: bounds.size.height * contentScale)
        
        // For performance
        metalLayer.drawsAsynchronously = true;
        metalLayer.frame = self.frame
        layer.addSublayer(metalLayer)
        
        opaque = true

        
    }
    
    
    
}

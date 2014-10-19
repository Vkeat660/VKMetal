//
//  MainViewController.swift
//  VKMetal
//
//  Created by Vivian Keating on 10/18/14.
//  Copyright (c) 2014 Vivian Keating. All rights reserved.
//

import UIKit
import Metal
import QuartzCore

class MainViewController: UIViewController {
    
    let device = MTLCreateSystemDefaultDevice()
    let metalLayer = CAMetalLayer()
    
    var vertexBuffer : MTLBuffer?
    var colorBuffer  : MTLBuffer?
    var pipelineState : MTLRenderPipelineState?
    var commandQueue : MTLCommandQueue?
    
    var displayLink : CADisplayLink?
    
    let vertexData : [Float] = [ 0.0,  0.6,  0.0,
                                -0.6, -0.6,  0.0,
                                 0.6, -0.6,  0.0]
    
    let colorData  : [Float] = [ 0.0, 0.0, 1.0, 1.0,
                                 0.0, 1.0, 0.0, 1.0,
                                 1.0, 0.0, 0.0, 1.0]
   
    override func viewDidLoad() {
        
        super.viewDidLoad()
        view.backgroundColor = UIColor.magentaColor()
        
        setupMetalLayer()
        setupVertexBuffer()
        setupPipeline()
        
        commandQueue = device.newCommandQueue()
        displayLink = CADisplayLink(target: self, selector: Selector("update"))
        displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        
        
    }
    
    func setupMetalLayer() {
        
        metalLayer.device          = device
        metalLayer.pixelFormat     = .BGRA8Unorm
        metalLayer.frame           = view.layer.frame
        metalLayer.framebufferOnly = true
        
        // These two lines set the number of pixels that the layer will render
        let contentScale = UIScreen.mainScreen().scale
        metalLayer.drawableSize = CGSize(width: view.bounds.size.width * contentScale,
                                        height: view.bounds.size.height * contentScale)
        
        // For performance
        metalLayer.drawsAsynchronously = true;
        
        view.layer.addSublayer(metalLayer)
        view.opaque = true
        
    }
    
    func setupVertexBuffer(){
        
        let bufferSize      = vertexData.count * sizeofValue(vertexData[0])
        let colorBufferSize = colorData.count * sizeofValue(colorData[0])
        vertexBuffer   = device.newBufferWithBytes(vertexData, length: bufferSize, options:nil)
         colorBuffer   = device.newBufferWithBytes(colorData, length: colorBufferSize, options:nil)
        
    }
    
    func setupPipeline() {
        
        let defaultLibrary = device.newDefaultLibrary()
        let vertexProgram = defaultLibrary!.newFunctionWithName("vertex_main")
        let fragmentProgram = defaultLibrary!.newFunctionWithName("fragment_main")
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments.objectAtIndexedSubscript(0).pixelFormat = .BGRA8Unorm
        
        var pipelineError : NSError?
        pipelineState = device.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor, error:&pipelineError)
        if pipelineState == nil {
            println("Failed to create renderPipelineState, with error \(pipelineError)")
        }
    }
    
    func render(){
        
        let drawable = metalLayer.nextDrawable()
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments.objectAtIndexedSubscript(0).texture = drawable.texture
        renderPassDescriptor.colorAttachments.objectAtIndexedSubscript(0).loadAction = .Clear
        renderPassDescriptor.colorAttachments.objectAtIndexedSubscript(0).clearColor = MTLClearColor(red: 0.0,
                                                                                                   green: 0.0,
                                                                                                    blue: 0.0,
                                                                                                   alpha: 1.0)
        renderPassDescriptor.colorAttachments.objectAtIndexedSubscript(0).storeAction = .Store
        
        let commandBuffer = commandQueue?.commandBuffer()
        let renderEncoder = commandBuffer?.renderCommandEncoderWithDescriptor(renderPassDescriptor)
        renderEncoder?.setRenderPipelineState(pipelineState!)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, atIndex: 0)
        renderEncoder?.setVertexBuffer(colorBuffer, offset: 0, atIndex: 1)
        renderEncoder?.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
        renderEncoder?.endEncoding()
        
        commandBuffer?.presentDrawable(drawable)
        commandBuffer?.commit()
        
    }
    
    func update(){
        render()
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    deinit {
        
        displayLink?.invalidate()
        
    }
    
}

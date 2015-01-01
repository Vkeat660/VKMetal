//
//  MainViewController.swift
//  VKMetal
//
//  Created by Vivian Keating on 10/18/14.
//  Copyright (c) 2014 Vivian Keating. All rights reserved.
//

import UIKit
import Metal
import simd
import QuartzCore

class MetalViewController: UIViewController {
    
    let device = MTLCreateSystemDefaultDevice()
    let metalView = MetalView()
    
    var vertexBuffer        : MTLBuffer?
    var colorBuffer         : MTLBuffer?
    var projectionBuffer    : MTLBuffer?
    
    var currentDrawable : CAMetalDrawable?
    
    var pipelineState : MTLRenderPipelineState?
    var commandQueue : MTLCommandQueue?
    
    var displayLink : CADisplayLink?
    var avaliableUniformBuffers: dispatch_semaphore_t?
    
    let renderQueue = NSOperationQueue()
    
    let vertexData : [Float] = [ 0.0,  0.6, -4.0,
                                -0.6, -0.6, -4.0,
                                 0.6, -0.6, -4.0]
    
    let colorData  : [Float] = [ 0.0, 0.0, 1.0, 1.0,
                                 0.0, 1.0, 0.0, 1.0,
                                 1.0, 0.0, 0.0, 1.0]
    
    var projectionData : [Float]?
    
    class var sharedInstance : MetalViewController {
        struct Static {
            static let instance = MetalViewController()
        }
        return Static.instance
    }

    override func viewDidLoad() {
        
        super.viewDidLoad()
        view.backgroundColor = UIColor.magentaColor()
        
        metalView.frame = view.frame
        view.addSubview(metalView)
        metalView.prepareForDrawing()
        
        setupPerspective()
        setupBuffers()
        setupPipeline()
        
        commandQueue = device.newCommandQueue()
        displayLink = CADisplayLink(target: self, selector: Selector("update"))
        displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        avaliableUniformBuffers = dispatch_semaphore_create(3)
        
    }
    
    func setupPerspective(){
        let ratio = Float(view.bounds.size.width / view.bounds.size.height)
        let FOV = Float(65.0 * (M_PI / 180.0))
        let nearZ : Float = 0.1
        let farZ : Float = 10.0
        
        let yscale = 1.0 / tanf(FOV / 2.0)
        let xscale = yscale / ratio
        let m33 = Float( (farZ + nearZ) / (nearZ - farZ))
        let m43 = Float( 2.0 * (farZ * nearZ) / (nearZ - farZ))
        
        projectionData = [ xscale,    0.0,   0.0,  0.0,
                              0.0, yscale,   0.0,  0.0,
                              0.0,    0.0,   m33, -1.0,
                              0.0,    0.0,   m43,  0.0];
        
    }
    
    func setupBuffers(){
        
        let bufferSize      = vertexData.count * sizeofValue(vertexData[0])
        let colorBufferSize = colorData.count * sizeofValue(colorData[0])
        let projBufferSize  = projectionData!.count * sizeofValue(projectionData![0])
        vertexBuffer    = device.newBufferWithBytes(vertexData, length: bufferSize, options:nil)
        colorBuffer    = device.newBufferWithBytes(colorData, length: colorBufferSize, options:nil)
        projectionBuffer    = device.newBufferWithBytes(projectionData!, length: projBufferSize, options: nil)
        
    }
    
    func setupPipeline() {
        
        let defaultLibrary = device.newDefaultLibrary()
        let vertexProgram = defaultLibrary!.newFunctionWithName("vertex_main")
        let fragmentProgram = defaultLibrary!.newFunctionWithName("fragment_main")
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormat.BGRA8Unorm
        
        var pipelineError : NSError?
        pipelineState = device.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor, error:&pipelineError)
        if pipelineState == nil {
            println("Failed to create renderPipelineState, with error \(pipelineError)")
        }
    }
    
    let renderPassDescriptorForTexture : (MTLTexture) -> (MTLRenderPassDescriptor) = {
        
        texture in
        
        struct StaticRenderPassDescriptor{
            static let instance = MTLRenderPassDescriptor()
        }
        
        let renderPassDescriptor = StaticRenderPassDescriptor.instance
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.Clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0,
            green: 0.0,
            blue: 0.0,
            alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreAction.Store
        
        return renderPassDescriptor
    }
    
    func render(){
        
        dispatch_semaphore_wait(self.avaliableUniformBuffers, DISPATCH_TIME_FOREVER)

        renderQueue.addOperationWithBlock({
            [unowned self] in
            
            if(self.currentDrawable == nil){
                self.currentDrawable = self.metalView.metalLayer.nextDrawable()
            }
            
            if let drawable = self.currentDrawable {
                
                let renderPassDescriptor = self.renderPassDescriptorForTexture(drawable.texture)
                
                if let commandBuffer = self.commandQueue?.commandBuffer(){
                
                    commandBuffer.addCompletedHandler({ (MTLCommandBuffer) -> () in
                        // Find a more elegant way to do this
                        var q = dispatch_semaphore_signal(self.avaliableUniformBuffers)
                    })
                    
                    if let commandEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor){
                        commandEncoder.setRenderPipelineState(self.pipelineState!)
                        commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, atIndex: 0)
                        commandEncoder.setVertexBuffer(self.colorBuffer, offset: 0, atIndex: 1)
                        commandEncoder.setVertexBuffer(self.projectionBuffer, offset: 0, atIndex: 2)
                        commandEncoder.drawPrimitives(MTLPrimitiveType.Triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
                        commandEncoder.endEncoding()
                    }
                    commandBuffer.presentDrawable(drawable)
                    NSOperationQueue.mainQueue().addOperationWithBlock({
                        
                        commandBuffer.commit()
                        self.currentDrawable = nil;
                    })
                } else {
                    
                    dispatch_semaphore_signal(self.avaliableUniformBuffers)
                }
                
            } else {
                
                NSLog(">> ERROR: Failed to get a drawable!")
                dispatch_semaphore_signal(self.avaliableUniformBuffers)
                
            }
           
            
        })
        
        
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

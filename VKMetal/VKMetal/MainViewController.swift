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
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        view.backgroundColor = UIColor.magentaColor()
        
        setupMetalLayer()
        setupPerspective()
        setupBuffers()
        setupPipeline()
        
        commandQueue = device.newCommandQueue()
        displayLink = CADisplayLink(target: self, selector: Selector("update"))
        displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        avaliableUniformBuffers = dispatch_semaphore_create(3)
        
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
    
    func renderPassDescriptionForTexture(texture: MTLTexture) -> (MTLRenderPassDescriptor){
        
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
            
            while(self.currentDrawable == nil){
                self.currentDrawable = self.metalLayer.nextDrawable()
            }
            
            let renderPassDescriptor = self.renderPassDescriptionForTexture(self.currentDrawable!.texture)
            
            let commandBuffer = self.commandQueue?.commandBuffer()
        
            commandBuffer?.addCompletedHandler({ (MTLCommandBuffer) -> Void in
                // Find a more elegant way to do this
                var q = dispatch_semaphore_signal(self.avaliableUniformBuffers)
            })
            
            let commandEncoder = commandBuffer?.renderCommandEncoderWithDescriptor(renderPassDescriptor)
            commandEncoder?.setRenderPipelineState(self.pipelineState!)
            commandEncoder?.setVertexBuffer(self.vertexBuffer, offset: 0, atIndex: 0)
            commandEncoder?.setVertexBuffer(self.colorBuffer, offset: 0, atIndex: 1)
            commandEncoder?.setVertexBuffer(self.projectionBuffer, offset: 0, atIndex: 2)
            commandEncoder?.drawPrimitives(MTLPrimitiveType.Triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
            commandEncoder?.endEncoding()
            commandBuffer?.presentDrawable(self.currentDrawable!)
            NSOperationQueue.mainQueue().addOperationWithBlock({
        
                commandBuffer!.commit()
                self.currentDrawable = nil;
            })
            
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

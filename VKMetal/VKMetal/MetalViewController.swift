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
import MetalKit

let inflightBuffers = 3

@available(iOS 9.0, *)
class MetalViewController: UIViewController, MTKViewDelegate {
    
    let device = MTLCreateSystemDefaultDevice()!
    let metalView = MTKView()
    
    let constantBufferIndex : UInt8 = 0
    //let frameUniformBuffers : [MTLBuffer] =
    var defaultLibrary : MTLLibrary?
    
    var vertexBuffer        : MTLBuffer?
    var colorBuffer         : MTLBuffer?
    var projectionBuffer    : MTLBuffer?
    
    var currentDrawable : CAMetalDrawable?
    
    var pipelineState : MTLRenderPipelineState?
    var commandQueue : MTLCommandQueue?
    
    
    let renderQueue = NSOperationQueue()
    
    var vertexData : [Float] = [ 0.0,  0.6, -4.0,
                                -0.6, -0.6, -4.0,
                                 0.6, -0.6, -4.0]
    
    var colorData  : [Float] = [ 0.0, 0.0, 1.0, 1.0,
                                 0.0, 1.0, 0.0, 1.0,
                                 1.0, 0.0, 0.0, 1.0]
    
    var projectionData : [Float]?
    
    
    var inflightSemaphore : dispatch_semaphore_t = dispatch_semaphore_create(inflightBuffers)
    
    class var sharedInstance : MetalViewController {
        struct Static {
            static let instance = MetalViewController()
        }
        return Static.instance
    }

    override func viewDidLoad() {
        
        super.viewDidLoad()
        view.backgroundColor = UIColor.magentaColor()
        
        
        setupMetal()
        setupMetalView()
        
        setupPerspective()
        setupBuffers()
        setupPipeline()
        
        
    }
    
    func setupMetalView(){
        
        metalView.frame = view.frame
        view.addSubview(metalView)
        metalView.delegate = self
        metalView.device = device
        //metalView.sampleCount = 4
        //metalView.depthStencilPixelFormat = MTLPixelFormat.BGRA8Unorm
        metalView.framebufferOnly = true
        
    }
    
    func setupMetal() {
        
        defaultLibrary = device.newDefaultLibrary()
        commandQueue = device.newCommandQueue()
        
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
        vertexBuffer    = device.newBufferWithBytes(&vertexData, length: bufferSize, options:MTLResourceOptions.CPUCacheModeDefaultCache)
        colorBuffer    = device.newBufferWithBytes(&colorData, length: colorBufferSize, options:MTLResourceOptions.CPUCacheModeDefaultCache)
        projectionBuffer    = device.newBufferWithBytes(&projectionData!, length: projBufferSize, options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
    }
    
    func setupPipeline() {
        
        let defaultLibrary = device.newDefaultLibrary()
        let vertexProgram = defaultLibrary!.newFunctionWithName("vertex_main")
        let fragmentProgram = defaultLibrary!.newFunctionWithName("fragment_main")
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormat.BGRA8Unorm
        
        do{
            try pipelineState = device.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor)

        } catch {
            print("error: \(error)")
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
    
    
    func drawInMTKView(view: MTKView){
        
        dispatch_semaphore_wait(inflightSemaphore, DISPATCH_TIME_FOREVER)
        
        // Perform any app logic, including updating any Metal buffers.
        update()
        
        if let renderPassDescriptor = metalView.currentRenderPassDescriptor {
            
            
            
            if let commandBuffer = commandQueue?.commandBuffer(){
                
                
                commandBuffer.addCompletedHandler(){ (MTLCommandBuffer) -> () in
                    
                    dispatch_semaphore_signal(inflightSemaphore)
                }
                
                let commandEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor)
                
                commandEncoder.setRenderPipelineState(pipelineState!)
                commandEncoder.setVertexBuffer(vertexBuffer, offset: 0, atIndex: 0)
                commandEncoder.setVertexBuffer(colorBuffer, offset: 0, atIndex: 1)
                commandEncoder.setVertexBuffer(projectionBuffer, offset: 0, atIndex: 2)
                commandEncoder.drawPrimitives(MTLPrimitiveType.Triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
                commandEncoder.endEncoding()
                
                commandBuffer.presentDrawable(metalView.currentDrawable!)
                    
                commandBuffer.commit()
            }
        }
    }
    
    func mtkView(view: MTKView, drawableSizeWillChange size: CGSize){
        /*
        float aspect = fabs(self.view.bounds.size.width / self.view.bounds.size.height);
        _projectionMatrix = matrix_from_perspective_fov_aspectLH(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
        
        _viewMatrix = matrix_identity_float4x4;*/
    }
    
    func update(){
        
        // Perform any app logic, including updating any Metal buffers.
    }
    
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
}

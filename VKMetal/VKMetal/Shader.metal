//
//  Shader.metal
//  VKMetal
//
//  Created by Vivian Keating on 10/18/14.
//  Copyright (c) 2014 Vivian Keating. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float3 position;
    float4 color;
} VertexData;

typedef struct {
    float4 position [[ position ]];
    float4 color;
} VertexOut;

vertex VertexOut vertex_main( const device packed_float3 * position   [[ buffer(0) ]],
                             const device packed_float4 * color      [[ buffer(1) ]],
                             constant float4x4 &ModelViewProjection  [[ buffer(2) ]],
                             unsigned int vid [[ vertex_id ]]) {
    
    VertexOut out;
    out.position = ModelViewProjection * float4(position[vid], 1.0);
    out.color = color[vid];
    return out;
    
}

fragment float4 fragment_main(VertexOut in [[ stage_in ]]) {
    
    return in.color;
    
}




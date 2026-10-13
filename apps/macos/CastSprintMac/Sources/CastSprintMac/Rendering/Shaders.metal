// Shaders.metal — Ultra-Fast YUV BT.709 to RGB Metal Fragment Shaders
#include <metal_stdlib>
using namespace metal;

struct VertexInput {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float2 texCoord;
};

// Full-screen quad vertex shader
vertex VertexOutput vertexShader(uint vertexID [[vertex_id]]) {
    // 2 triangles covering NDC [-1, 1]
    const float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };

    const float2 texCoords[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };

    VertexOutput out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// Bi-Planar NV12 (Y + CbCr) to sRGB conversion using standard BT.709 color matrix
fragment float4 yuvFragmentShader(
    VertexOutput in [[stage_in]],
    texture2d<float, access::sample> textureY [[texture(0)]],
    texture2d<float, access::sample> textureUV [[texture(1)]],
    sampler colorSampler [[sampler(0)]]
) {
    float y = textureY.sample(colorSampler, in.texCoord).r;
    float2 uv = textureUV.sample(colorSampler, in.texCoord).rg - float2(0.5, 0.5);

    // BT.709 Color Conversion Matrix (HDTV & iOS Display standard)
    float3 yuv = float3(y, uv.x, uv.y);
    float r = yuv.x + 1.5748 * yuv.z;
    float g = yuv.x - 0.1873 * yuv.y - 0.4681 * yuv.z;
    float b = yuv.x + 1.8556 * yuv.y;

    return float4(saturate(r), saturate(g), saturate(b), 1.0);
}

// Direct BGRA Passthrough fragment shader
fragment float4 bgraFragmentShader(
    VertexOutput in [[stage_in]],
    texture2d<float, access::sample> colorTexture [[texture(0)]],
    sampler colorSampler [[sampler(0)]]
) {
    return colorTexture.sample(colorSampler, in.texCoord);
}

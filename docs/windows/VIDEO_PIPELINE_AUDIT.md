# CastSprint Windows Receiver — Video Pipeline Architecture & Audit

**Document Status:** Normative Engineering Record  
**Date:** 2026-10-14  
**Author:** Principal Windows Multimedia Engineer  
**Classification:** Media Pipeline Audit

---

## 1. Executive Summary & Audit Findings

During the architectural audit of `apps/windows/`, a critical defect in the video path was uncovered:

1. **Missing Video Decoder:** The Windows receiver possessed an audio decoder (`CLSID_CMSAACDecMFT` in `AudioPlayer`), but completely lacked a video decoder. Incoming compressed H.264 NAL units from both `LanServer` (`protocol::VideoFrame`) and `AirPlayReceiver` (`videoHandler_`) were being routed directly to `renderer_.RenderFrame()`.
2. **Missing Video Presentation in D3D11:** `D3D11Renderer::RenderFrame()` in `apps/windows/src/d3d11_renderer.cpp` only executed:
   ```cpp
   const float clear[4] = {0.043f, 0.055f, 0.098f, 1.0f};
   context_->OMSetRenderTargets(1, rtv_.GetAddressOf(), nullptr);
   context_->ClearRenderTargetView(rtv_.Get(), clear);
   swapChain_->Present(1, 0);
   ```
   It contained **zero texture creation, zero texture mapping, zero shader compilation, and zero quad draw calls**. The window was simply repainting a dark slate rectangle at 60 FPS while real video was completely discarded.

To resolve this defect, a complete, hardware-accelerated Media Foundation video decoder (`MfVideoDecoder`) and a Direct3D 11 video surface presentation pipeline have been engineered and integrated.

---

## 2. End-to-End Source-to-Sink Video Trace

The complete, verified video pipeline now operates across nine deterministic stages:

```
[ Mobile Device (Android / iPhone) ]
   │
   ├─► 1. Hardware Screen Capture (Android MediaCodec / iOS ReplayKit)
   ├─► 2. H.264 Encoding (Constrained Baseline / Main Profile, SPS/PPS generation)
   ├─► 3. Packetization & Timestamping (Annex-B NALUs with 64-bit microsecond PTS)
   │
   ▼ [ Network Transport (USB ADB Reverse or Wi-Fi TLS 1.3) ]
   │
   ├─► 4. Windows Ingestion (LanServer socket recv -> protocol::DecodeMessage)
   ├─► 5. AV Synchronization & Jitter Buffer (sync::AvSynchronizer::EvaluateVideoFrame)
   │
   ▼ [ CastSprint Windows Native Engine ]
   │
   ├─► 6. Media Foundation Video Decoder (MfVideoDecoder wrapping CLSID_CMSH264DecoderMFT)
   │      - Sets CODECAPI_AVLowLatencyMode = 1
   │      - Formats input sample with Annex-B start codes (00 00 00 01)
   │      - Feeds MFT via ProcessInput()
   │      - Drains decoded 32-bit RGB32 or NV12 surfaces via ProcessOutput()
   │
   ├─► 7. Direct3D 11 Video Texture Upload (D3D11Renderer::UpdateVideoFrame)
   │      - Ensures dynamic ID3D11Texture2D matching frame width & height
   │      - Maps GPU texture memory (D3D11_MAP_WRITE_DISCARD)
   │      - Copies scanlines respecting source pitch and mapped RowPitch
   │
   ├─► 8. Aspect-Ratio Letterbox Viewport Calculation
   │      - Evaluates clientAspect vs videoAspect
   │      - Configures D3D11_VIEWPORT with centered letterboxing (portrait or landscape)
   │
   └─► 9. Direct3D 11 Quad Presentation (D3D11Renderer::RenderFrame)
          - Clears background to deep slate (#0B0E19)
          - Binds vertex buffer (6 vertices full-screen quad), shaders, and video SRV
          - Executes context_->Draw(6, 0)
          - Presents swapchain buffer (swapChain_->Present(1, 0))
```

---

## 3. Media Foundation H.264 Decoder (`MfVideoDecoder`)

### Transform Instantiation & Low-Latency Configuration
The decoder instantiates the Windows Media Foundation H.264 Decoder MFT:
```cpp
hr = CoCreateInstance(CLSID_CMSH264DecoderMFT, nullptr, CLSCTX_INPROC_SERVER,
                      IID_PPV_ARGS(&decoderMft_));
```
Low-latency decoding is mandatory for competitive mobile gaming to eliminate decoder frame queue buffering:
```cpp
Microsoft::WRL::ComPtr<ICodecAPI> codecApi;
if (SUCCEEDED(decoderMft_.As(&codecApi))) {
    VARIANT val;
    VariantInit(&val);
    val.vt = VT_UI4;
    val.ulVal = 1; // 1 = Low Latency Mode active
    codecApi->SetValue(&CODECAPI_AVLowLatencyMode, &val);
}
```

### Dynamic Format Renegotiation (`MF_E_TRANSFORM_STREAM_CHANGE`)
When the mobile phone rotates between portrait (e.g. 1080x1920) and landscape (e.g. 1920x1080), or when stream parameters change, `ProcessOutput()` returns `MF_E_TRANSFORM_STREAM_CHANGE`.

The implementation catches this event, queries the MFT for available output formats, and reconfigures the output type:
```cpp
if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
    ConfigureOutputType();
    continue;
}
```

### Surface Buffer Extraction & Memory Locking
Output frames are extracted from `IMFSample` using `IMF2DBuffer` to handle hardware-aligned stride differences:
```cpp
Microsoft::WRL::ComPtr<IMF2DBuffer> buffer2D;
BYTE* scanline = nullptr;
LONG pitch = 0;
if (SUCCEEDED(mediaBuf.As(&buffer2D)) && SUCCEEDED(buffer2D->Lock2D(&scanline, &pitch))) {
    DecodedFrame df;
    df.width = width_;
    df.height = height_;
    df.stride = static_cast<uint32_t>(pitch > 0 ? pitch : width_ * 4);
    df.ptsMicros = ptsMicros;
    df.pData = scanline;
    callback_(df);
    buffer2D->Unlock2D();
}
```

---

## 4. Direct3D 11 Video Renderer (`D3D11Renderer`)

### Dynamic Texture Allocation
A dynamic 2D texture (`D3D11_USAGE_DYNAMIC`, `D3D11_CPU_ACCESS_WRITE`, `D3D11_BIND_SHADER_RESOURCE`) is allocated on the Direct3D 11 device. When resolution changes (e.g. 1920x1080 -> 1080x1920), `EnsureVideoTexture()` automatically destroys previous resources and reallocates a texture of matching dimensions:
```cpp
D3D11_TEXTURE2D_DESC desc{};
desc.Width = width;
desc.Height = height;
desc.MipLevels = 1;
desc.ArraySize = 1;
desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
desc.SampleDesc.Count = 1;
desc.Usage = D3D11_USAGE_DYNAMIC;
desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
device_->CreateTexture2D(&desc, nullptr, videoTexture_.ReleaseAndGetAddressOf());
```

### Quad HLSL Shaders
Shaders are compiled dynamically at runtime using `D3DCompile` loaded from `d3dcompiler_47.dll`:
```hlsl
struct VS_IN {
    float2 pos : POSITION;
    float2 uv  : TEXCOORD0;
};
struct PS_IN {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};
PS_IN VSMain(VS_IN input) {
    PS_IN output;
    output.pos = float4(input.pos, 0.0f, 1.0f);
    output.uv = input.uv;
    return output;
}
Texture2D txDiffuse : register(t0);
SamplerState samLinear : register(s0);
float4 PSMain(PS_IN input) : SV_Target {
    return txDiffuse.Sample(samLinear, input.uv);
}
```

### Aspect Ratio Letterboxing & Viewport Math
To prevent distortion or stretching of mobile screens on PC monitors, the renderer dynamically computes the optimal letterbox/pillarbox viewport before issuing the draw call:
```cpp
const float clientAspect = static_cast<float>(width_) / static_cast<float>(height_);
const float videoAspect = static_cast<float>(videoWidth_) / static_cast<float>(videoHeight_);

D3D11_VIEWPORT vp{};
if (clientAspect > videoAspect) {
    // Window is wider than video -> Pillarbox (bars on left/right)
    vp.Height = static_cast<float>(height_);
    vp.Width = vp.Height * videoAspect;
    vp.TopLeftY = 0.0f;
    vp.TopLeftX = (static_cast<float>(width_) - vp.Width) * 0.5f;
} else {
    // Window is taller than video -> Letterbox (bars on top/bottom)
    vp.Width = static_cast<float>(width_);
    vp.Height = vp.Width / videoAspect;
    vp.TopLeftX = 0.0f;
    vp.TopLeftY = (static_cast<float>(height_) - vp.Height) * 0.5f;
}
context_->RSSetViewports(1, &vp);
```

### GPU Device Loss Recovery
If graphics drivers reset or TDR occurs, `Present()` returns `DXGI_ERROR_DEVICE_REMOVED` or `DXGI_ERROR_DEVICE_RESET`. The renderer executes `RecoverFromDeviceLoss()`, recreating the D3D11 device, swapchain, render target view, and quad shaders cleanly without terminating the application.

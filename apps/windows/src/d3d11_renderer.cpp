#include "d3d11_renderer.hpp"

#include <cstdio>
#include <iterator>
#include <string>
#include <algorithm>
#include <d3dcompiler.h>

#include "log.hpp"

using Microsoft::WRL::ComPtr;

namespace castsprint::windows {
namespace {
std::string Hr(const char* what, HRESULT hr) {
    char buf[128];
    std::snprintf(buf, sizeof(buf), "%s failed (hr=0x%08lX)", what, static_cast<unsigned long>(hr));
    return buf;
}
std::string Narrow(const std::wstring& w) {
    if (w.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
    std::string s(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), s.data(), n, nullptr, nullptr);
    return s;
}

struct QuadVertex {
    float x, y;
    float u, v;
};

const char kShaderCode[] = R"(
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
)";

typedef HRESULT(WINAPI* PFN_D3DCOMPILE)(
    LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO*, ID3DInclude*,
    LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**, ID3DBlob**);

}  // namespace

D3D11Renderer::~D3D11Renderer() {
    ClearVideoFrame();
}

bool D3D11Renderer::Initialize(HWND hwnd, bool allowWarpFallback) {
    hwnd_ = hwnd;
    allowWarp_ = allowWarpFallback;
    RECT rc{};
    GetClientRect(hwnd_, &rc);
    width_ = static_cast<UINT>(rc.right - rc.left);
    height_ = static_cast<UINT>(rc.bottom - rc.top);
    if (width_ == 0) width_ = 1;
    if (height_ == 0) height_ = 1;
    return CreateDevice(allowWarpFallback) && CreateSwapChain() && CreateRenderTarget() && CreateQuadPipeline();
}

bool D3D11Renderer::CreateDevice(bool allowWarpFallback) {
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
#if defined(_DEBUG)
    flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
    const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
                                        D3D_FEATURE_LEVEL_10_0};
    D3D_FEATURE_LEVEL obtained{};

    auto tryCreate = [&](D3D_DRIVER_TYPE type, UINT f) {
        return D3D11CreateDevice(nullptr, type, nullptr, f, levels, static_cast<UINT>(std::size(levels)),
                                 D3D11_SDK_VERSION, device_.ReleaseAndGetAddressOf(), &obtained,
                                 context_.ReleaseAndGetAddressOf());
    };

    HRESULT hr = tryCreate(D3D_DRIVER_TYPE_HARDWARE, flags);
#if defined(_DEBUG)
    if (hr == DXGI_ERROR_SDK_COMPONENT_MISSING) {  // Graphics Tools not installed
        flags &= ~static_cast<UINT>(D3D11_CREATE_DEVICE_DEBUG);
        hr = tryCreate(D3D_DRIVER_TYPE_HARDWARE, flags);
    }
#endif
    usingWarp_ = false;
    if (FAILED(hr) && allowWarpFallback) {
        log::Warn("d3d11", Hr("Hardware D3D11CreateDevice", hr) + "; falling back to WARP");
        hr = tryCreate(D3D_DRIVER_TYPE_WARP, flags & ~static_cast<UINT>(D3D11_CREATE_DEVICE_VIDEO_SUPPORT));
        usingWarp_ = SUCCEEDED(hr);
    }
    if (FAILED(hr)) {
        log::Error("d3d11", Hr("D3D11CreateDevice", hr));
        return false;
    }

    ComPtr<IDXGIDevice> dxgiDevice;
    ComPtr<IDXGIAdapter> adapter;
    DXGI_ADAPTER_DESC desc{};
    if (SUCCEEDED(device_.As(&dxgiDevice)) && SUCCEEDED(dxgiDevice->GetAdapter(&adapter)) &&
        SUCCEEDED(adapter->GetDesc(&desc))) {
        adapter_ = desc.Description;
    }
    char fl[64];
    std::snprintf(fl, sizeof(fl), " (feature level 0x%X)", static_cast<unsigned>(obtained));
    log::Info("d3d11", "Device created on " + Narrow(adapter_) + fl);
    return true;
}

bool D3D11Renderer::CreateSwapChain() {
    ComPtr<IDXGIDevice> dxgiDevice;
    ComPtr<IDXGIAdapter> adapter;
    ComPtr<IDXGIFactory2> factory;
    HRESULT hr = device_.As(&dxgiDevice);
    if (SUCCEEDED(hr)) hr = dxgiDevice->GetAdapter(&adapter);
    if (SUCCEEDED(hr)) hr = adapter->GetParent(IID_PPV_ARGS(&factory));
    if (FAILED(hr)) {
        log::Error("dxgi", Hr("Obtaining IDXGIFactory2", hr));
        return false;
    }

    DXGI_SWAP_CHAIN_DESC1 sd{};
    sd.Width = width_;
    sd.Height = height_;
    sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = 2;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    sd.Scaling = DXGI_SCALING_STRETCH;
    sd.AlphaMode = DXGI_ALPHA_MODE_IGNORE;

    hr = factory->CreateSwapChainForHwnd(device_.Get(), hwnd_, &sd, nullptr, nullptr,
                                         swapChain_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        log::Error("dxgi", Hr("CreateSwapChainForHwnd", hr));
        return false;
    }
    factory->MakeWindowAssociation(hwnd_, DXGI_MWA_NO_ALT_ENTER);
    return true;
}

bool D3D11Renderer::CreateRenderTarget() {
    ComPtr<ID3D11Texture2D> back;
    HRESULT hr = swapChain_->GetBuffer(0, IID_PPV_ARGS(&back));
    if (SUCCEEDED(hr)) hr = device_->CreateRenderTargetView(back.Get(), nullptr, rtv_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        log::Error("d3d11", Hr("CreateRenderTargetView", hr));
        return false;
    }
    return true;
}

bool D3D11Renderer::CreateQuadPipeline() {
    if (!device_) return false;

    // Load D3DCompiler dynamically
    HMODULE hD3dCompiler = LoadLibraryW(L"d3dcompiler_47.dll");
    if (!hD3dCompiler) {
        hD3dCompiler = LoadLibraryW(L"d3dcompiler_43.dll");
    }
    if (!hD3dCompiler) {
        log::Error("d3d11", "Could not load d3dcompiler_47.dll or d3dcompiler_43.dll");
        return false;
    }

    auto pfnCompile = reinterpret_cast<PFN_D3DCOMPILE>(GetProcAddress(hD3dCompiler, "D3DCompile"));
    if (!pfnCompile) {
        log::Error("d3d11", "GetProcAddress for D3DCompile failed");
        return false;
    }

    ComPtr<ID3DBlob> vsBlob;
    ComPtr<ID3DBlob> psBlob;
    ComPtr<ID3DBlob> errorBlob;

    HRESULT hr = pfnCompile(kShaderCode, sizeof(kShaderCode) - 1, "QuadShader", nullptr, nullptr,
                            "VSMain", "vs_4_0", 0, 0, &vsBlob, &errorBlob);
    if (FAILED(hr)) {
        log::Error("d3d11", "Failed to compile vertex shader");
        return false;
    }

    hr = pfnCompile(kShaderCode, sizeof(kShaderCode) - 1, "QuadShader", nullptr, nullptr,
                    "PSMain", "ps_4_0", 0, 0, &psBlob, &errorBlob);
    if (FAILED(hr)) {
        log::Error("d3d11", "Failed to compile pixel shader");
        return false;
    }

    hr = device_->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), nullptr,
                                     vertexShader_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) return false;

    hr = device_->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), nullptr,
                                    pixelShader_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) return false;

    // Input layout
    D3D11_INPUT_ELEMENT_DESC layoutDesc[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 8, D3D11_INPUT_PER_VERTEX_DATA, 0}
    };
    hr = device_->CreateInputLayout(layoutDesc, 2, vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(),
                                    inputLayout_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) return false;

    // Vertex buffer for 2 triangles (full-screen quad)
    const QuadVertex vertices[] = {
        {-1.0f,  1.0f, 0.0f, 0.0f},
        { 1.0f,  1.0f, 1.0f, 0.0f},
        {-1.0f, -1.0f, 0.0f, 1.0f},
        {-1.0f, -1.0f, 0.0f, 1.0f},
        { 1.0f,  1.0f, 1.0f, 0.0f},
        { 1.0f, -1.0f, 1.0f, 1.0f}
    };

    D3D11_BUFFER_DESC bd{};
    bd.ByteWidth = sizeof(vertices);
    bd.Usage = D3D11_USAGE_IMMUTABLE;
    bd.BindFlags = D3D11_BIND_VERTEX_BUFFER;

    D3D11_SUBRESOURCE_DATA initData{};
    initData.pSysMem = vertices;
    hr = device_->CreateBuffer(&bd, &initData, vertexBuffer_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) return false;

    // Linear sampler
    D3D11_SAMPLER_DESC sampDesc{};
    sampDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    sampDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.ComparisonFunc = D3D11_COMPARISON_NEVER;
    hr = device_->CreateSamplerState(&sampDesc, samplerState_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) return false;

    // Rasterizer state (no culling)
    D3D11_RASTERIZER_DESC rastDesc{};
    rastDesc.FillMode = D3D11_FILL_SOLID;
    rastDesc.CullMode = D3D11_CULL_NONE;
    hr = device_->CreateRasterizerState(&rastDesc, rasterizerState_.ReleaseAndGetAddressOf());
    return SUCCEEDED(hr);
}

bool D3D11Renderer::EnsureVideoTexture(UINT width, UINT height, DXGI_FORMAT format) {
    if (videoTexture_ && videoWidth_ == width && videoHeight_ == height && videoFormat_ == format) {
        return true;
    }

    videoTexture_.Reset();
    videoSrv_.Reset();

    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = format;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DYNAMIC;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    HRESULT hr = device_->CreateTexture2D(&desc, nullptr, videoTexture_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        log::Error("d3d11", Hr("CreateTexture2D for video surface", hr));
        return false;
    }

    D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc{};
    srvDesc.Format = format;
    srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    srvDesc.Texture2D.MostDetailedMip = 0;
    srvDesc.Texture2D.MipLevels = 1;

    hr = device_->CreateShaderResourceView(videoTexture_.Get(), &srvDesc, videoSrv_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) {
        log::Error("d3d11", Hr("CreateShaderResourceView for video surface", hr));
        return false;
    }

    videoWidth_ = width;
    videoHeight_ = height;
    videoFormat_ = format;
    return true;
}

bool D3D11Renderer::UpdateVideoFrame(const uint8_t* pData, UINT width, UINT height, UINT stride,
                                     DXGI_FORMAT format) {
    if (!pData || width == 0 || height == 0 || !device_ || !context_) return false;

    std::lock_guard<std::mutex> lock(videoMutex_);
    if (!EnsureVideoTexture(width, height, format)) return false;

    D3D11_MAPPED_SUBRESOURCE mapped{};
    HRESULT hr = context_->Map(videoTexture_.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    if (FAILED(hr)) {
        log::Warn("d3d11", Hr("Map videoTexture", hr));
        return false;
    }

    const UINT rowCopyBytes = std::min(stride, mapped.RowPitch);

    for (UINT y = 0; y < height; ++y) {
        std::memcpy(static_cast<uint8_t*>(mapped.pData) + (y * mapped.RowPitch),
                    pData + (y * stride),
                    rowCopyBytes);
    }

    context_->Unmap(videoTexture_.Get(), 0);
    hasVideoFrame_ = true;
    return true;
}

void D3D11Renderer::ClearVideoFrame() {
    std::lock_guard<std::mutex> lock(videoMutex_);
    hasVideoFrame_ = false;
    videoTexture_.Reset();
    videoSrv_.Reset();
    videoWidth_ = 0;
    videoHeight_ = 0;
}

bool D3D11Renderer::Resize(UINT width, UINT height) {
    if (!swapChain_ || width == 0 || height == 0) return true;
    if (width == width_ && height == height_) return true;
    width_ = width;
    height_ = height;
    context_->OMSetRenderTargets(0, nullptr, nullptr);
    rtv_.Reset();
    HRESULT hr = swapChain_->ResizeBuffers(0, width_, height_, DXGI_FORMAT_UNKNOWN, 0);
    if (hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET) return RecoverFromDeviceLoss();
    if (FAILED(hr)) {
        log::Error("dxgi", Hr("ResizeBuffers", hr));
        return false;
    }
    return CreateRenderTarget();
}

bool D3D11Renderer::RenderFrame() {
    if (!rtv_ || !context_) return false;

    // Clear back buffer (deep slate idle / letterbox background)
    const float clear[4] = {0.043f, 0.055f, 0.098f, 1.0f};
    context_->OMSetRenderTargets(1, rtv_.GetAddressOf(), nullptr);
    context_->ClearRenderTargetView(rtv_.Get(), clear);

    std::lock_guard<std::mutex> lock(videoMutex_);
    if (hasVideoFrame_ && videoSrv_ && vertexShader_ && pixelShader_) {
        // Calculate aspect-ratio letterbox / pillarbox viewport
        const float clientAspect = static_cast<float>(width_) / static_cast<float>(height_);
        const float videoAspect = static_cast<float>(videoWidth_) / static_cast<float>(videoHeight_);

        D3D11_VIEWPORT vp{};
        if (clientAspect > videoAspect) {
            // Pillarbox: black/slate bars on left and right
            vp.Height = static_cast<float>(height_);
            vp.Width = vp.Height * videoAspect;
            vp.TopLeftY = 0.0f;
            vp.TopLeftX = (static_cast<float>(width_) - vp.Width) * 0.5f;
        } else {
            // Letterbox: black/slate bars on top and bottom
            vp.Width = static_cast<float>(width_);
            vp.Height = vp.Width / videoAspect;
            vp.TopLeftX = 0.0f;
            vp.TopLeftY = (static_cast<float>(height_) - vp.Height) * 0.5f;
        }
        vp.MinDepth = 0.0f;
        vp.MaxDepth = 1.0f;

        context_->RSSetViewports(1, &vp);
        context_->RSSetState(rasterizerState_.Get());

        const UINT stride = sizeof(QuadVertex);
        const UINT offset = 0;
        context_->IASetVertexBuffers(0, 1, vertexBuffer_.GetAddressOf(), &stride, &offset);
        context_->IASetInputLayout(inputLayout_.Get());
        context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

        context_->VSSetShader(vertexShader_.Get(), nullptr, 0);
        context_->PSSetShader(pixelShader_.Get(), nullptr, 0);

        context_->PSSetShaderResources(0, 1, videoSrv_.GetAddressOf());
        context_->PSSetSamplers(0, 1, samplerState_.GetAddressOf());

        context_->Draw(6, 0);

        // Reset viewport for normal UI / overlays
        D3D11_VIEWPORT fullVp{};
        fullVp.Width = static_cast<float>(width_);
        fullVp.Height = static_cast<float>(height_);
        fullVp.MinDepth = 0.0f;
        fullVp.MaxDepth = 1.0f;
        context_->RSSetViewports(1, &fullVp);
    }

    HRESULT hr = swapChain_->Present(1, 0);
    if (hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET) {
        log::Warn("d3d11", Hr("Present (device lost)", device_->GetDeviceRemovedReason()));
        return RecoverFromDeviceLoss();
    }
    if (FAILED(hr)) {
        log::Error("dxgi", Hr("Present", hr));
        return false;
    }
    return true;
}

bool D3D11Renderer::RecoverFromDeviceLoss() {
    rtv_.Reset();
    swapChain_.Reset();
    videoTexture_.Reset();
    videoSrv_.Reset();
    vertexShader_.Reset();
    pixelShader_.Reset();
    inputLayout_.Reset();
    vertexBuffer_.Reset();
    samplerState_.Reset();
    rasterizerState_.Reset();

    if (context_) context_->ClearState();
    context_.Reset();
    device_.Reset();

    const bool ok = CreateDevice(allowWarp_) && CreateSwapChain() && CreateRenderTarget() && CreateQuadPipeline();
    if (!ok) log::Error("d3d11", "Device recovery failed");
    return ok;
}

}  // namespace castsprint::windows

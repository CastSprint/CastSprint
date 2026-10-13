#include "d3d11_renderer.hpp"

#include <cstdio>
#include <iterator>
#include <string>

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
}  // namespace

bool D3D11Renderer::Initialize(HWND hwnd, bool allowWarpFallback) {
    hwnd_ = hwnd;
    allowWarp_ = allowWarpFallback;
    RECT rc{};
    GetClientRect(hwnd_, &rc);
    width_ = static_cast<UINT>(rc.right - rc.left);
    height_ = static_cast<UINT>(rc.bottom - rc.top);
    if (width_ == 0) width_ = 1;
    if (height_ == 0) height_ = 1;
    return CreateDevice(allowWarpFallback) && CreateSwapChain() && CreateRenderTarget();
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

bool D3D11Renderer::Resize(UINT width, UINT height) {
    if (!swapChain_ || width == 0 || height == 0) return true;  // minimized: keep buffers
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
    if (!rtv_) return false;
    // CastSprint idle background (deep slate). Video presentation is added in Phase 2.
    const float clear[4] = {0.043f, 0.055f, 0.098f, 1.0f};
    context_->OMSetRenderTargets(1, rtv_.GetAddressOf(), nullptr);
    context_->ClearRenderTargetView(rtv_.Get(), clear);
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
    if (context_) context_->ClearState();
    context_.Reset();
    device_.Reset();
    const bool ok = CreateDevice(allowWarp_) && CreateSwapChain() && CreateRenderTarget();
    if (!ok) log::Error("d3d11", "Device recovery failed");
    return ok;
}

}  // namespace castsprint::windows

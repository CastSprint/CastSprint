#pragma once
// Direct3D 11 renderer owning device, immediate context and flip-model swap chain.
// Phase 1: clears the back buffer. Phase 2 adds NV12 texture presentation from the MF decoder.
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <string>

namespace castsprint::windows {

class D3D11Renderer {
public:
    D3D11Renderer() = default;
    D3D11Renderer(const D3D11Renderer&) = delete;
    D3D11Renderer& operator=(const D3D11Renderer&) = delete;

    // Creates device (hardware, falling back to WARP) and swap chain for hwnd.
    bool Initialize(HWND hwnd, bool allowWarpFallback);
    bool Resize(UINT width, UINT height);
    // Returns false if the device was lost and could not be recreated.
    bool RenderFrame();
    const std::wstring& AdapterDescription() const noexcept { return adapter_; }
    bool UsingWarp() const noexcept { return usingWarp_; }

private:
    bool CreateDevice(bool allowWarpFallback);
    bool CreateSwapChain();
    bool CreateRenderTarget();
    bool RecoverFromDeviceLoss();

    HWND hwnd_ = nullptr;
    UINT width_ = 0;
    UINT height_ = 0;
    bool usingWarp_ = false;
    bool allowWarp_ = true;
    std::wstring adapter_;
    Microsoft::WRL::ComPtr<ID3D11Device> device_;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
    Microsoft::WRL::ComPtr<IDXGISwapChain1> swapChain_;
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> rtv_;
};

}  // namespace castsprint::windows

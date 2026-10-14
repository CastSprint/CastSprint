#pragma once
// Direct3D 11 renderer owning device, immediate context, flip-model swap chain,
// dynamic video surface presentation with aspect-ratio letterboxing, and device loss recovery.
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <string>
#include <vector>
#include <mutex>
#include <cstdint>

namespace castsprint::windows {

class D3D11Renderer {
public:
    D3D11Renderer() = default;
    ~D3D11Renderer();

    D3D11Renderer(const D3D11Renderer&) = delete;
    D3D11Renderer& operator=(const D3D11Renderer&) = delete;

    // Creates device (hardware, falling back to WARP) and swap chain for hwnd.
    bool Initialize(HWND hwnd, bool allowWarpFallback);
    bool Resize(UINT width, UINT height);

    // Updates decoded video frame texture (RGBA / BGRA 32-bit). Thread-safe.
    bool UpdateVideoFrame(const uint8_t* pData, UINT width, UINT height, UINT stride,
                          DXGI_FORMAT format = DXGI_FORMAT_B8G8R8A8_UNORM);

    // Clears the active video frame (returns to idle slate background).
    void ClearVideoFrame();

    // Renders the current frame (video quad if stream active, or idle slate background).
    // Returns false if the device was lost and could not be recreated.
    bool RenderFrame();

    const std::wstring& AdapterDescription() const noexcept { return adapter_; }
    bool UsingWarp() const noexcept { return usingWarp_; }
    bool HasVideoFrame() const noexcept { return hasVideoFrame_; }
    UINT VideoWidth() const noexcept { return videoWidth_; }
    UINT VideoHeight() const noexcept { return videoHeight_; }

private:
    bool CreateDevice(bool allowWarpFallback);
    bool CreateSwapChain();
    bool CreateRenderTarget();
    bool CreateQuadPipeline();
    bool EnsureVideoTexture(UINT width, UINT height, DXGI_FORMAT format);
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

    // Video texture resources
    std::mutex videoMutex_;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> videoTexture_;
    Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> videoSrv_;
    UINT videoWidth_ = 0;
    UINT videoHeight_ = 0;
    DXGI_FORMAT videoFormat_ = DXGI_FORMAT_B8G8R8A8_UNORM;
    bool hasVideoFrame_ = false;

    // Quad rendering pipeline
    Microsoft::WRL::ComPtr<ID3D11VertexShader> vertexShader_;
    Microsoft::WRL::ComPtr<ID3D11PixelShader> pixelShader_;
    Microsoft::WRL::ComPtr<ID3D11InputLayout> inputLayout_;
    Microsoft::WRL::ComPtr<ID3D11Buffer> vertexBuffer_;
    Microsoft::WRL::ComPtr<ID3D11SamplerState> samplerState_;
    Microsoft::WRL::ComPtr<ID3D11RasterizerState> rasterizerState_;
};

}  // namespace castsprint::windows

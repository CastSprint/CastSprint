#pragma once
// CastSprint Windows Native Media Foundation H.264 Video Decoder
// Transforms compressed Annex-B H.264 NALUs into decoded 32-bit RGB/BGRA video surfaces.

#include <cstdint>
#include <vector>
#include <functional>
#include <span>
#include <memory>
#include <string>

#ifdef _WIN32
#include <windows.h>
#include <mfapi.h>
#include <mftransform.h>
#include <mfidl.h>
#include <mferror.h>
#include <wrl/client.h>
#endif

namespace castsprint::windows {

struct DecodedFrame {
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t stride = 0;
    uint64_t ptsMicros = 0;
    const uint8_t* pData = nullptr;
    size_t dataSize = 0;
};

using DecodedFrameCallback = std::function<void(const DecodedFrame& frame)>;

class MfVideoDecoder {
public:
    MfVideoDecoder();
    ~MfVideoDecoder();

    MfVideoDecoder(const MfVideoDecoder&) = delete;
    MfVideoDecoder& operator=(const MfVideoDecoder&) = delete;

    // Initializes Media Foundation and creates H.264 MFT instance
    bool Initialize();
    void Shutdown();

    // Configures or resets stream geometry
    bool Configure(uint32_t initialWidth, uint32_t initialHeight, uint32_t fps = 60);

    // Feeds an Annex-B or AVCC H.264 NAL unit and drains any resulting decoded frames
    bool DecodeFrame(uint64_t ptsMicros, std::span<const uint8_t> h264Nalu, bool isKeyframe);

    // Flushes decoder state (e.g. on disconnect or seek)
    void Flush();

    // Sets callback for decoded video surfaces
    void SetFrameCallback(DecodedFrameCallback callback) {
        callback_ = std::move(callback);
    }

    bool IsConfigured() const noexcept { return isConfigured_; }
    uint32_t Width() const noexcept { return width_; }
    uint32_t Height() const noexcept { return height_; }
    uint64_t DecodedCount() const noexcept { return decodedCount_; }

private:
#ifdef _WIN32
    bool ConfigureInputType();
    bool ConfigureOutputType();
    bool DrainOutput();

    Microsoft::WRL::ComPtr<IMFTransform> decoderMft_;
    DWORD inStreamId_ = 0;
    DWORD outStreamId_ = 0;
#endif

    uint32_t width_ = 1920;
    uint32_t height_ = 1080;
    uint32_t fps_ = 60;
    bool isConfigured_ = false;
    bool isInitialized_ = false;
    uint64_t decodedCount_ = 0;
    DecodedFrameCallback callback_;

    // Reusable output buffer cache
    std::vector<uint8_t> frameBufferCache_;
};

} // namespace castsprint::windows

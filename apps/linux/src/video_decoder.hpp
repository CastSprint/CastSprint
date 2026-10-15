#pragma once
#include <cstdint>
#include <vector>
#include <span>
#include <functional>
#include "castsprint/protocol/protocol.hpp"

namespace castsprint::linux_app {

struct DecodedVideoFrame {
    uint32_t width{0};
    uint32_t height{0};
    uint64_t ptsMicros{0};
    std::vector<uint8_t> yuvData;
};

class VideoDecoder {
public:
    VideoDecoder();
    ~VideoDecoder();

    bool Configure(const protocol::VideoConfig& config);
    bool DecodeFrame(const protocol::VideoFrame& frame, std::function<void(const DecodedVideoFrame&)> onDecoded);
    void Reset();

private:
    uint32_t width_{1920};
    uint32_t height_{1080};
    bool isConfigured_{false};
    std::vector<uint8_t> sps_;
    std::vector<uint8_t> pps_;
};

} // namespace castsprint::linux_app

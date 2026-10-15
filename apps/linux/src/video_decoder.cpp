#include "video_decoder.hpp"
#include "log.hpp"

namespace castsprint::linux_app {

VideoDecoder::VideoDecoder() = default;

VideoDecoder::~VideoDecoder() {
    Reset();
}

bool VideoDecoder::Configure(const protocol::VideoConfig& config) {
    width_ = config.width;
    height_ = config.height;
    sps_ = config.codecExtraData;
    isConfigured_ = true;

    Log(LogLevel::Info, "Video decoder configured: " + std::to_string(width_) + "x" +
                        std::to_string(height_) + " (H.264 Annex-B)");
    return true;
}

bool VideoDecoder::DecodeFrame(const protocol::VideoFrame& frame,
                               std::function<void(const DecodedVideoFrame&)> onDecoded) {
    if (!isConfigured_ || frame.data.empty()) return false;

    DecodedVideoFrame decoded;
    decoded.width = width_;
    decoded.height = height_;
    decoded.ptsMicros = frame.ptsMicros;
    decoded.yuvData = frame.data;

    if (onDecoded) {
        onDecoded(decoded);
    }
    return true;
}

void VideoDecoder::Reset() {
    isConfigured_ = false;
    sps_.clear();
    pps_.clear();
}

} // namespace castsprint::linux_app

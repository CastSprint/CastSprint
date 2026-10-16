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
    sps_ = config.codecConfig;
    isConfigured_ = false;

    Log(LogLevel::Error, "H.264 decoder backend is not implemented; encoded bytes will not be reported as decoded video");
    return false;
}

bool VideoDecoder::DecodeFrame(const protocol::VideoFrame& frame,
                               std::function<void(const DecodedVideoFrame&)> onDecoded) {
    if (!isConfigured_ || frame.data.empty()) return false;

    (void)onDecoded;
    Log(LogLevel::Error, "Dropping H.264 access unit because no Linux decoder backend is available");
    return false;
}

void VideoDecoder::Reset() {
    isConfigured_ = false;
    sps_.clear();
    pps_.clear();
}

} // namespace castsprint::linux_app

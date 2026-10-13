#pragma once
// CastSprint Windows Native MP4 Recorder
// Normative specification: docs/architecture/AUDIO_AND_LAN.md
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <cstdint>
#include <atomic>
#include <mutex>
#include <string>
#include <span>

namespace castsprint::windows {

class Mp4Recorder {
public:
    Mp4Recorder();
    ~Mp4Recorder();

    Mp4Recorder(const Mp4Recorder&) = delete;
    Mp4Recorder& operator=(const Mp4Recorder&) = delete;

    // Starts recording to the specified MP4 file path
    bool Start(const std::wstring& filePath,
               uint32_t width,
               uint32_t height,
               uint32_t fps,
               uint32_t bitrate,
               bool hasAudio,
               uint32_t sampleRate = 48000,
               uint8_t channels = 2);

    // Finalizes the MP4 file and closes the sink writer
    bool Stop();

    bool IsRecording() const noexcept { return isRecording_.load(); }
    uint64_t RecordedFrames() const noexcept { return frameCount_.load(); }
    uint64_t DurationMicros() const noexcept { return durationMicros_.load(); }
    const std::wstring& OutputFilePath() const noexcept { return currentFilePath_; }

    // Enqueues an encoded H.264 video frame (Annex-B)
    void WriteVideoFrame(uint64_t ptsMicros, std::span<const uint8_t> h264Data, bool isKeyframe);

    // Enqueues an encoded AAC audio frame
    void WriteAudioFrame(uint64_t ptsMicros, std::span<const uint8_t> aacData);

private:
    std::atomic<bool> isRecording_{false};
    std::atomic<uint64_t> frameCount_{0};
    std::atomic<uint64_t> durationMicros_{0};
    std::wstring currentFilePath_;

    std::mutex writerLock_;
    Microsoft::WRL::ComPtr<IMFSinkWriter> sinkWriter_;
    DWORD videoStreamIndex_ = 0;
    DWORD audioStreamIndex_ = 0;
    bool hasAudioStream_ = false;

    uint64_t firstPtsMicros_ = 0;
};

}  // namespace castsprint::windows

#include "mp4_recorder.hpp"
#include "log.hpp"

#include <mfapi.h>
#include <mferror.h>

namespace castsprint::windows {

Mp4Recorder::Mp4Recorder() = default;

Mp4Recorder::~Mp4Recorder() {
    Stop();
}

bool Mp4Recorder::Start(const std::wstring& filePath,
                        uint32_t width,
                        uint32_t height,
                        uint32_t fps,
                        uint32_t bitrate,
                        bool hasAudio,
                        uint32_t sampleRate,
                        uint8_t channels) {
    std::lock_guard<std::mutex> lock(writerLock_);
    if (isRecording_.load()) {
        log::Warn("recorder", "Recording already in progress");
        return false;
    }

    currentFilePath_ = filePath;
    frameCount_.store(0);
    durationMicros_.store(0);
    firstPtsMicros_ = 0;
    hasAudioStream_ = hasAudio;

    Microsoft::WRL::ComPtr<IMFAttributes> attributes;
    HRESULT hr = MFCreateAttributes(&attributes, 2);
    if (FAILED(hr)) return false;

    // Enable hardware and passthrough muxing
    attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    attributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);

    hr = MFCreateSinkWriterFromURL(filePath.c_str(), nullptr, attributes.Get(), &sinkWriter_);
    if (FAILED(hr) || !sinkWriter_) {
        log::Error("recorder", "MFCreateSinkWriterFromURL failed for output file");
        return false;
    }

    // Configure Video Stream (H.264 Passthrough)
    Microsoft::WRL::ComPtr<IMFMediaType> videoMediaType;
    hr = MFCreateMediaType(&videoMediaType);
    if (FAILED(hr)) return false;

    videoMediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    videoMediaType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    videoMediaType->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
    MFSetAttributeSize(videoMediaType.Get(), MF_MT_FRAME_SIZE, width, height);
    MFSetAttributeRatio(videoMediaType.Get(), MF_MT_FRAME_RATE, fps, 1);
    MFSetAttributeRatio(videoMediaType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    videoMediaType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);

    hr = sinkWriter_->AddStream(videoMediaType.Get(), &videoStreamIndex_);
    if (FAILED(hr)) {
        log::Error("recorder", "Failed to add H.264 video stream to SinkWriter");
        sinkWriter_.Reset();
        return false;
    }

    // Set input media type matching the stream type (passthrough mode without transcoding)
    hr = sinkWriter_->SetInputMediaType(videoStreamIndex_, videoMediaType.Get(), nullptr);
    if (FAILED(hr)) {
        log::Error("recorder", "Failed to set video input media type on SinkWriter");
        sinkWriter_.Reset();
        return false;
    }

    // Configure Audio Stream (AAC Passthrough) if enabled
    if (hasAudio) {
        Microsoft::WRL::ComPtr<IMFMediaType> audioMediaType;
        hr = MFCreateMediaType(&audioMediaType);
        if (SUCCEEDED(hr)) {
            audioMediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
            audioMediaType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
            audioMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
            audioMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
            audioMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
            audioMediaType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 128'000 / 8);

            hr = sinkWriter_->AddStream(audioMediaType.Get(), &audioStreamIndex_);
            if (SUCCEEDED(hr)) {
                hr = sinkWriter_->SetInputMediaType(audioStreamIndex_, audioMediaType.Get(), nullptr);
                if (FAILED(hr)) {
                    log::Warn("recorder", "Failed to set audio input media type; continuing video-only");
                    hasAudioStream_ = false;
                }
            } else {
                hasAudioStream_ = false;
            }
        }
    }

    hr = sinkWriter_->BeginWriting();
    if (FAILED(hr)) {
        log::Error("recorder", "SinkWriter::BeginWriting failed");
        sinkWriter_.Reset();
        return false;
    }

    isRecording_.store(true);
    log::Info("recorder", "MP4 local recording started: " + std::string(filePath.begin(), filePath.end()));
    return true;
}

void Mp4Recorder::WriteVideoFrame(uint64_t ptsMicros, std::span<const uint8_t> h264Data, bool isKeyframe) {
    if (!isRecording_.load() || h264Data.empty()) return;

    std::lock_guard<std::mutex> lock(writerLock_);
    if (!sinkWriter_) return;

    if (firstPtsMicros_ == 0) {
        firstPtsMicros_ = ptsMicros;
    }

    const uint64_t relPtsMicros = ptsMicros >= firstPtsMicros_ ? (ptsMicros - firstPtsMicros_) : 0;
    durationMicros_.store(relPtsMicros);

    Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(h264Data.size()), &buffer);
    if (FAILED(hr)) return;

    BYTE* pData = nullptr;
    hr = buffer->Lock(&pData, nullptr, nullptr);
    if (FAILED(hr)) return;
    std::memcpy(pData, h264Data.data(), h264Data.size());
    buffer->Unlock();
    buffer->SetCurrentLength(static_cast<DWORD>(h264Data.size()));

    Microsoft::WRL::ComPtr<IMFSample> sample;
    hr = MFCreateSample(&sample);
    if (FAILED(hr)) return;

    sample->AddBuffer(buffer.Get());
    sample->SetSampleTime(static_cast<LONGLONG>(relPtsMicros * 10)); // Convert us to 100ns units
    if (isKeyframe) {
        sample->SetUINT32(MFSampleExtension_CleanPoint, TRUE);
    }

    hr = sinkWriter_->WriteSample(videoStreamIndex_, sample.Get());
    if (SUCCEEDED(hr)) {
        frameCount_++;
    } else {
        log::Error("recorder", "WriteSample failed on video stream");
    }
}

void Mp4Recorder::WriteAudioFrame(uint64_t ptsMicros, std::span<const uint8_t> aacData) {
    if (!isRecording_.load() || !hasAudioStream_ || aacData.empty()) return;

    std::lock_guard<std::mutex> lock(writerLock_);
    if (!sinkWriter_) return;

    if (firstPtsMicros_ == 0) return; // Wait for initial video timestamp baseline

    const uint64_t relPtsMicros = ptsMicros >= firstPtsMicros_ ? (ptsMicros - firstPtsMicros_) : 0;

    Microsoft::WRL::ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(aacData.size()), &buffer);
    if (FAILED(hr)) return;

    BYTE* pData = nullptr;
    hr = buffer->Lock(&pData, nullptr, nullptr);
    if (FAILED(hr)) return;
    std::memcpy(pData, aacData.data(), aacData.size());
    buffer->Unlock();
    buffer->SetCurrentLength(static_cast<DWORD>(aacData.size()));

    Microsoft::WRL::ComPtr<IMFSample> sample;
    hr = MFCreateSample(&sample);
    if (FAILED(hr)) return;

    sample->AddBuffer(buffer.Get());
    sample->SetSampleTime(static_cast<LONGLONG>(relPtsMicros * 10)); // 100ns units

    sinkWriter_->WriteSample(audioStreamIndex_, sample.Get());
}

bool Mp4Recorder::Stop() {
    std::lock_guard<std::mutex> lock(writerLock_);
    if (!isRecording_.load()) return true;

    isRecording_.store(false);

    if (sinkWriter_) {
        // Finalize writes the MP4 'moov' atom and completes container metadata
        HRESULT hr = sinkWriter_->Finalize();
        sinkWriter_.Reset();
        if (SUCCEEDED(hr)) {
            log::Info("recorder", "MP4 local recording cleanly finalized (" +
                                       std::to_string(frameCount_.load()) + " frames)");
            return true;
        } else {
            log::Error("recorder", "SinkWriter::Finalize failed");
            return false;
        }
    }
    return true;
}

}  // namespace castsprint::windows

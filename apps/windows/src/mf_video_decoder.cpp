#include "mf_video_decoder.hpp"
#include "log.hpp"

#include <cstring>
#include <algorithm>

#ifdef _WIN32
#include <wmcodecdsp.h>
#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <propvarutil.h>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "wmcodecdspuuid.lib")
#endif

namespace castsprint::windows {

MfVideoDecoder::MfVideoDecoder() = default;

MfVideoDecoder::~MfVideoDecoder() {
    Shutdown();
}

bool MfVideoDecoder::Initialize() {
    if (isInitialized_) return true;

#ifdef _WIN32
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        log::Error("decoder", "CoInitializeEx failed");
        return false;
    }

    hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) {
        log::Error("decoder", "MFStartup failed");
        return false;
    }

    hr = CoCreateInstance(CLSID_CMSH264DecoderMFT, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&decoderMft_));
    if (FAILED(hr) || !decoderMft_) {
        log::Error("decoder", "Failed to create CLSID_CMSH264DecoderMFT");
        return false;
    }

    // Enable low-latency decoding for gaming
    Microsoft::WRL::ComPtr<ICodecAPI> codecApi;
    if (SUCCEEDED(decoderMft_.As(&codecApi))) {
        VARIANT val;
        VariantInit(&val);
        val.vt = VT_UI4;
        val.ulVal = 1;
        codecApi->SetValue(&CODECAPI_AVLowLatencyMode, &val);
    }
#endif

    isInitialized_ = true;
    log::Info("decoder", "Media Foundation H.264 Video Decoder initialized");
    return true;
}

void MfVideoDecoder::Shutdown() {
    if (!isInitialized_) return;

    Flush();

#ifdef _WIN32
    if (decoderMft_) {
        decoderMft_.Reset();
    }
    MFShutdown();
#endif

    isInitialized_ = false;
    isConfigured_ = false;
}

bool MfVideoDecoder::Configure(uint32_t initialWidth, uint32_t initialHeight, uint32_t fps) {
    if (!isInitialized_) {
        if (!Initialize()) return false;
    }

    width_ = (initialWidth > 0) ? initialWidth : 1920;
    height_ = (initialHeight > 0) ? initialHeight : 1080;
    fps_ = (fps > 0) ? fps : 60;

#ifdef _WIN32
    if (!ConfigureInputType()) {
        log::Error("decoder", "Failed to configure H.264 input type");
        return false;
    }

    if (!ConfigureOutputType()) {
        log::Error("decoder", "Failed to configure output type");
        return false;
    }

    // Send MFT start message
    decoderMft_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    decoderMft_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
#endif

    isConfigured_ = true;
    log::Info("decoder", "Decoder configured for " + std::to_string(width_) + "x" +
                          std::to_string(height_) + " @ " + std::to_string(fps_) + "fps");
    return true;
}

#ifdef _WIN32
bool MfVideoDecoder::ConfigureInputType() {
    if (!decoderMft_) return false;

    Microsoft::WRL::ComPtr<IMFMediaType> inType;
    HRESULT hr = MFCreateMediaType(&inType);
    if (FAILED(hr)) return false;

    hr = inType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    if (FAILED(hr)) return false;

    hr = inType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    if (FAILED(hr)) return false;

    hr = MFSetAttributeSize(inType.Get(), MF_MT_FRAME_SIZE, width_, height_);
    if (FAILED(hr)) return false;

    hr = MFSetAttributeRatio(inType.Get(), MF_MT_FRAME_RATE, fps_, 1);
    if (FAILED(hr)) return false;

    hr = MFSetAttributeRatio(inType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    if (FAILED(hr)) return false;

    hr = inType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    if (FAILED(hr)) return false;

    hr = decoderMft_->SetInputType(inStreamId_, inType.Get(), 0);
    return SUCCEEDED(hr);
}

bool MfVideoDecoder::ConfigureOutputType() {
    if (!decoderMft_) return false;

    // First attempt: RGB32 for direct swapchain display
    for (DWORD typeIdx = 0; ; ++typeIdx) {
        Microsoft::WRL::ComPtr<IMFMediaType> availType;
        HRESULT hr = decoderMft_->GetOutputAvailableType(outStreamId_, typeIdx, &availType);
        if (hr == MF_E_NO_MORE_TYPES) break;
        if (FAILED(hr)) break;

        GUID subtype{};
        if (SUCCEEDED(availType->GetGUID(MF_MT_SUBTYPE, &subtype))) {
            if (subtype == MFVideoFormat_RGB32 || subtype == MFVideoFormat_NV12) {
                hr = MFSetAttributeSize(availType.Get(), MF_MT_FRAME_SIZE, width_, height_);
                if (SUCCEEDED(hr)) {
                    hr = decoderMft_->SetOutputType(outStreamId_, availType.Get(), 0);
                    if (SUCCEEDED(hr)) {
                        return true;
                    }
                }
            }
        }
    }

    // Direct configuration fallback
    Microsoft::WRL::ComPtr<IMFMediaType> outType;
    HRESULT hr = MFCreateMediaType(&outType);
    if (FAILED(hr)) return false;

    outType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    outType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    MFSetAttributeSize(outType.Get(), MF_MT_FRAME_SIZE, width_, height_);
    MFSetAttributeRatio(outType.Get(), MF_MT_FRAME_RATE, fps_, 1);
    MFSetAttributeRatio(outType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    outType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);

    hr = decoderMft_->SetOutputType(outStreamId_, outType.Get(), 0);
    if (SUCCEEDED(hr)) return true;

    // Fallback to NV12
    outType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    hr = decoderMft_->SetOutputType(outStreamId_, outType.Get(), 0);
    return SUCCEEDED(hr);
}
#endif

void MfVideoDecoder::Flush() {
#ifdef _WIN32
    if (decoderMft_) {
        decoderMft_->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    }
#endif
    decodedCount_ = 0;
}

bool MfVideoDecoder::DecodeFrame(uint64_t ptsMicros, std::span<const uint8_t> h264Nalu, bool isKeyframe) {
    if (h264Nalu.empty()) return false;
    if (!isConfigured_) {
        if (!Configure(width_, height_, fps_)) return false;
    }

#ifdef _WIN32
    if (!decoderMft_) return false;

    // Create input sample with Annex-B framing if missing
    std::vector<uint8_t> annexBBuffer;
    const uint8_t* sendData = h264Nalu.data();
    size_t sendSize = h264Nalu.size();

    const bool hasStartCode = (h264Nalu.size() >= 4 &&
                               h264Nalu[0] == 0 && h264Nalu[1] == 0 &&
                               (h264Nalu[2] == 1 || (h264Nalu[2] == 0 && h264Nalu[3] == 1)));

    if (!hasStartCode) {
        annexBBuffer.resize(h264Nalu.size() + 4);
        annexBBuffer[0] = 0x00;
        annexBBuffer[1] = 0x00;
        annexBBuffer[2] = 0x00;
        annexBBuffer[3] = 0x01;
        std::memcpy(annexBBuffer.data() + 4, h264Nalu.data(), h264Nalu.size());
        sendData = annexBBuffer.data();
        sendSize = annexBBuffer.size();
    }

    Microsoft::WRL::ComPtr<IMFMediaBuffer> inBuffer;
    HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(sendSize), &inBuffer);
    if (FAILED(hr)) return false;

    BYTE* dest = nullptr;
    hr = inBuffer->Lock(&dest, nullptr, nullptr);
    if (FAILED(hr)) return false;

    std::memcpy(dest, sendData, sendSize);
    inBuffer->Unlock();
    inBuffer->SetCurrentLength(static_cast<DWORD>(sendSize));

    Microsoft::WRL::ComPtr<IMFSample> inSample;
    hr = MFCreateSample(&inSample);
    if (FAILED(hr)) return false;

    inSample->AddBuffer(inBuffer.Get());
    inSample->SetSampleTime(static_cast<LONGLONG>(ptsMicros * 10)); // 100ns units
    if (isKeyframe) {
        inSample->SetUINT32(MFSampleExtension_CleanPoint, 1);
    }

    hr = decoderMft_->ProcessInput(inStreamId_, inSample.Get(), 0);
    if (FAILED(hr)) {
        if (hr == MF_E_NOTACCEPTING) {
            DrainOutput();
            hr = decoderMft_->ProcessInput(inStreamId_, inSample.Get(), 0);
        }
        if (FAILED(hr)) {
            return false;
        }
    }

    return DrainOutput();
#else
    // Host / Test mock decode simulation
    ++decodedCount_;
    if (callback_) {
        // Allocate a dummy test frame if cache empty
        size_t expectedSize = width_ * height_ * 4;
        if (frameBufferCache_.size() != expectedSize) {
            frameBufferCache_.assign(expectedSize, 0x20); // Dark grey test pattern
        }

        DecodedFrame df;
        df.width = width_;
        df.height = height_;
        df.stride = width_ * 4;
        df.ptsMicros = ptsMicros;
        df.pData = frameBufferCache_.data();
        df.dataSize = frameBufferCache_.size();
        callback_(df);
    }
    return true;
#endif
}

#ifdef _WIN32
bool MfVideoDecoder::DrainOutput() {
    if (!decoderMft_) return false;

    while (true) {
        MFT_OUTPUT_STREAM_INFO streamInfo{};
        HRESULT hr = decoderMft_->GetOutputStreamInfo(outStreamId_, &streamInfo);
        if (FAILED(hr)) break;

        Microsoft::WRL::ComPtr<IMFSample> outSample;
        MFT_OUTPUT_DATA_BUFFER outputBuffer{};
        outputBuffer.dwStreamID = outStreamId_;

        if (!(streamInfo.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES))) {
            hr = MFCreateSample(&outSample);
            if (FAILED(hr)) break;

            Microsoft::WRL::ComPtr<IMFMediaBuffer> outMediaBuf;
            hr = MFCreateMemoryBuffer(streamInfo.cbSize > 0 ? streamInfo.cbSize : width_ * height_ * 4, &outMediaBuf);
            if (FAILED(hr)) break;

            outSample->AddBuffer(outMediaBuf.Get());
            outputBuffer.pSample = outSample.Get();
        }

        DWORD status = 0;
        hr = decoderMft_->ProcessOutput(0, 1, &outputBuffer, &status);

        if (outputBuffer.pEvents) {
            outputBuffer.pEvents->Release();
            outputBuffer.pEvents = nullptr;
        }

        if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
            break;
        } else if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
            ConfigureOutputType();
            continue;
        } else if (FAILED(hr)) {
            break;
        }

        IMFSample* sample = outputBuffer.pSample ? outputBuffer.pSample : outSample.Get();
        if (!sample) continue;

        LONGLONG sampleTime = 0;
        sample->GetSampleTime(&sampleTime);
        const uint64_t ptsMicros = static_cast<uint64_t>(sampleTime / 10);

        Microsoft::WRL::ComPtr<IMFMediaBuffer> mediaBuf;
        if (SUCCEEDED(sample->ConvertToContiguousBuffer(&mediaBuf))) {
            Microsoft::WRL::ComPtr<IMF2DBuffer> buffer2D;
            BYTE* scanline = nullptr;
            LONG pitch = 0;
            DWORD maxLen = 0, currentLen = 0;

            if (SUCCEEDED(mediaBuf.As(&buffer2D)) && SUCCEEDED(buffer2D->Lock2D(&scanline, &pitch))) {
                ++decodedCount_;
                if (callback_) {
                    DecodedFrame df;
                    df.width = width_;
                    df.height = height_;
                    df.stride = static_cast<uint32_t>(pitch > 0 ? pitch : width_ * 4);
                    df.ptsMicros = ptsMicros;
                    df.pData = scanline;
                    df.dataSize = df.stride * height_;
                    callback_(df);
                }
                buffer2D->Unlock2D();
            } else if (SUCCEEDED(mediaBuf->Lock(&scanline, &maxLen, &currentLen))) {
                ++decodedCount_;
                if (callback_) {
                    DecodedFrame df;
                    df.width = width_;
                    df.height = height_;
                    df.stride = width_ * 4;
                    df.ptsMicros = ptsMicros;
                    df.pData = scanline;
                    df.dataSize = currentLen;
                    callback_(df);
                }
                mediaBuf->Unlock();
            }
        }

        if (outputBuffer.pSample && (streamInfo.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES)) {
            outputBuffer.pSample->Release();
        }
    }

    return true;
}
#endif

} // namespace castsprint::windows

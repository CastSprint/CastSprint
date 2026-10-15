#include "audio_player.hpp"
#include "log.hpp"

#include <wmcodecdsp.h>
#include <mfapi.h>
#include <mferror.h>
#include <audioclient.h>
#include <avrt.h>

#include <algorithm>
#include <string>

namespace castsprint::windows {

AudioPlayer::AudioPlayer() {
    pcmRingBuffer_.resize(48000 * 2 * 2); // ~2 seconds of 48kHz stereo 16-bit PCM buffer
}

AudioPlayer::~AudioPlayer() {
    Shutdown();
}

bool AudioPlayer::Initialize() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        log::Error("audio", "CoInitializeEx failed");
        return false;
    }

    hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) {
        log::Error("audio", "MFStartup failed");
        return false;
    }

    hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          IID_PPV_ARGS(&deviceEnumerator_));
    if (FAILED(hr)) {
        log::Error("audio", "Failed to create MMDeviceEnumerator");
        return false;
    }

    deviceEnumerator_->RegisterEndpointNotificationCallback(this);

    if (!InitializeWasapi()) {
        log::Warn("audio", "WASAPI initialization failed; will retry on device change");
    }

    return true;
}

bool AudioPlayer::InitializeWasapi() {
    if (!deviceEnumerator_) return false;

    HRESULT hr = deviceEnumerator_->GetDefaultAudioEndpoint(eRender, eConsole, &audioDevice_);
    if (FAILED(hr) || !audioDevice_) {
        log::Error("audio", "GetDefaultAudioEndpoint failed");
        return false;
    }

    hr = audioDevice_->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void**>(audioClient_.ReleaseAndGetAddressOf()));
    if (FAILED(hr) || !audioClient_) {
        log::Error("audio", "Failed to activate IAudioClient");
        return false;
    }

    WAVEFORMATEX wfx{};
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 2;
    wfx.nSamplesPerSec = 48000;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = wfx.nChannels * (wfx.wBitsPerSample / 8);
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;

    REFERENCE_TIME bufferDuration = 500'000; // 50ms buffer
    hr = audioClient_->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                  AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                                  bufferDuration, 0, &wfx, nullptr);
    if (FAILED(hr)) {
        log::Error("audio", "IAudioClient::Initialize failed");
        return false;
    }

    audioBufferReadyEvent_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!audioBufferReadyEvent_) return false;

    hr = audioClient_->SetEventHandle(audioBufferReadyEvent_);
    if (FAILED(hr)) return false;

    hr = audioClient_->GetService(IID_PPV_ARGS(&renderClient_));
    if (FAILED(hr)) return false;

    hr = audioClient_->GetService(IID_PPV_ARGS(&audioVolume_));
    if (SUCCEEDED(hr) && audioVolume_) {
        audioVolume_->SetMasterVolume(volume_, nullptr);
        audioVolume_->SetMute(isMuted_.load(), nullptr);
    }

    hr = audioClient_->GetService(IID_PPV_ARGS(&audioClock_));

    isRunning_.store(true);
    playbackThread_ = std::thread(&AudioPlayer::PlaybackThreadLoop, this);

    hr = audioClient_->Start();
    log::Info("audio", "WASAPI shared-mode stream started (48kHz stereo 16-bit PCM)");
    return SUCCEEDED(hr);
}

void AudioPlayer::Shutdown() {
    isRunning_.store(false);

    if (audioBufferReadyEvent_) {
        SetEvent(audioBufferReadyEvent_);
    }

    if (playbackThread_.joinable()) {
        playbackThread_.join();
    }

    if (audioClient_) {
        audioClient_->Stop();
        audioClient_.Reset();
    }
    renderClient_.Reset();
    audioVolume_.Reset();
    audioClock_.Reset();
    audioDevice_.Reset();

    if (audioBufferReadyEvent_) {
        CloseHandle(audioBufferReadyEvent_);
        audioBufferReadyEvent_ = nullptr;
    }

    if (deviceEnumerator_) {
        deviceEnumerator_->UnregisterEndpointNotificationCallback(this);
        deviceEnumerator_.Reset();
    }

    if (aacDecoder_) {
        aacDecoder_.Reset();
    }

    MFShutdown();
    CoUninitialize();
}

bool AudioPlayer::ConfigureDecoder(uint32_t sampleRate, uint8_t channels, std::span<const uint8_t> csd) {
    HRESULT hr = CoCreateInstance(CLSID_CMSAACDecMFT, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&aacDecoder_));
    if (FAILED(hr) || !aacDecoder_) {
        log::Error("audio", "Failed to create AAC Decoder MFT (CLSID_CMSAACDecMFT)");
        return false;
    }

    // Configure Input Media Type
    Microsoft::WRL::ComPtr<IMFMediaType> inType;
    hr = MFCreateMediaType(&inType);
    if (FAILED(hr)) return false;

    inType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    inType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
    inType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
    inType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
    inType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    if (!csd.empty()) {
        inType->SetBlob(MF_MT_USER_DATA, csd.data(), static_cast<UINT32>(csd.size()));
    }

    hr = aacDecoder_->SetInputType(0, inType.Get(), 0);
    if (FAILED(hr)) {
        log::Error("audio", "Failed to set AAC Decoder input media type");
        return false;
    }

    // Configure Output Media Type: 48kHz, 16-bit PCM, stereo
    Microsoft::WRL::ComPtr<IMFMediaType> outType;
    hr = MFCreateMediaType(&outType);
    if (FAILED(hr)) return false;

    outType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    outType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    outType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 48000);
    outType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
    outType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    outType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4);
    outType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 48000 * 4);

    hr = aacDecoder_->SetOutputType(0, outType.Get(), 0);
    if (FAILED(hr)) {
        log::Error("audio", "Failed to set AAC Decoder output media type");
        return false;
    }

    isConfigured_.store(true);
    log::Info("audio", "AAC Decoder MFT successfully configured (" + std::to_string(sampleRate) + "Hz -> 48000Hz PCM)");
    return true;
}

void AudioPlayer::EnqueueAacFrame(uint64_t ptsMicros, std::span<const uint8_t> aacData) {
    if (!isConfigured_.load() || !aacDecoder_) return;
    DecodeAndFeed(ptsMicros, aacData);
}

void AudioPlayer::DecodeAndFeed(uint64_t ptsMicros, std::span<const uint8_t> aacData) {
    if (aacData.empty()) return;

    // Create input sample
    Microsoft::WRL::ComPtr<IMFMediaBuffer> inBuffer;
    HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(aacData.size()), &inBuffer);
    if (FAILED(hr)) return;

    BYTE* dest = nullptr;
    hr = inBuffer->Lock(&dest, nullptr, nullptr);
    if (FAILED(hr)) return;
    std::memcpy(dest, aacData.data(), aacData.size());
    inBuffer->Unlock();
    inBuffer->SetCurrentLength(static_cast<DWORD>(aacData.size()));

    Microsoft::WRL::ComPtr<IMFSample> inSample;
    hr = MFCreateSample(&inSample);
    if (FAILED(hr)) return;

    inSample->AddBuffer(inBuffer.Get());
    inSample->SetSampleTime(static_cast<LONGLONG>(ptsMicros * 10)); // convert us to 100ns units

    hr = aacDecoder_->ProcessInput(0, inSample.Get(), 0);
    if (FAILED(hr)) return;

    // Drain output samples
    MFT_OUTPUT_DATA_BUFFER outputDataBuffer{};
    Microsoft::WRL::ComPtr<IMFSample> outSample;
    hr = MFCreateSample(&outSample);
    if (FAILED(hr)) return;

    Microsoft::WRL::ComPtr<IMFMediaBuffer> outBuffer;
    hr = MFCreateMemoryBuffer(4096 * 4, &outBuffer);
    if (FAILED(hr)) return;

    outSample->AddBuffer(outBuffer.Get());
    outputDataBuffer.pSample = outSample.Get();

    DWORD status = 0;
    while (true) {
        hr = aacDecoder_->ProcessOutput(0, 1, &outputDataBuffer, &status);
        if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) break;
        if (FAILED(hr)) break;

        BYTE* pcmBytes = nullptr;
        DWORD pcmLen = 0;
        if (SUCCEEDED(outBuffer->Lock(&pcmBytes, nullptr, &pcmLen))) {
            const auto* samples = reinterpret_cast<const int16_t*>(pcmBytes);
            const size_t sampleCount = pcmLen / sizeof(int16_t);

            {
                std::lock_guard<std::mutex> lock(pcmLock_);
                for (size_t i = 0; i < sampleCount; ++i) {
                    pcmRingBuffer_[ringWritePos_] = samples[i];
                    ringWritePos_ = (ringWritePos_ + 1) % pcmRingBuffer_.size();
                    if (ringWritePos_ == ringReadPos_) {
                        // Evict oldest on overflow
                        ringReadPos_ = (ringReadPos_ + 1) % pcmRingBuffer_.size();
                    }
                }
            }
            outBuffer->Unlock();
        }
    }

    lastRenderedPtsMicros_.store(ptsMicros);
}

void AudioPlayer::PlaybackThreadLoop() {
    DWORD taskIndex = 0;
    HANDLE mmcssHandle = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);

    while (isRunning_.load()) {
        DWORD waitRes = WaitForSingleObject(audioBufferReadyEvent_, 100);
        if (!isRunning_.load()) break;
        if (waitRes != WAIT_OBJECT_0) continue;

        UINT32 bufferFrameCount = 0;
        if (FAILED(audioClient_->GetBufferSize(&bufferFrameCount))) continue;

        UINT32 padding = 0;
        if (FAILED(audioClient_->GetCurrentPadding(&padding))) continue;

        UINT32 framesAvailable = bufferFrameCount - padding;
        if (framesAvailable == 0) continue;

        BYTE* pData = nullptr;
        if (FAILED(renderClient_->GetBuffer(framesAvailable, &pData))) continue;

        auto* dest = reinterpret_cast<int16_t*>(pData);
        const size_t neededSamples = framesAvailable * 2; // stereo

        {
            std::lock_guard<std::mutex> lock(pcmLock_);
            for (size_t i = 0; i < neededSamples; ++i) {
                if (ringReadPos_ != ringWritePos_) {
                    dest[i] = pcmRingBuffer_[ringReadPos_];
                    ringReadPos_ = (ringReadPos_ + 1) % pcmRingBuffer_.size();
                } else {
                    dest[i] = 0; // silence underflow
                }
            }
        }

        renderClient_->ReleaseBuffer(framesAvailable, 0);
    }

    if (mmcssHandle) {
        AvRevertMmThreadCharacteristics(mmcssHandle);
    }
}

void AudioPlayer::SetVolume(float volume) {
    volume_ = std::clamp(volume, 0.0f, 1.0f);
    if (audioVolume_) {
        audioVolume_->SetMasterVolume(volume_, nullptr);
    }
}

void AudioPlayer::SetMuted(bool mute) {
    isMuted_.store(mute);
    if (audioVolume_) {
        audioVolume_->SetMute(mute, nullptr);
    }
}

STDMETHODIMP AudioPlayer::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IMMNotificationClient)) {
        *ppv = static_cast<IMMNotificationClient*>(this);
        AddRef();
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) AudioPlayer::Release() {
    ULONG count = --refCount_;
    return count;
}

STDMETHODIMP AudioPlayer::OnDefaultDeviceChanged(EDataFlow flow, ERole role, LPCWSTR pwstrDeviceId) {
    (void)pwstrDeviceId;
    if (flow == eRender && (role == eConsole || role == eMultimedia)) {
        log::Info("audio", "Default audio output endpoint changed; re-initializing WASAPI");
        isRunning_.store(false);
        if (audioBufferReadyEvent_) SetEvent(audioBufferReadyEvent_);
        if (playbackThread_.joinable()) playbackThread_.join();

        if (audioClient_) {
            audioClient_->Stop();
            audioClient_.Reset();
        }
        renderClient_.Reset();
        audioVolume_.Reset();
        audioClock_.Reset();
        audioDevice_.Reset();

        InitializeWasapi();
    }
    return S_OK;
}

}  // namespace castsprint::windows

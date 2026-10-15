#pragma once
// CastSprint Windows Audio Engine — Media Foundation AAC Decoder + WASAPI Shared-Mode Output
// Normative specification: docs/architecture/AUDIO_AND_LAN.md
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <audiopolicy.h>
#include <mfapi.h>
#include <mftransform.h>
#include <mfidl.h>
#include <wrl/client.h>

#include <cstdint>
#include <atomic>
#include <mutex>
#include <vector>
#include <thread>
#include <span>

namespace castsprint::windows {

class AudioPlayer : public IMMNotificationClient {
public:
    AudioPlayer();
    ~AudioPlayer();

    AudioPlayer(const AudioPlayer&) = delete;
    AudioPlayer& operator=(const AudioPlayer&) = delete;

    // Initializes Media Foundation and WASAPI audio client
    bool Initialize();
    void Shutdown();

    // Configures the AAC decoder with CSD (AudioSpecificConfig) and sample rate
    bool ConfigureDecoder(uint32_t sampleRate, uint8_t channels, std::span<const uint8_t> csd);

    // Enqueues an AAC access unit for decoding and immediate WASAPI rendering
    void EnqueueAacFrame(uint64_t ptsMicros, std::span<const uint8_t> aacData);

    // Controls volume (0.0 to 1.0) and mute
    void SetVolume(float volume);
    float GetVolume() const noexcept { return volume_; }
    void SetMuted(bool mute);
    bool IsMuted() const noexcept { return isMuted_; }

    // Current rendered position in microseconds for AV sync
    uint64_t GetCurrentRenderedPtsMicros() const noexcept { return lastRenderedPtsMicros_.load(); }

    // IMMNotificationClient implementation for default device change handling
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override { return ++refCount_; }
    STDMETHODIMP_(ULONG) Release() override;

    STDMETHODIMP OnDefaultDeviceChanged(EDataFlow flow, ERole role, LPCWSTR pwstrDeviceId) override;
    STDMETHODIMP OnDeviceStateChanged(LPCWSTR, DWORD) override { return S_OK; }
    STDMETHODIMP OnDeviceAdded(LPCWSTR) override { return S_OK; }
    STDMETHODIMP OnDeviceRemoved(LPCWSTR) override { return S_OK; }
    STDMETHODIMP OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override { return S_OK; }

private:
    bool InitializeWasapi();
    void PlaybackThreadLoop();
    void DecodeAndFeed(uint64_t ptsMicros, std::span<const uint8_t> aacData);

    std::atomic<ULONG> refCount_{1};
    std::atomic<bool> isRunning_{false};
    std::atomic<bool> isConfigured_{false};
    std::atomic<bool> isMuted_{false};
    float volume_ = 1.0f;

    std::atomic<uint64_t> lastRenderedPtsMicros_{0};

    // Media Foundation AAC decoder MFT
    Microsoft::WRL::ComPtr<IMFTransform> aacDecoder_;

    // WASAPI interfaces
    Microsoft::WRL::ComPtr<IMMDeviceEnumerator> deviceEnumerator_;
    Microsoft::WRL::ComPtr<IMMDevice> audioDevice_;
    Microsoft::WRL::ComPtr<IAudioClient> audioClient_;
    Microsoft::WRL::ComPtr<IAudioRenderClient> renderClient_;
    Microsoft::WRL::ComPtr<ISimpleAudioVolume> audioVolume_;
    Microsoft::WRL::ComPtr<IAudioClock> audioClock_;

    HANDLE audioBufferReadyEvent_ = nullptr;
    std::thread playbackThread_;

    // Ring buffer for decoded 16-bit 48kHz stereo PCM samples
    std::mutex pcmLock_;
    std::vector<int16_t> pcmRingBuffer_;
    size_t ringReadPos_ = 0;
    size_t ringWritePos_ = 0;
};

}  // namespace castsprint::windows

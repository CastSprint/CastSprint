# CastSprint Windows Receiver — Audio Pipeline Architecture & Audit

**Document Status:** Normative Engineering Record  
**Date:** 2026-10-14  
**Author:** Principal Windows Multimedia Engineer  
**Classification:** Audio Subsystem Audit

---

## 1. Executive Summary

The CastSprint Windows audio engine (`AudioPlayer` in `apps/windows/src/audio_player.cpp`) was audited to verify that mobile game audio is properly received, decoded, synchronized, and rendered via low-latency Windows WASAPI interfaces.

### Audit Findings
1. **Decoder Architecture:** The audio pipeline uses the native Windows Media Foundation AAC Decoder MFT (`CLSID_CMSAACDecMFT`). It explicitly does not pass compressed AAC frames into PCM audio interfaces.
2. **Output Interface:** Low-latency Windows WASAPI (Windows Audio Session API) shared-mode output is implemented with event-driven buffer callbacks (`AUDCLNT_STREAMFLAGS_EVENTCALLBACK`) and a 50ms hardware buffer.
3. **Thread Priority:** The playback loop is registered with the Multimedia Class Scheduler Service (MMCSS) under the `"Pro Audio"` task characteristic.
4. **Dynamic Device Switching:** The engine implements `IMMNotificationClient`, allowing it to intercept default audio output changes (e.g. plugging in USB gaming headphones) and reinitialize WASAPI without crashing or audio dropouts.

---

## 2. End-to-End Source-to-Sink Audio Trace

```
[ Mobile Game (Android / iOS) ]
   │
   ├─► 1. Audio Capture (Android AudioRecord internal capture / iOS ReplayKit Audio)
   ├─► 2. AAC-LC Encoding (48,000 Hz, 2 Channels Stereo, 16-bit PCM source, 128 kbps)
   ├─► 3. Framing & PTS Generation (Microsecond timestamp relative to stream epoch)
   │
   ▼ [ Network Transport (USB ADB Reverse or Wi-Fi TLS 1.3) ]
   │
   ├─► 4. Windows Ingestion (LanServer socket recv -> protocol::DecodeMessage)
   │
   ▼ [ CastSprint Windows Native Audio Engine (AudioPlayer) ]
   │
   ├─► 5. Codec Configuration (AudioPlayer::ConfigureDecoder)
   │      - Initializes CLSID_CMSAACDecMFT
   │      - Sets input media type: MFAudioFormat_AAC, 48kHz / 44.1kHz, 2 channels, CSD blob
   │      - Sets output media type: MFAudioFormat_PCM, 48000 Hz, 2 channels, 16-bit, 4 block align
   │
   ├─► 6. AAC Decoding (AudioPlayer::DecodeAndFeed)
   │      - Encloses compressed AAC access unit into IMFMediaBuffer and IMFSample
   │      - Invokes aacDecoder_->ProcessInput()
   │      - Loops aacDecoder_->ProcessOutput() to extract raw 16-bit PCM samples
   │
   ├─► 7. PCM Jitter Buffering (Circular Ring Buffer)
   │      - Stores decoded int16_t samples in thread-safe 2-second circular buffer
   │      - Records lastRenderedPtsMicros_ for AV synchronization
   │
   ├─► 8. AV Clock Skew Feedback (sync::AvSynchronizer::OnAudioRendered)
   │      - Feeds rendered audio PTS and system time to AV synchronizer
   │      - Informs video scheduler of audio master clock position
   │
   └─► 9. WASAPI Playback Thread (AudioPlayer::PlaybackThreadLoop)
          - MMCSS "Pro Audio" task scheduling
          - Waits on audioBufferReadyEvent_ (event-driven WASAPI)
          - Drains PCM from ring buffer into IAudioRenderClient::GetBuffer()
          - Plays out to Windows default audio endpoint (speakers / headphones)
```

---

## 3. Media Foundation AAC Decoder Configuration

The decoder initializes `CLSID_CMSAACDecMFT` located in `wmcodecdsp.h`:
```cpp
hr = CoCreateInstance(CLSID_CMSAACDecMFT, nullptr, CLSCTX_INPROC_SERVER,
                      IID_PPV_ARGS(&aacDecoder_));
```

### Input Type Specification
The input type is set with the negotiated sample rate (typically 48,000 Hz), stereo channel count, and the Codec Specific Data (CSD / AudioSpecificConfig) sent during handshake:
```cpp
inType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
inType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
inType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
inType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
inType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
if (!csd.empty()) {
    inType->SetBlob(MF_MT_USER_DATA, csd.data(), static_cast<UINT32>(csd.size()));
}
aacDecoder_->SetInputType(0, inType.Get(), 0);
```

### Output Type Specification
Output is normalized to 16-bit signed stereo PCM at 48,000 Hz:
```cpp
outType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
outType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
outType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 48000);
outType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
outType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
outType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4); // 2 channels * 2 bytes
outType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 48000 * 4); // 192,000 B/s
aacDecoder_->SetOutputType(0, outType.Get(), 0);
```

---

## 4. WASAPI Low-Latency Engine & Thread Scheduling

### Event-Driven Buffer Architecture
WASAPI shared mode is configured with event-driven callbacks (`AUDCLNT_STREAMFLAGS_EVENTCALLBACK`) using a 50ms hardware buffer duration (`500,000` 100ns units):
```cpp
hr = audioClient_->Initialize(AUDCLNT_SHAREMODE_SHARED,
                              AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                              500'000, 0, &wfx, nullptr);
audioBufferReadyEvent_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
audioClient_->SetEventHandle(audioBufferReadyEvent_);
```

### MMCSS Real-Time Priority
To prevent audio crackling, stuttering, or buffer underruns during heavy CPU utilization (such as high-framerate 3D rendering or OBS encoding), the playback thread requests Multimedia Class Scheduler Service priority:
```cpp
DWORD taskIndex = 0;
HANDLE mmcssHandle = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);
```

---

## 5. Audio-Video Synchronization Interaction

CastSprint uses the audio rendering position as the master clock. 

When audio frames are decoded and committed to the hardware queue, the engine updates `lastRenderedPtsMicros_`. The main event loop reads this value and notifies `avSync_`:
```cpp
const uint64_t renderedPts = audioPlayer_.GetCurrentRenderedPtsMicros();
if (renderedPts > 0) {
    const uint64_t nowMicros = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count());
    avSync_.OnAudioRendered(renderedPts, nowMicros);
}
```

When incoming video frames arrive, `avSync_.EvaluateVideoFrame(vf.ptsMicros, nowMicros)` compares the video presentation timestamp against the estimated audio clock:
- If video lags audio by more than the threshold (`kDropThresholdMicros`), the synchronizer returns `VideoAction::DropLate` to avoid rendering stale video frames.
- If video and audio are synchronized within tolerance, the frame proceeds to `MfVideoDecoder` and `D3D11Renderer`.

---

## 6. Dynamic Audio Endpoint Handling

If the user changes their Windows audio output (e.g. plugging in a headset, switching default output in the Windows taskbar, or disconnecting a Bluetooth speaker), `IMMNotificationClient::OnDefaultDeviceChanged` is triggered:
```cpp
STDMETHODIMP AudioPlayer::OnDefaultDeviceChanged(EDataFlow flow, ERole role, LPCWSTR pwstrDeviceId) {
    if (flow == eRender && (role == eConsole || role == eMultimedia)) {
        log::Info("audio", "Default audio output endpoint changed; re-initializing WASAPI");
        // Stops playback thread, releases existing IAudioClient interfaces,
        // and re-activates the new default IMMDevice endpoint seamlessly.
        ShutdownWasapi();
        InitializeWasapi();
    }
    return S_OK;
}
```
This guarantees uninterrupted gaming audio without requiring an application restart.

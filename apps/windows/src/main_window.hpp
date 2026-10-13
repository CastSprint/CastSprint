#pragma once
#include <windows.h>

#include "d3d11_renderer.hpp"
#include "audio_player.hpp"
#include "mp4_recorder.hpp"
#include "lan_server.hpp"
#include "castsprint/sync/av_sync.hpp"

namespace castsprint::windows {

class MainWindow {
public:
    MainWindow();
    ~MainWindow();
    MainWindow(const MainWindow&) = delete;
    MainWindow& operator=(const MainWindow&) = delete;

    bool Create(HINSTANCE instance, bool visible);
    // Blocking message loop; renders on demand (WM_PAINT) — no busy-waiting.
    int Run();
    // Renders `frames` frames then destroys the window. Used by --smoke-test.
    bool RunSmokeTest(int frames);

    void SetPreset(sync::SyncPreset preset);
    void ToggleRecording();
    void SetAudioOffset(int64_t offsetMicros);

private:
    static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
    LRESULT HandleMessage(UINT, WPARAM, LPARAM);
    void UpdateTitleBar();

    HWND hwnd_ = nullptr;
    HINSTANCE instance_ = nullptr;
    D3D11Renderer renderer_;
    bool rendererFailed_ = false;

    AudioPlayer audioPlayer_;
    Mp4Recorder recorder_;
    LanServer lanServer_;
    sync::AvSynchronizer avSync_;

    sync::SyncPreset currentPreset_ = sync::SyncPreset::Balanced;
    uint32_t streamWidth_ = 1920;
    uint32_t streamHeight_ = 1080;
    uint32_t streamFps_ = 60;
    uint32_t streamBitrate_ = 12'000'000;
    bool hasAudioConfig_ = false;
};

}  // namespace castsprint::windows

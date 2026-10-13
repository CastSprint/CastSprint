#pragma once
#include <windows.h>
#include <string>

#include "d3d11_renderer.hpp"
#include "audio_player.hpp"
#include "mp4_recorder.hpp"
#include "lan_server.hpp"
#include "castsprint/sync/av_sync.hpp"

namespace castsprint::windows {

enum class ScreenTab {
    Home = 0,
    GamingView = 1,
    StreamSettings = 2,
    Recording = 3,
    Performance = 4,
    Settings = 5
};

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

    void SetTab(ScreenTab tab);
    void ToggleFullscreen();
    void SetPreset(sync::SyncPreset preset);
    void ToggleRecording();
    void SetAudioOffset(int64_t offsetMicros);
    void ExportLogs();

private:
    static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
    LRESULT HandleMessage(UINT, WPARAM, LPARAM);
    void UpdateTitleBar();

    // Custom dark UI painting for dashboard tabs
    void RenderUI(HDC hdc, const RECT& clientRect);
    void RenderNavBar(HDC memDC, int width);
    void RenderHomeScreen(HDC memDC, int width, int height);
    void RenderSettingsScreen(HDC memDC, int width, int height);
    void RenderRecordingScreen(HDC memDC, int width, int height);
    void RenderPerformanceScreen(HDC memDC, int width, int height);
    void RenderAppSettingsScreen(HDC memDC, int width, int height);

    void HandleMouseClick(int x, int y);

    HWND hwnd_ = nullptr;
    HINSTANCE instance_ = nullptr;
    D3D11Renderer renderer_;
    bool rendererFailed_ = false;

    AudioPlayer audioPlayer_;
    Mp4Recorder recorder_;
    LanServer lanServer_;
    sync::AvSynchronizer avSync_;

    ScreenTab currentTab_ = ScreenTab::Home;
    bool isFullscreen_ = false;
    WINDOWPLACEMENT prevPlacement_{sizeof(WINDOWPLACEMENT)};

    sync::SyncPreset currentPreset_ = sync::SyncPreset::Balanced;
    uint32_t streamWidth_ = 1920;
    uint32_t streamHeight_ = 1080;
    uint32_t streamFps_ = 60;
    uint32_t streamBitrate_ = 12'000'000;
    bool hasAudioConfig_ = false;

    std::wstring recordingFolderPath_;
    bool autoReconnect_ = true;
    bool startMinimized_ = false;
};

}  // namespace castsprint::windows

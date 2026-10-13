#include "main_window.hpp"
#include "log.hpp"

#include <chrono>
#include <iomanip>
#include <sstream>

namespace castsprint::windows {
namespace {
constexpr wchar_t kClassName[] = L"CastSprintReceiverWindow";
}

MainWindow::MainWindow() : avSync_(currentPreset_) {}

MainWindow::~MainWindow() {
    lanServer_.Stop();
    recorder_.Stop();
    audioPlayer_.Shutdown();
    if (hwnd_) DestroyWindow(hwnd_);
}

bool MainWindow::Create(HINSTANCE instance, bool visible) {
    instance_ = instance;
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &MainWindow::WndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wc.lpszClassName = kClassName;
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        log::Error("window", "RegisterClassExW failed");
        return false;
    }

    hwnd_ = CreateWindowExW(0, kClassName, L"CastSprint Receiver — initializing...", WS_OVERLAPPEDWINDOW,
                            CW_USEDEFAULT, CW_USEDEFAULT, 1280, 720, nullptr, nullptr, instance, this);
    if (!hwnd_) {
        log::Error("window", "CreateWindowExW failed");
        return false;
    }

    if (!renderer_.Initialize(hwnd_, /*allowWarpFallback=*/true)) {
        MessageBoxW(hwnd_, L"Direct3D 11 could not be initialized. Update your graphics driver.",
                    L"CastSprint", MB_ICONERROR | MB_OK);
        return false;
    }

    // Initialize Audio Engine
    audioPlayer_.Initialize();

    // Start LAN Receiver Server
    LanCallbacks callbacks;
    callbacks.onVideoConfig = [this](const protocol::VideoConfig& vc) {
        streamWidth_ = vc.width;
        streamHeight_ = vc.height;
        streamFps_ = vc.frameRate;
        streamBitrate_ = vc.bitrate;
        log::Info("receiver", "Stream configured: " + std::to_string(vc.width) + "x" +
                              std::to_string(vc.height) + " @ " + std::to_string(vc.frameRate) + "fps");
    };

    callbacks.onVideoFrame = [this](const protocol::VideoFrame& vf) {
        const uint64_t nowMicros = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count());

        // Audio clock synchronization evaluation
        const auto syncDec = avSync_.EvaluateVideoFrame(vf.ptsMicros, nowMicros);
        if (syncDec.action == sync::VideoAction::DropLate) {
            // Late frame dropped to maintain real-time gaming sync
            return;
        }

        // Write to native MP4 recorder if active
        if (recorder_.IsRecording()) {
            recorder_.WriteVideoFrame(vf.ptsMicros, vf.data, (vf.frameFlags & protocol::kFrameKeyframe) != 0);
        }

        // Render frame to D3D11 swap chain
        renderer_.RenderFrame();
    };

    callbacks.onAudioConfig = [this](const protocol::AudioConfig& ac) {
        hasAudioConfig_ = true;
        audioPlayer_.ConfigureDecoder(ac.sampleRate, ac.channels, ac.codecConfig);
    };

    callbacks.onAudioFrame = [this](const protocol::AudioFrame& af) {
        if (recorder_.IsRecording()) {
            recorder_.WriteAudioFrame(af.ptsMicros, af.data);
        }

        audioPlayer_.EnqueueAacFrame(af.ptsMicros, af.data);

        const uint64_t renderedPts = audioPlayer_.GetCurrentRenderedPtsMicros();
        if (renderedPts > 0) {
            const uint64_t nowMicros = static_cast<uint64_t>(
                std::chrono::duration_cast<std::chrono::microseconds>(
                    std::chrono::steady_clock::now().time_since_epoch()).count());
            avSync_.OnAudioRendered(renderedPts, nowMicros);
        }
    };

    callbacks.onStateChanged = [this](session::ConnectionState) {
        PostMessageW(hwnd_, WM_USER + 1, 0, 0);
    };

    lanServer_.Start(protocol::kDefaultPort, std::move(callbacks));

    // Periodic stats update timer (every 500ms)
    SetTimer(hwnd_, 1001, 500, nullptr);

    UpdateTitleBar();

    if (visible) {
        ShowWindow(hwnd_, SW_SHOWNORMAL);
        UpdateWindow(hwnd_);
    }
    log::Info("window", "Main window created and receiver listening");
    return true;
}

void MainWindow::UpdateTitleBar() {
    if (!hwnd_) return;

    std::wostringstream ss;
    ss << L"CastSprint — ";

    switch (lanServer_.State()) {
    case session::ConnectionState::Disconnected:
    case session::ConnectionState::Closed:
        ss << L"Disconnected";
        break;
    case session::ConnectionState::Listening:
        ss << L"Waiting for device | PIN: " << lanServer_.SessionPin().data()
           << L" | Port " << protocol::kDefaultPort;
        break;
    case session::ConnectionState::Handshaking:
        ss << L"Handshaking...";
        break;
    case session::ConnectionState::Connected: {
        const auto& s = lanServer_.Stats();
        ss << L"Connected (" << std::fixed << std::setprecision(1) << s.currentFps << L" FPS, "
           << std::setprecision(2) << s.currentBitrateMbps << L" Mbps)";
        break;
    }
    case session::ConnectionState::Reconnecting:
        ss << L"Reconnecting...";
        break;
    }

    if (recorder_.IsRecording()) {
        const uint64_t sec = recorder_.DurationMicros() / 1'000'000;
        ss << L" | [REC " << (sec / 60) << L":" << std::setw(2) << std::setfill(L'0') << (sec % 60) << L"]";
    }

    if (audioPlayer_.IsMuted()) {
        ss << L" | [MUTED]";
    }

    SetWindowTextW(hwnd_, ss.str().c_str());
}

void MainWindow::ToggleRecording() {
    if (recorder_.IsRecording()) {
        recorder_.Stop();
        log::Info("recorder", "Recording stopped by user");
        UpdateTitleBar();
    } else {
        const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        std::tm tmNow{};
        localtime_s(&tmNow, &now);

        std::wostringstream path;
        path << L"CastSprint_" << (tmNow.tm_year + 1900)
             << std::setw(2) << std::setfill(L'0') << (tmNow.tm_mon + 1)
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_mday << L"_"
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_hour
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_min
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_sec << L".mp4";

        recorder_.Start(path.str(), streamWidth_, streamHeight_, streamFps_,
                        streamBitrate_, hasAudioConfig_);
        UpdateTitleBar();
    }
}

void MainWindow::SetPreset(sync::SyncPreset preset) {
    currentPreset_ = preset;
    avSync_.SetPreset(preset);
    log::Info("preset", "Preset switched");
}

void MainWindow::SetAudioOffset(int64_t offsetMicros) {
    avSync_.SetUserAudioOffsetMicros(offsetMicros);
    log::Info("audio", "Audio offset set to " + std::to_string(offsetMicros / 1000) + "ms");
}

int MainWindow::Run() {
    MSG msg{};
    BOOL r;
    while ((r = GetMessageW(&msg, nullptr, 0, 0)) != 0) {
        if (r == -1) {
            log::Error("window", "GetMessageW failed");
            return 1;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return rendererFailed_ ? 2 : static_cast<int>(msg.wParam);
}

bool MainWindow::RunSmokeTest(int frames) {
    for (int i = 0; i < frames; ++i) {
        if (!renderer_.RenderFrame()) return false;
        MSG msg{};
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    return !rendererFailed_;
}

LRESULT CALLBACK MainWindow::WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    MainWindow* self = nullptr;
    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
        self = static_cast<MainWindow*>(cs->lpCreateParams);
        self->hwnd_ = hwnd;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    } else {
        self = reinterpret_cast<MainWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }
    if (self) return self->HandleMessage(msg, wp, lp);
    return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT MainWindow::HandleMessage(UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_TIMER:
        if (wp == 1001) {
            UpdateTitleBar();
            return 0;
        }
        break;
    case WM_USER + 1:
        UpdateTitleBar();
        return 0;
    case WM_KEYDOWN:
        switch (wp) {
        case 'R':
            ToggleRecording();
            return 0;
        case 'M':
            audioPlayer_.SetMuted(!audioPlayer_.IsMuted());
            UpdateTitleBar();
            return 0;
        case VK_UP:
            audioPlayer_.SetVolume(audioPlayer_.GetVolume() + 0.05f);
            return 0;
        case VK_DOWN:
            audioPlayer_.SetVolume(audioPlayer_.GetVolume() - 0.05f);
            return 0;
        case VK_OEM_4: // '['
            SetAudioOffset(avSync_.UserAudioOffsetMicros() - 10'000);
            return 0;
        case VK_OEM_6: // ']'
            SetAudioOffset(avSync_.UserAudioOffsetMicros() + 10'000);
            return 0;
        case '1':
            SetPreset(sync::SyncPreset::LowLatency);
            return 0;
        case '2':
            SetPreset(sync::SyncPreset::Balanced);
            return 0;
        case '3':
            SetPreset(sync::SyncPreset::HighQuality);
            return 0;
        default:
            break;
        }
        break;
    case WM_SIZE:
        if (!renderer_.Resize(LOWORD(lp), HIWORD(lp))) {
            rendererFailed_ = true;
            DestroyWindow(hwnd_);
        }
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        BeginPaint(hwnd, &ps);
        EndPaint(hwnd, &ps);
        if (!renderer_.RenderFrame()) {
            rendererFailed_ = true;
            DestroyWindow(hwnd_);
        }
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_DESTROY:
        KillTimer(hwnd_, 1001);
        SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
        hwnd_ = nullptr;
        PostQuitMessage(0);
        return 0;
    default:
        break;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

}  // namespace castsprint::windows

#include "main_window.hpp"
#include "log.hpp"

#include <chrono>
#include <iomanip>
#include <sstream>
#include <shlobj.h>
#include <shellapi.h>

namespace castsprint::windows {
namespace {
constexpr wchar_t kClassName[] = L"CastSprintReceiverWindow";
constexpr int kNavHeight = 46;

// Dark Gaming Color Palette
constexpr COLORREF kBgColor = RGB(11, 14, 25);           // #0B0E19 Deep Slate
constexpr COLORREF kCardBgColor = RGB(17, 24, 39);       // #111827 Dark Surface
constexpr COLORREF kCardBorder = RGB(31, 41, 55);        // #1F2937 Surface Border
constexpr COLORREF kAccentCyan = RGB(0, 229, 255);       // #00E5FF Electric Cyan
constexpr COLORREF kAccentBlue = RGB(2, 132, 199);       // #0284C7 Cyber Blue
constexpr COLORREF kTextWhite = RGB(248, 250, 252);      // #F8FAFC Bright White
constexpr COLORREF kTextMuted = RGB(148, 163, 184);      // #94A3B8 Muted Slate
constexpr COLORREF kTextDim = RGB(100, 116, 139);        // #64748B Dim Slate
constexpr COLORREF kGreen = RGB(16, 185, 129);           // #10B981 Emerald
constexpr COLORREF kRed = RGB(239, 68, 68);              // #EF4444 Recording Red
constexpr COLORREF kAmber = RGB(245, 158, 11);           // #F59E0B Warning Amber

void DrawRoundedBox(HDC hdc, int left, int top, int right, int bottom, COLORREF bg, COLORREF border) {
    HBRUSH hBrush = CreateSolidBrush(bg);
    HPEN hPen = CreatePen(PS_SOLID, 1, border);
    HGDIOBJ oldBrush = SelectObject(hdc, hBrush);
    HGDIOBJ oldPen = SelectObject(hdc, hPen);
    RoundRect(hdc, left, top, right, bottom, 12, 12);
    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(hBrush);
    DeleteObject(hPen);
}
}  // namespace

MainWindow::MainWindow() : avSync_(currentPreset_) {
    // Default recording folder: User's Videos\CastSprint\
    PWSTR pVideos = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Videos, 0, nullptr, &pVideos))) {
        recordingFolderPath_ = std::wstring(pVideos) + L"\\CastSprint";
        CoTaskMemFree(pVideos);
        CreateDirectoryW(recordingFolderPath_.c_str(), nullptr);
    } else {
        recordingFolderPath_ = L".";
    }
}

MainWindow::~MainWindow() {
    airplayReceiver_.Stop();
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
    wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(101));
    if (!wc.hIcon) wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wc.lpszClassName = kClassName;

    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        log::Error("window", "RegisterClassExW failed");
        return false;
    }

    hwnd_ = CreateWindowExW(0, kClassName, L"CastSprint — Gaming Screen Mirroring", WS_OVERLAPPEDWINDOW,
                            CW_USEDEFAULT, CW_USEDEFAULT, 1280, 750, nullptr, nullptr, instance, this);
    if (!hwnd_) {
        log::Error("window", "CreateWindowExW failed");
        return false;
    }

    if (!renderer_.Initialize(hwnd_, /*allowWarpFallback=*/true)) {
        MessageBoxW(hwnd_, L"Direct3D 11 could not be initialized. Update your graphics driver.",
                    L"CastSprint", MB_ICONERROR | MB_OK);
        return false;
    }

    // Initialize Video & Audio Engines
    audioPlayer_.Initialize();
    videoDecoder_.Initialize();
    videoDecoder_.SetFrameCallback([this](const DecodedFrame& frame) {
        renderer_.UpdateVideoFrame(frame.pData, frame.width, frame.height, frame.stride, DXGI_FORMAT_B8G8R8A8_UNORM);
        if (currentTab_ == ScreenTab::GamingView) {
            renderer_.RenderFrame();
        }
    });

    RefreshAdbStatus();

    // Start LAN Receiver Server
    LanCallbacks callbacks;
    callbacks.onVideoConfig = [this](const protocol::VideoConfig& vc) {
        streamWidth_ = vc.width;
        streamHeight_ = vc.height;
        streamFps_ = vc.frameRate;
        streamBitrate_ = vc.bitrate;
        videoDecoder_.Configure(vc.width, vc.height, vc.frameRate);
        log::Info("receiver", "Stream configured: " + std::to_string(vc.width) + "x" +
                              std::to_string(vc.height) + " @ " + std::to_string(vc.frameRate) + "fps");
    };

    callbacks.onVideoFrame = [this](const protocol::VideoFrame& vf) {
        const uint64_t nowMicros = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count());

        const auto syncDec = avSync_.EvaluateVideoFrame(vf.ptsMicros, nowMicros);
        if (syncDec.action == sync::VideoAction::DropLate) {
            return;
        }

        if (recorder_.IsRecording()) {
            recorder_.WriteVideoFrame(vf.ptsMicros, vf.data, (vf.frameFlags & protocol::kFrameKeyframe) != 0);
        }

        videoDecoder_.DecodeFrame(vf.ptsMicros, vf.data, (vf.frameFlags & protocol::kFrameKeyframe) != 0);
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

    callbacks.onStateChanged = [this](session::ConnectionState state) {
        if (state == session::ConnectionState::Connected) {
            // Automatically switch to Gaming View upon streaming connection
            currentTab_ = ScreenTab::GamingView;
        } else if (state == session::ConnectionState::Closed || state == session::ConnectionState::Error) {
            videoDecoder_.Flush();
            renderer_.ClearVideoFrame();
        }
        PostMessageW(hwnd_, WM_USER + 1, 0, 0);
    };

    lanServer_.Start(protocol::kDefaultPort, std::move(callbacks));

    // Configure and start native AirPlay receiver for iPhone / iPad mirroring
    airplayReceiver_.SetVideoHandler([this](std::span<const uint8_t> nalu, uint64_t ptsMicros) {
        if (recorder_.IsRecording()) {
            recorder_.WriteVideoFrame(ptsMicros, nalu, false);
        }
        videoDecoder_.DecodeFrame(ptsMicros, nalu, false);
    });

    airplayReceiver_.SetAudioHandler([this](std::span<const uint8_t> audioData, uint64_t ptsMicros) {
        audioPlayer_.EnqueueAacFrame(ptsMicros, audioData);
        if (recorder_.IsRecording()) {
            recorder_.WriteAudioFrame(ptsMicros, audioData);
        }
    });

    airplayReceiver_.SetStateChangedHandler([this](airplay::ReceiverState state) {
        if (state == airplay::ReceiverState::StreamingActive) {
            currentTab_ = ScreenTab::GamingView;
        } else if (state == airplay::ReceiverState::Stopped || state == airplay::ReceiverState::Error) {
            videoDecoder_.Flush();
            renderer_.ClearVideoFrame();
        }
        PostMessageW(hwnd_, WM_USER + 1, 0, 0);
    });

    airplayReceiver_.Start();

    SetTimer(hwnd_, 1001, 500, nullptr);
    UpdateTitleBar();

    if (visible) {
        ShowWindow(hwnd_, SW_SHOWNORMAL);
        UpdateWindow(hwnd_);
    }
    log::Info("window", "Main window created and receiver active");
    return true;
}

void MainWindow::SetTab(ScreenTab tab) {
    currentTab_ = tab;
    UpdateTitleBar();
    InvalidateRect(hwnd_, nullptr, TRUE);
}

void MainWindow::SetDeviceType(DeviceType type) {
    currentDeviceType_ = type;
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::SetAppleMode(AppleConnectionMode mode) {
    currentAppleMode_ = mode;
    airplay::AirPlayReceiverConfig cfg = airplayReceiver_.GetConfig();
    if (mode == AppleConnectionMode::AirPlayUsbHotspot) {
        cfg.enableUsbHotspotOnly = true;
    } else {
        cfg.enableUsbHotspotOnly = false;
    }
    airplayReceiver_.UpdateConfig(cfg);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::ToggleAirPlayReceiver() {
    if (airplayReceiver_.IsRunning()) {
        airplayReceiver_.Stop();
    } else {
        airplayReceiver_.Start();
    }
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::ToggleFullscreen() {
    if (!isFullscreen_) {
        GetWindowPlacement(hwnd_, &prevPlacement_);
        DWORD style = GetWindowLong(hwnd_, GWL_STYLE);
        SetWindowLong(hwnd_, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);
        HMONITOR hMon = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTOPRIMARY);
        MONITORINFO mi{sizeof(mi)};
        GetMonitorInfo(hMon, &mi);
        SetWindowPos(hwnd_, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                     mi.rcMonitor.right - mi.rcMonitor.left,
                     mi.rcMonitor.bottom - mi.rcMonitor.top,
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        isFullscreen_ = true;
        currentTab_ = ScreenTab::GamingView;
    } else {
        SetWindowLong(hwnd_, GWL_STYLE, GetWindowLong(hwnd_, GWL_STYLE) | WS_OVERLAPPEDWINDOW);
        SetWindowPlacement(hwnd_, &prevPlacement_);
        SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        isFullscreen_ = false;
    }
    UpdateTitleBar();
    InvalidateRect(hwnd_, nullptr, TRUE);
}

void MainWindow::UpdateTitleBar() {
    if (!hwnd_) return;

    std::wostringstream ss;
    ss << L"CastSprint — ";

    switch (currentTab_) {
    case ScreenTab::Home: ss << L"Home"; break;
    case ScreenTab::GamingView: ss << L"Gaming View"; break;
    case ScreenTab::StreamSettings: ss << L"Stream Settings"; break;
    case ScreenTab::Recording: ss << L"Recording"; break;
    case ScreenTab::Performance: ss << L"Performance Diagnostics"; break;
    case ScreenTab::Settings: ss << L"Settings"; break;
    }

    ss << L" | ";
    switch (lanServer_.State()) {
    case session::ConnectionState::Disconnected:
    case session::ConnectionState::Closed:
        ss << L"Disconnected";
        break;
    case session::ConnectionState::Listening:
        ss << L"PIN: " << lanServer_.SessionPin().data() << L" (Port " << protocol::kDefaultPort << L")";
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
        path << recordingFolderPath_ << L"\\CastSprint_" << (tmNow.tm_year + 1900)
             << std::setw(2) << std::setfill(L'0') << (tmNow.tm_mon + 1)
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_mday << L"_"
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_hour
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_min
             << std::setw(2) << std::setfill(L'0') << tmNow.tm_sec << L".mp4";

        recorder_.Start(path.str(), streamWidth_, streamHeight_, streamFps_,
                        streamBitrate_, hasAudioConfig_);
        UpdateTitleBar();
    }
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::SetPreset(sync::SyncPreset preset) {
    currentPreset_ = preset;
    avSync_.SetPreset(preset);
    log::Info("preset", "Preset switched");
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::SetAudioOffset(int64_t offsetMicros) {
    avSync_.SetUserAudioOffsetMicros(offsetMicros);
    log::Info("audio", "Audio offset set to " + std::to_string(offsetMicros / 1000) + "ms");
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void MainWindow::ExportLogs() {
    PWSTR pDesktop = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &pDesktop))) {
        std::wstring dest = std::wstring(pDesktop) + L"\\CastSprint_Diagnostics.log";
        CoTaskMemFree(pDesktop);
        CopyFileW(L"castsprint.log", dest.c_str(), FALSE);
        MessageBoxW(hwnd_, (L"Diagnostics log exported to:\n" + dest).c_str(),
                    L"Log Exported", MB_ICONINFORMATION | MB_OK);
    }
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
            if (currentTab_ != ScreenTab::GamingView) {
                InvalidateRect(hwnd_, nullptr, FALSE);
            }
            return 0;
        }
        break;
    case WM_USER + 1:
        UpdateTitleBar();
        InvalidateRect(hwnd_, nullptr, TRUE);
        return 0;
    case WM_LBUTTONDOWN:
        HandleMouseClick(LOWORD(lp), HIWORD(lp));
        return 0;
    case WM_KEYDOWN:
        switch (wp) {
        case VK_F11:
            ToggleFullscreen();
            return 0;
        case '1':
            SetTab(ScreenTab::Home);
            return 0;
        case '2':
            SetTab(ScreenTab::GamingView);
            return 0;
        case '3':
            SetTab(ScreenTab::StreamSettings);
            return 0;
        case '4':
            SetTab(ScreenTab::Recording);
            return 0;
        case '5':
            SetTab(ScreenTab::Performance);
            return 0;
        case '6':
            SetTab(ScreenTab::Settings);
            return 0;
        case 'R':
            ToggleRecording();
            return 0;
        case 'M':
            audioPlayer_.SetMuted(!audioPlayer_.IsMuted());
            UpdateTitleBar();
            InvalidateRect(hwnd_, nullptr, FALSE);
            return 0;
        case VK_UP:
            audioPlayer_.SetVolume(audioPlayer_.GetVolume() + 0.05f);
            InvalidateRect(hwnd_, nullptr, FALSE);
            return 0;
        case VK_DOWN:
            audioPlayer_.SetVolume(audioPlayer_.GetVolume() - 0.05f);
            InvalidateRect(hwnd_, nullptr, FALSE);
            return 0;
        case VK_OEM_4: // '['
            SetAudioOffset(avSync_.UserAudioOffsetMicros() - 10'000);
            return 0;
        case VK_OEM_6: // ']'
            SetAudioOffset(avSync_.UserAudioOffsetMicros() + 10'000);
            return 0;
        default:
            break;
        }
        break;
    case WM_SIZE: {
        UINT w = LOWORD(lp);
        UINT h = HIWORD(lp);
        if (!renderer_.Resize(w, h)) {
            rendererFailed_ = true;
            DestroyWindow(hwnd_);
        }
        return 0;
    }
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd_, &ps);
        RECT rc{};
        GetClientRect(hwnd_, &rc);

        if (currentTab_ == ScreenTab::GamingView && !isFullscreen_) {
            // Render navigation bar on top, D3D11 underneath
            RenderUI(hdc, rc);
            renderer_.RenderFrame();
        } else if (currentTab_ == ScreenTab::GamingView && isFullscreen_) {
            // Borderless fullscreen: Direct3D 11 owns entire viewport
            renderer_.RenderFrame();
        } else {
            // Dashboard screens
            RenderUI(hdc, rc);
        }

        EndPaint(hwnd_, &ps);
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

void MainWindow::HandleMouseClick(int x, int y) {
    if (y < kNavHeight) {
        // Navigation bar clicks
        int tabWidth = 140;
        if (x >= 10 && x < 10 + tabWidth) SetTab(ScreenTab::Home);
        else if (x >= 10 + tabWidth && x < 10 + tabWidth * 2) SetTab(ScreenTab::GamingView);
        else if (x >= 10 + tabWidth * 2 && x < 10 + tabWidth * 3) SetTab(ScreenTab::StreamSettings);
        else if (x >= 10 + tabWidth * 3 && x < 10 + tabWidth * 4) SetTab(ScreenTab::Recording);
        else if (x >= 10 + tabWidth * 4 && x < 10 + tabWidth * 5) SetTab(ScreenTab::Performance);
        else if (x >= 10 + tabWidth * 5 && x < 10 + tabWidth * 6) SetTab(ScreenTab::Settings);

        RECT rc{};
        GetClientRect(hwnd_, &rc);
        if (x >= rc.right - 120 && x <= rc.right - 10) {
            ToggleFullscreen();
        }
    } else {
        // Tab body action button clicks
        if (currentTab_ == ScreenTab::Home) {
            // Device Type Selector clicks
            if (y >= 115 && y <= 150) {
                if (x >= 40 && x <= 200) SetDeviceType(DeviceType::Android);
                else if (x >= 210 && x <= 370) SetDeviceType(DeviceType::AppleIOS);
            }

            if (currentDeviceType_ == DeviceType::Android) {
                if (y >= 325 && y <= 365 && x >= 60 && x <= 300) {
                    ExecuteAdbReverse();
                    InvalidateRect(hwnd_, nullptr, FALSE);
                } else if (y >= 470 && y <= 530 && x >= 40 && x <= 260) {
                    SetTab(ScreenTab::GamingView);
                }
            } else {
                // Apple Connection Mode Pill clicks
                if (y >= 160 && y <= 192) {
                    if (x >= 40 && x <= 180) SetAppleMode(AppleConnectionMode::AirPlayWiFi);
                    else if (x >= 190 && x <= 360) SetAppleMode(AppleConnectionMode::AirPlayUsbHotspot);
                    else if (x >= 370 && x <= 520) SetAppleMode(AppleConnectionMode::CastSprintApp);
                    else if (x >= 530 && x <= 710) SetAppleMode(AppleConnectionMode::DirectUsb);
                }
                // AirPlay Start/Stop button
                if (y >= 455 && y <= 495 && x >= 60 && x <= 240) {
                    ToggleAirPlayReceiver();
                }
                // Enter Gaming View button
                if (y >= 545 && y <= 590 && x >= 40 && x <= 260) {
                    SetTab(ScreenTab::GamingView);
                }
            }
        } else if (currentTab_ == ScreenTab::Recording) {
            if (y >= 160 && y <= 210 && x >= 40 && x <= 240) {
                ToggleRecording();
            } else if (y >= 230 && y <= 270 && x >= 40 && x <= 240) {
                ShellExecuteW(nullptr, L"explore", recordingFolderPath_.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            }
        } else if (currentTab_ == ScreenTab::StreamSettings) {
            if (y >= 140 && y <= 180) {
                if (x >= 40 && x <= 180) SetPreset(sync::SyncPreset::LowLatency);
                else if (x >= 200 && x <= 340) SetPreset(sync::SyncPreset::Balanced);
                else if (x >= 360 && x <= 500) SetPreset(sync::SyncPreset::HighQuality);
            }
        } else if (currentTab_ == ScreenTab::Settings) {
            if (y >= 360 && y <= 400 && x >= 40 && x <= 240) {
                ExportLogs();
            } else if (y >= 480 && y <= 520 && x >= 40 && x <= 240) {
                ShellExecuteW(nullptr, L"open", L"https://github.com/CastSprint/CastSprint", nullptr, nullptr, SW_SHOWNORMAL);
            }
        }
    }
}

void MainWindow::RenderUI(HDC hdc, const RECT& clientRect) {
    const int w = clientRect.right - clientRect.left;
    const int h = clientRect.bottom - clientRect.top;
    if (w <= 0 || h <= 0) return;

    HDC memDC = CreateCompatibleDC(hdc);
    HBITMAP memBitmap = CreateCompatibleBitmap(hdc, w, h);
    HGDIOBJ oldBitmap = SelectObject(memDC, memBitmap);

    // Deep Slate background
    HBRUSH bgBrush = CreateSolidBrush(kBgColor);
    FillRect(memDC, &clientRect, bgBrush);
    DeleteObject(bgBrush);

    RenderNavBar(memDC, w);

    if (currentTab_ != ScreenTab::GamingView) {
        switch (currentTab_) {
        case ScreenTab::Home: RenderHomeScreen(memDC, w, h); break;
        case ScreenTab::StreamSettings: RenderSettingsScreen(memDC, w, h); break;
        case ScreenTab::Recording: RenderRecordingScreen(memDC, w, h); break;
        case ScreenTab::Performance: RenderPerformanceScreen(memDC, w, h); break;
        case ScreenTab::Settings: RenderAppSettingsScreen(memDC, w, h); break;
        default: break;
        }
    }

    BitBlt(hdc, 0, 0, w, h, memDC, 0, 0, SRCCOPY);

    SelectObject(memDC, oldBitmap);
    DeleteObject(memBitmap);
    DeleteDC(memDC);
}

void MainWindow::RenderNavBar(HDC memDC, int width) {
    // Navigation bar background
    RECT navRect{0, 0, width, kNavHeight};
    HBRUSH navBrush = CreateSolidBrush(RGB(15, 23, 42)); // #0F172A
    FillRect(memDC, &navRect, navBrush);
    DeleteObject(navBrush);

    HPEN borderPen = CreatePen(PS_SOLID, 1, kCardBorder);
    HGDIOBJ oldPen = SelectObject(memDC, borderPen);
    MoveToEx(memDC, 0, kNavHeight - 1, nullptr);
    LineTo(memDC, width, kNavHeight - 1);
    SelectObject(memDC, oldPen);
    DeleteObject(borderPen);

    SetBkMode(memDC, TRANSPARENT);

    HFONT navFont = CreateFontW(15, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(memDC, navFont);

    const wchar_t* tabs[] = {
        L"[1] Home", L"[2] Gaming View", L"[3] Stream Settings",
        L"[4] Recording", L"[5] Performance", L"[6] Settings"
    };

    int tabWidth = 140;
    for (int i = 0; i < 6; ++i) {
        RECT tabR{10 + i * tabWidth, 0, 10 + (i + 1) * tabWidth, kNavHeight};
        const bool active = (static_cast<int>(currentTab_) == i);

        if (active) {
            SetTextColor(memDC, kAccentCyan);
            HPEN indPen = CreatePen(PS_SOLID, 3, kAccentCyan);
            HGDIOBJ oP = SelectObject(memDC, indPen);
            MoveToEx(memDC, tabR.left + 8, kNavHeight - 2, nullptr);
            LineTo(memDC, tabR.right - 8, kNavHeight - 2);
            SelectObject(memDC, oP);
            DeleteObject(indPen);
        } else {
            SetTextColor(memDC, kTextMuted);
        }

        DrawTextW(memDC, tabs[i], -1, &tabR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    }

    // Status chip
    RECT statusR{width - 260, 8, width - 130, kNavHeight - 8};
    const auto connState = lanServer_.State();
    const bool isAirPlayActive = (airplayReceiver_.State() == airplay::ReceiverState::StreamingActive);
    COLORREF statusColor = (connState == session::ConnectionState::Connected || isAirPlayActive) ? kGreen :
                           (connState == session::ConnectionState::Listening || airplayReceiver_.IsRunning()) ? kAccentCyan : kAmber;
    const wchar_t* statusText = (isAirPlayActive) ? L"● AIRPLAY ACTIVE" :
                                (connState == session::ConnectionState::Connected) ? L"● STREAMING" :
                                (airplayReceiver_.IsRunning() || connState == session::ConnectionState::Listening) ? L"● LISTENING" : L"● OFFLINE";

    DrawRoundedBox(memDC, statusR.left, statusR.top, statusR.right, statusR.bottom,
                   RGB(17, 24, 39), statusColor);
    SetTextColor(memDC, statusColor);
    DrawTextW(memDC, statusText, -1, &statusR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    // Fullscreen toggle button
    RECT fsR{width - 120, 8, width - 10, kNavHeight - 8};
    DrawRoundedBox(memDC, fsR.left, fsR.top, fsR.right, fsR.bottom,
                   RGB(30, 41, 59), kAccentBlue);
    SetTextColor(memDC, kTextWhite);
    DrawTextW(memDC, L"⛶ Fullscreen", -1, &fsR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    SelectObject(memDC, oldFont);
    DeleteObject(navFont);
}

void MainWindow::RenderHomeScreen(HDC memDC, int width, int height) {
    HFONT titleFont = CreateFontW(22, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                 DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                 CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT subFont = CreateFontW(13, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT btnFont = CreateFontW(14, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    // Title
    SelectObject(memDC, titleFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 40, 58, L"CastSprint Gaming Mirror", 24);

    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 40, 86, L"Ultra-low latency mobile screen and game audio mirroring for Windows (Android & iOS)", 85);

    // Device Type Tabs: [ 🤖 Android Device ] and [ 🍎 iPhone / iPad ]
    SelectObject(memDC, btnFont);
    bool isAndroid = (currentDeviceType_ == DeviceType::Android);
    bool isApple = (currentDeviceType_ == DeviceType::AppleIOS);

    DrawRoundedBox(memDC, 40, 115, 200, 148,
                   isAndroid ? RGB(2, 132, 199) : kCardBgColor,
                   isAndroid ? kAccentCyan : kCardBorder);
    SetTextColor(memDC, isAndroid ? kTextWhite : kTextMuted);
    RECT rAndroid{40, 115, 200, 148};
    DrawTextW(memDC, L"🤖 Android Device", -1, &rAndroid, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    DrawRoundedBox(memDC, 210, 115, 370, 148,
                   isApple ? RGB(2, 132, 199) : kCardBgColor,
                   isApple ? kAccentCyan : kCardBorder);
    SetTextColor(memDC, isApple ? kTextWhite : kTextMuted);
    RECT rApple{210, 115, 370, 148};
    DrawTextW(memDC, L"🍎 iPhone / iPad", -1, &rApple, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    DeleteObject(titleFont);
    DeleteObject(subFont);
    DeleteObject(btnFont);

    if (isAndroid) {
        RenderAndroidHome(memDC, width, height);
    } else {
        RenderAppleHome(memDC, width, height);
    }
}

void MainWindow::RenderAndroidHome(HDC memDC, int width, int height) {
    (void)height;
    HFONT cardTitleFont = CreateFontW(16, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT subFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    // Card 1: USB Connection
    int cardW = (width - 100) / 2;
    DrawRoundedBox(memDC, 40, 160, 40 + cardW, 460, kCardBgColor, kCardBorder);

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kAccentCyan);
    TextOutW(memDC, 60, 180, L"⚡ Android USB Gaming (Lowest Latency)", 38);

    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 60, 215, L"Recommended for competitive mobile gaming (~15ms latency).", 59);

    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 60, 245, L"1. Connect Android phone to PC with a USB cable.", 49);
    TextOutW(memDC, 60, 270, L"2. Enable Developer Options & USB Debugging on Android.", 55);

    // Live ADB Device Detection
    if (!adbDevices_.empty()) {
        std::wstring devInfo = L"Device: " + std::wstring(adbDevices_[0].model.begin(), adbDevices_[0].model.end()) +
                               (adbDevices_[0].isAuthorized ? L" (Authorized)" : L" (Pending USB Prompt)");
        SetTextColor(memDC, adbDevices_[0].isAuthorized ? kGreen : kAmber);
        TextOutW(memDC, 60, 295, devInfo.c_str(), static_cast<int>(devInfo.size()));
    } else {
        SetTextColor(memDC, kTextMuted);
        TextOutW(memDC, 60, 295, L"Scanning for ADB devices (check USB cable)...", 46);
    }

    // ADB Reverse Tunnel Button
    RECT adbBtnR{60, 325, 300, 365};
    DrawRoundedBox(memDC, adbBtnR.left, adbBtnR.top, adbBtnR.right, adbBtnR.bottom,
                   adbTunnelActive_ ? RGB(22, 101, 52) : RGB(30, 41, 59),
                   adbTunnelActive_ ? kGreen : kAccentCyan);
    SetTextColor(memDC, kTextWhite);
    DrawTextW(memDC, adbTunnelActive_ ? L"✓ Tunnel Active (27183)" : L"⚡ Run ADB Reverse Tunnel",
              -1, &adbBtnR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 60, 380, L"3. Open CastSprint on Android and tap 'Start Mirroring'.", 55);

    // Card 2: Wi-Fi Pairing
    DrawRoundedBox(memDC, 60 + cardW, 160, 60 + cardW * 2, 460, kCardBgColor, kCardBorder);

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kGreen);
    TextOutW(memDC, 80 + cardW, 180, L"📶 Secure Wi-Fi (Local LAN TLS)", 31);

    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 80 + cardW, 215, L"Zero cloud dependencies. End-to-end encrypted on local Wi-Fi.", 62);

    SetTextColor(memDC, kTextMuted);
    std::wstring pinStr = L"Receiver Session PIN: " + std::wstring(lanServer_.SessionPin().begin(), lanServer_.SessionPin().end());
    TextOutW(memDC, 80 + cardW, 250, pinStr.c_str(), static_cast<int>(pinStr.size()));

    std::wstring portStr = L"Listening Port: " + std::to_wstring(protocol::kDefaultPort);
    TextOutW(memDC, 80 + cardW, 275, portStr.c_str(), static_cast<int>(portStr.size()));

    std::wstring fpStr = L"SHA-256 Fingerprint: " + std::wstring(lanServer_.CertificateFingerprintSha256().begin(), lanServer_.CertificateFingerprintSha256().end()).substr(0, 32) + L"...";
    TextOutW(memDC, 80 + cardW, 300, fpStr.c_str(), static_cast<int>(fpStr.size()));

    TextOutW(memDC, 80 + cardW, 335, L"• Android auto-discovers via mDNS (_castsprint._tcp)", 52);
    TextOutW(memDC, 80 + cardW, 360, L"• Enter the PIN above on your phone to authorize streaming.", 59);

    // Action CTA
    DrawRoundedBox(memDC, 40, 480, 260, 525, RGB(2, 132, 199), kAccentCyan);
    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kTextWhite);
    RECT btnR{40, 480, 260, 525};
    DrawTextW(memDC, L"Enter Gaming View", -1, &btnR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    DeleteObject(cardTitleFont);
    DeleteObject(subFont);
}

void MainWindow::RenderAppleHome(HDC memDC, int width, int height) {
    (void)height;
    HFONT cardTitleFont = CreateFontW(16, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT subFont = CreateFontW(13, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT modeFont = CreateFontW(12, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    // Apple Connection Mode Pills
    SelectObject(memDC, modeFont);
    auto drawModePill = [&](int left, int right, const wchar_t* label, bool active) {
        DrawRoundedBox(memDC, left, 160, right, 192,
                       active ? RGB(2, 132, 199) : RGB(17, 24, 39),
                       active ? kAccentCyan : kCardBorder);
        SetTextColor(memDC, active ? kTextWhite : kTextMuted);
        RECT r{left, 160, right, 192};
        DrawTextW(memDC, label, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    };

    drawModePill(40, 180, L"📶 AirPlay Wi-Fi", currentAppleMode_ == AppleConnectionMode::AirPlayWiFi);
    drawModePill(190, 360, L"⚡ USB Hotspot (Wired)", currentAppleMode_ == AppleConnectionMode::AirPlayUsbHotspot);
    drawModePill(370, 520, L"🎮 CastSprint iOS App", currentAppleMode_ == AppleConnectionMode::CastSprintApp);
    drawModePill(530, 710, L"🔒 Direct USB (Blocked)", currentAppleMode_ == AppleConnectionMode::DirectUsb);

    int cardW = (width - 100) / 2;

    // Card 1: Receiver Status & Controls
    DrawRoundedBox(memDC, 40, 205, 40 + cardW, 530, kCardBgColor, kCardBorder);

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kAccentCyan);
    TextOutW(memDC, 60, 225, L"AirPlay Receiver Engine", 23);

    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextWhite);

    bool isApRunning = airplayReceiver_.IsRunning();
    COLORREF apStatusCol = isApRunning ? kGreen : kAmber;
    std::wstring apStatusText = isApRunning ? L"● ACTIVE (Ready for iOS Mirroring)" : L"● STOPPED";

    DrawRoundedBox(memDC, 60, 255, 320, 285, RGB(17, 24, 39), apStatusCol);
    SetTextColor(memDC, apStatusCol);
    RECT apStatR{60, 255, 320, 285};
    DrawTextW(memDC, apStatusText.c_str(), -1, &apStatR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    SetTextColor(memDC, kTextWhite);
    std::wstring rxName = L"AirPlay Name: CastSprint Desktop";
    TextOutW(memDC, 60, 305, rxName.c_str(), static_cast<int>(rxName.size()));

    std::wstring portText = L"Service Ports: RTSP 7000 (TCP), RTP 7010 (UDP)";
    TextOutW(memDC, 60, 330, portText.c_str(), static_cast<int>(portText.size()));

    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 60, 365, L"• No mobile app or user account required.", 42);
    TextOutW(memDC, 60, 390, L"• Zero watermarks and no cloud streaming.", 42);
    TextOutW(memDC, 60, 415, L"• Direct D3D11 rendering with WASAPI game audio.", 48);

    // Toggle Button
    DrawRoundedBox(memDC, 60, 455, 240, 495, isApRunning ? RGB(239, 68, 68) : RGB(16, 185, 129), kTextWhite);
    SetTextColor(memDC, kTextWhite);
    RECT tglR{60, 455, 240, 495};
    DrawTextW(memDC, isApRunning ? L"Stop AirPlay" : L"Start AirPlay", -1, &tglR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    // Card 2: Guided Instructions
    DrawRoundedBox(memDC, 60 + cardW, 205, 60 + cardW * 2, 530, kCardBgColor, kCardBorder);

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kGreen);

    if (currentAppleMode_ == AppleConnectionMode::AirPlayWiFi) {
        TextOutW(memDC, 80 + cardW, 225, L"How to Mirror via Local Wi-Fi", 29);
        SelectObject(memDC, subFont);
        SetTextColor(memDC, kTextWhite);
        TextOutW(memDC, 80 + cardW, 260, L"Zero app installation needed on your iPhone or iPad:", 52);

        SetTextColor(memDC, kTextMuted);
        TextOutW(memDC, 80 + cardW, 295, L"1. Connect PC and iPhone to the same local Wi-Fi network.", 57);
        TextOutW(memDC, 80 + cardW, 325, L"2. Swipe down from top-right corner to open Control Center.", 58);
        TextOutW(memDC, 80 + cardW, 355, L"3. Tap the 'Screen Mirroring' icon (two rectangles).", 52);
        TextOutW(memDC, 80 + cardW, 385, L"4. Select 'CastSprint Desktop' from the device list.", 51);
        TextOutW(memDC, 80 + cardW, 415, L"5. Your screen and game audio will appear here at 60 FPS!", 58);
    } else if (currentAppleMode_ == AppleConnectionMode::AirPlayUsbHotspot) {
        TextOutW(memDC, 80 + cardW, 225, L"Wired USB Hotspot Mirroring (~25ms)", 35);
        SelectObject(memDC, subFont);
        SetTextColor(memDC, kTextWhite);
        TextOutW(memDC, 80 + cardW, 260, L"Lowest latency wired stream without third-party drivers:", 56);

        SetTextColor(memDC, kTextMuted);
        TextOutW(memDC, 80 + cardW, 295, L"1. Connect iPhone to PC via physical USB cable.", 47);
        TextOutW(memDC, 80 + cardW, 325, L"2. In iOS Settings > Personal Hotspot, turn ON (USB Only).", 58);
        TextOutW(memDC, 80 + cardW, 355, L"3. Windows automatically loads Apple Mobile Device Ethernet.", 60);
        TextOutW(memDC, 80 + cardW, 385, L"4. Open Control Center > Screen Mirroring > CastSprint Desktop.", 63);
        TextOutW(memDC, 80 + cardW, 415, L"5. Streams wired across USB at ~24ms latency. Zero driver hacks!", 64);
    } else if (currentAppleMode_ == AppleConnectionMode::CastSprintApp) {
        TextOutW(memDC, 80 + cardW, 225, L"CastSprint iOS Gaming App", 25);
        SelectObject(memDC, subFont);
        SetTextColor(memDC, kTextWhite);
        TextOutW(memDC, 80 + cardW, 260, L"Dedicated mobile client with custom CSP1 binary protocol:", 57);

        SetTextColor(memDC, kTextMuted);
        std::wstring pinStr = L"Receiver Session PIN: " + std::wstring(lanServer_.SessionPin().begin(), lanServer_.SessionPin().end());
        TextOutW(memDC, 80 + cardW, 295, pinStr.c_str(), static_cast<int>(pinStr.size()));
        TextOutW(memDC, 80 + cardW, 325, L"1. Open CastSprint on your iPhone or iPad.", 42);
        TextOutW(memDC, 80 + cardW, 355, L"2. Enter PIN above or tap auto-discovered receiver.", 51);
        TextOutW(memDC, 80 + cardW, 385, L"3. Tap 'Start Broadcast' to begin ScreenCaptureKit streaming.", 62);
    } else {
        SetTextColor(memDC, kRed);
        TextOutW(memDC, 80 + cardW, 225, L"Direct USB Protocol (Blocked)", 29);
        SelectObject(memDC, subFont);
        SetTextColor(memDC, kTextWhite);
        TextOutW(memDC, 80 + cardW, 260, L"Why this mode is disabled in production:", 40);

        SetTextColor(memDC, kTextMuted);
        TextOutW(memDC, 80 + cardW, 295, L"• Direct QuickTime USB bulk streaming without Hotspot requires", 62);
        TextOutW(memDC, 80 + cardW, 320, L"  replacing Apple's usbaapl64 driver with WinUSB via Zadig.", 59);
        TextOutW(memDC, 80 + cardW, 345, L"• Doing so permanently breaks Apple Devices, iTunes, and sync.", 62);
        TextOutW(memDC, 80 + cardW, 375, L"• Please use 'USB Hotspot (Wired)' mode instead! It uses Apple's", 64);
        TextOutW(memDC, 80 + cardW, 400, L"  official NDIS driver and preserves 100% of Apple features.", 61);
    }

    // Action CTA
    DrawRoundedBox(memDC, 40, 545, 260, 590, RGB(2, 132, 199), kAccentCyan);
    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kTextWhite);
    RECT btnR{40, 545, 260, 590};
    DrawTextW(memDC, L"Enter Gaming View (F11)", -1, &btnR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    DeleteObject(cardTitleFont);
    DeleteObject(subFont);
    DeleteObject(modeFont);
}

void MainWindow::RenderSettingsScreen(HDC memDC, int width, int height) {
    (void)height;
    HFONT cardTitleFont = CreateFontW(17, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT subFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 40, 68, L"Stream & Performance Profiles", 29);

    // Presets
    int presetW = 140;
    DrawRoundedBox(memDC, 40, 110, 40 + presetW, 160,
                   (currentPreset_ == sync::SyncPreset::LowLatency) ? RGB(2, 132, 199) : kCardBgColor,
                   (currentPreset_ == sync::SyncPreset::LowLatency) ? kAccentCyan : kCardBorder);
    DrawRoundedBox(memDC, 200, 110, 200 + presetW, 160,
                   (currentPreset_ == sync::SyncPreset::Balanced) ? RGB(2, 132, 199) : kCardBgColor,
                   (currentPreset_ == sync::SyncPreset::Balanced) ? kAccentCyan : kCardBorder);
    DrawRoundedBox(memDC, 360, 110, 360 + presetW, 160,
                   (currentPreset_ == sync::SyncPreset::HighQuality) ? RGB(2, 132, 199) : kCardBgColor,
                   (currentPreset_ == sync::SyncPreset::HighQuality) ? kAccentCyan : kCardBorder);

    RECT r1{40, 110, 40 + presetW, 160};
    RECT r2{200, 110, 200 + presetW, 160};
    RECT r3{360, 110, 360 + presetW, 160};
    DrawTextW(memDC, L"Low Latency", -1, &r1, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DrawTextW(memDC, L"Balanced", -1, &r2, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DrawTextW(memDC, L"High Quality", -1, &r3, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 40, 180, L"Low Latency: 720p/1080p, 60fps, 8Mbps, <25ms buffer. (Key 1)", 60);
    TextOutW(memDC, 40, 205, L"Balanced: 1080p, 60fps, 12Mbps, smooth AV sync. (Key 2)", 55);
    TextOutW(memDC, 40, 230, L"High Quality: Native/1440p/4K, 60fps, 20Mbps. (Key 3)", 53);

    // Audio Controls
    DrawRoundedBox(memDC, 40, 270, width - 40, 480, kCardBgColor, kCardBorder);
    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kAccentCyan);
    TextOutW(memDC, 60, 290, L"Audio & Synchronization", 23);

    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextWhite);
    std::wstring volStr = L"Playback Volume: " + std::to_wstring(static_cast<int>(audioPlayer_.GetVolume() * 100)) +
                          L"% " + (audioPlayer_.IsMuted() ? L"[MUTED]" : L"") + L" (Use Up/Down arrows, M to Mute)";
    TextOutW(memDC, 60, 330, volStr.c_str(), static_cast<int>(volStr.size()));

    std::wstring offStr = L"Audio Sync Delay Offset: " + std::to_wstring(avSync_.UserAudioOffsetMicros() / 1000) +
                          L" ms (Adjust with [ and ] keys)";
    TextOutW(memDC, 60, 365, offStr.c_str(), static_cast<int>(offStr.size()));

    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 60, 405, L"Audio Engine: Media Foundation AAC-LC Decoder -> WASAPI Shared-Mode (48kHz Stereo)", 83);
    TextOutW(memDC, 60, 430, L"Endpoint Migration: Automatically migrates when headphones/speakers are switched.", 80);

    DeleteObject(cardTitleFont);
    DeleteObject(subFont);
}

void MainWindow::RenderRecordingScreen(HDC memDC, int width, int height) {
    (void)height;
    HFONT cardTitleFont = CreateFontW(17, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT subFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 40, 68, L"Local MP4 Gaming Recording", 27);

    DrawRoundedBox(memDC, 40, 110, width - 40, 400, kCardBgColor, kCardBorder);

    // Status pill
    const bool isRec = recorder_.IsRecording();
    RECT pillR{60, 130, 200, 165};
    DrawRoundedBox(memDC, pillR.left, pillR.top, pillR.right, pillR.bottom,
                   isRec ? RGB(153, 27, 27) : RGB(30, 41, 59),
                   isRec ? kRed : kTextDim);
    SetTextColor(memDC, isRec ? kRed : kTextMuted);
    DrawTextW(memDC, isRec ? L"● RECORDING" : L"IDLE", -1, &pillR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    // Action button
    RECT actR{60, 180, 260, 225};
    DrawRoundedBox(memDC, actR.left, actR.top, actR.right, actR.bottom,
                   isRec ? RGB(220, 38, 38) : RGB(2, 132, 199), kAccentCyan);
    SetTextColor(memDC, kTextWhite);
    DrawTextW(memDC, isRec ? L"Stop Recording (R)" : L"Start Recording (R)", -1, &actR,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    // Duration & details
    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextWhite);
    const uint64_t sec = recorder_.DurationMicros() / 1'000'000;
    std::wostringstream durStr;
    durStr << L"Duration: " << (sec / 60) << L":" << std::setw(2) << std::setfill(L'0') << (sec % 60)
           << L" | Frames Recorded: " << recorder_.RecordedFrames();
    TextOutW(memDC, 280, 195, durStr.str().c_str(), static_cast<int>(durStr.str().size()));

    // Output folder
    TextOutW(memDC, 60, 250, L"Destination Directory:", 22);
    SetTextColor(memDC, kAccentCyan);
    TextOutW(memDC, 60, 275, recordingFolderPath_.c_str(), static_cast<int>(recordingFolderPath_.size()));

    // Open Folder button
    RECT folR{60, 310, 220, 350};
    DrawRoundedBox(memDC, folR.left, folR.top, folR.right, folR.bottom, RGB(30, 41, 59), kAccentBlue);
    SetTextColor(memDC, kTextWhite);
    DrawTextW(memDC, L"Open Folder", -1, &folR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 60, 370, L"Zero-transcode passthrough: muxes incoming H.264 video & AAC audio with zero CPU lag.", 86);

    DeleteObject(cardTitleFont);
    DeleteObject(subFont);
}

void MainWindow::RenderPerformanceScreen(HDC memDC, int width, int height) {
    (void)height;
    HFONT cardTitleFont = CreateFontW(17, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT subFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 40, 68, L"Live Diagnostics & Telemetry", 28);

    DrawRoundedBox(memDC, 40, 110, width - 40, 480, kCardBgColor, kCardBorder);

    const auto& s = lanServer_.Stats();
    SelectObject(memDC, subFont);

    auto drawMetric = [&](int x, int y, const wchar_t* label, const std::wstring& val, COLORREF valCol) {
        SetTextColor(memDC, kTextMuted);
        TextOutW(memDC, x, y, label, static_cast<int>(wcslen(label)));
        SetTextColor(memDC, valCol);
        TextOutW(memDC, x, y + 22, val.c_str(), static_cast<int>(val.size()));
    };

    std::wostringstream fpsStr, bitStr, rttStr, driftStr, vidFramesStr, audFramesStr, dropStr;
    fpsStr << std::fixed << std::setprecision(1) << s.currentFps << L" FPS";
    bitStr << std::fixed << std::setprecision(2) << s.currentBitrateMbps << L" Mbps";
    rttStr << (s.lastRttMicros / 1000) << L" ms";
    driftStr << (s.estimatedClockOffsetMicros / 1000) << L" ms";
    vidFramesStr << s.videoFramesReceived << L" (Keyframes: " << s.keyframesReceived << L")";
    audFramesStr << s.audioFramesReceived;
    dropStr << s.droppedFrames;

    drawMetric(70, 140, L"Received FPS", fpsStr.str(), kAccentCyan);
    drawMetric(280, 140, L"Network Bitrate", bitStr.str(), kGreen);
    drawMetric(490, 140, L"Dropped Frames", dropStr.str(), s.droppedFrames > 0 ? kAmber : kTextWhite);

    drawMetric(70, 220, L"Network RTT", rttStr.str(), kAccentCyan);
    drawMetric(280, 220, L"AV Clock Skew", driftStr.str(), kTextWhite);
    drawMetric(490, 220, L"Total Received", std::to_wstring(s.totalBytesReceived / (1024 * 1024)) + L" MB", kTextWhite);

    drawMetric(70, 300, L"Video Frames", vidFramesStr.str(), kTextWhite);
    drawMetric(280, 300, L"Audio Frames", audFramesStr.str(), kTextWhite);

    std::wstring gpuDesc = L"Renderer: " + renderer_.AdapterDescription() + (renderer_.UsingWarp() ? L" (WARP)" : L" (Hardware)");
    drawMetric(70, 380, L"Direct3D 11 Adapter", gpuDesc, kAccentCyan);

    DeleteObject(cardTitleFont);
    DeleteObject(subFont);
}

void MainWindow::RenderAppSettingsScreen(HDC memDC, int width, int height) {
    (void)height;
    HFONT cardTitleFont = CreateFontW(17, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HFONT subFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    SelectObject(memDC, cardTitleFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 40, 68, L"Application Settings & About", 28);

    DrawRoundedBox(memDC, 40, 110, width - 40, 520, kCardBgColor, kCardBorder);

    SelectObject(memDC, subFont);
    SetTextColor(memDC, kTextWhite);
    TextOutW(memDC, 60, 135, L"CastSprint — Free Native Gaming Screen Mirroring (Version 0.2.0 Beta)", 69);

    SetTextColor(memDC, kTextMuted);
    TextOutW(memDC, 60, 165, L"• Free forever. Zero paywalls, subscriptions, advertisements, or watermarks.", 76);
    TextOutW(memDC, 60, 190, L"• No cloud servers. Direct USB & local Wi-Fi TLS transmission.", 62);
    TextOutW(memDC, 60, 215, L"• OBS Studio Integration: Use Window Capture on 'CastSprint' with Windows 10+ capture method.", 94);

    // Export log button
    RECT logR{60, 260, 240, 300};
    DrawRoundedBox(memDC, logR.left, logR.top, logR.right, logR.bottom, RGB(30, 41, 59), kAccentBlue);
    SetTextColor(memDC, kTextWhite);
    DrawTextW(memDC, L"Export Diagnostic Log", -1, &logR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    // GitHub / Donate button
    RECT donR{60, 320, 240, 360};
    DrawRoundedBox(memDC, donR.left, donR.top, donR.right, donR.bottom, RGB(30, 41, 59), kGreen);
    SetTextColor(memDC, kTextWhite);
    DrawTextW(memDC, L"Support / GitHub", -1, &donR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    SetTextColor(memDC, kTextDim);
    TextOutW(memDC, 60, 385, L"Hotkeys: [1-6] Switch tabs | [F11] Borderless Fullscreen | [R] Record | [M] Mute | [[ / ]] Sync", 95);

    DeleteObject(cardTitleFont);
    DeleteObject(subFont);
}

void MainWindow::RefreshAdbStatus() {
    AdbTunnel::LocateAdb(adbPath_);
    if (!adbPath_.empty()) {
        adbDevices_ = AdbTunnel::ListDevices(adbPath_);
    } else {
        adbDevices_.clear();
    }
}

void MainWindow::ExecuteAdbReverse() {
    if (adbPath_.empty()) {
        RefreshAdbStatus();
    }
    if (!adbPath_.empty()) {
        adbTunnelActive_ = AdbTunnel::SetupReverseTunnel(adbPath_, protocol::kDefaultPort);
        if (adbTunnelActive_) {
            log::Info("adb", "Reverse tunnel active on port " + std::to_string(protocol::kDefaultPort));
        } else {
            log::Warn("adb", "Failed to setup reverse tunnel");
        }
    }
}

}  // namespace castsprint::windows

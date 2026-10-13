#include "main_window.hpp"

#include "log.hpp"

namespace castsprint::windows {
namespace {
constexpr wchar_t kClassName[] = L"CastSprintReceiverWindow";
}

MainWindow::~MainWindow() {
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

    hwnd_ = CreateWindowExW(0, kClassName, L"CastSprint Receiver — waiting for device", WS_OVERLAPPEDWINDOW,
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
    if (visible) {
        ShowWindow(hwnd_, SW_SHOWNORMAL);
        UpdateWindow(hwnd_);
    }
    log::Info("window", "Main window created");
    return true;
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
    case WM_SIZE:
        if (!renderer_.Resize(LOWORD(lp), HIWORD(lp))) {
            rendererFailed_ = true;
            DestroyWindow(hwnd_);
        }
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        BeginPaint(hwnd_, &ps);
        EndPaint(hwnd_, &ps);
        if (!renderer_.RenderFrame()) {
            rendererFailed_ = true;
            DestroyWindow(hwnd_);
        }
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;  // D3D owns the client area
    case WM_DESTROY:
        SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
        hwnd_ = nullptr;
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProcW(hwnd_, msg, wp, lp);
    }
}

}  // namespace castsprint::windows

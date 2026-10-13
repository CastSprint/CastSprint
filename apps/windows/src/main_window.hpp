#pragma once
#include <windows.h>

#include "d3d11_renderer.hpp"

namespace castsprint::windows {

class MainWindow {
public:
    MainWindow() = default;
    ~MainWindow();
    MainWindow(const MainWindow&) = delete;
    MainWindow& operator=(const MainWindow&) = delete;

    bool Create(HINSTANCE instance, bool visible);
    // Blocking message loop; renders on demand (WM_PAINT) — no busy-waiting.
    int Run();
    // Renders `frames` frames then destroys the window. Used by --smoke-test.
    bool RunSmokeTest(int frames);

private:
    static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
    LRESULT HandleMessage(UINT, WPARAM, LPARAM);

    HWND hwnd_ = nullptr;
    HINSTANCE instance_ = nullptr;
    D3D11Renderer renderer_;
    bool rendererFailed_ = false;
};

}  // namespace castsprint::windows

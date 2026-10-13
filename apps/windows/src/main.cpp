// CastSprint Receiver (Windows) — Phase 1 foundation entry point.
#include <windows.h>
#include <shellapi.h>

#include <cwchar>
#include <string>

#include "castsprint/protocol/protocol.hpp"
#include "log.hpp"
#include "main_window.hpp"

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    using namespace castsprint;

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    bool smokeTest = false;
    int argc = 0;
    if (LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc)) {
        for (int i = 1; i < argc; ++i) {
            if (std::wcscmp(argv[i], L"--smoke-test") == 0) smokeTest = true;
        }
        LocalFree(argv);
    }

    log::Info("app", "CastSprint Receiver starting (protocol v" + std::to_string(protocol::kVersion) +
                         ", default port " + std::to_string(protocol::kDefaultPort) + ")");

    windows::MainWindow window;
    if (!window.Create(instance, /*visible=*/!smokeTest)) return 1;

    if (smokeTest) {
        const bool ok = window.RunSmokeTest(3);
        log::Info("app", ok ? "Smoke test passed" : "Smoke test FAILED");
        return ok ? 0 : 1;
    }
    return window.Run();
}

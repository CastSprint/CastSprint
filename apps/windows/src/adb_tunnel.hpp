#pragma once
// CastSprint Windows Native ADB Tunnel & Reverse Port Forwarding Helper
// Automates 'adb reverse tcp:27183 tcp:27183' for Android USB gaming mirroring.

#include <string>
#include <vector>
#include <cstdint>

#ifdef _WIN32
#include <windows.h>
#endif

namespace castsprint::windows {

struct AdbDevice {
    std::string serial;
    std::string model;
    bool isAuthorized = false;
};

class AdbTunnel {
public:
    // Finds adb.exe in PATH or standard Android SDK platform-tools directories
    static bool LocateAdb(std::wstring& outPath) {
#ifdef _WIN32
        // 1. Try PATH
        wchar_t pathBuf[MAX_PATH];
        DWORD found = SearchPathW(nullptr, L"adb.exe", nullptr, MAX_PATH, pathBuf, nullptr);
        if (found > 0 && found < MAX_PATH) {
            outPath = pathBuf;
            return true;
        }

        // 2. Try %LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
        wchar_t localAppData[MAX_PATH];
        if (GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, MAX_PATH) > 0) {
            std::wstring candidate = std::wstring(localAppData) + L"\\Android\\Sdk\\platform-tools\\adb.exe";
            DWORD attr = GetFileAttributesW(candidate.c_str());
            if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY)) {
                outPath = candidate;
                return true;
            }
        }

        // 3. Try %PROGRAMFILES%\Android\platform-tools\adb.exe
        wchar_t progFiles[MAX_PATH];
        if (GetEnvironmentVariableW(L"ProgramFiles", progFiles, MAX_PATH) > 0) {
            std::wstring candidate = std::wstring(progFiles) + L"\\Android\\platform-tools\\adb.exe";
            DWORD attr = GetFileAttributesW(candidate.c_str());
            if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY)) {
                outPath = candidate;
                return true;
            }
        }
#else
        (void)outPath;
#endif
        return false;
    }

    // Queries connected Android devices via 'adb devices -l'
    static std::vector<AdbDevice> ListDevices(const std::wstring& adbPath) {
        std::vector<AdbDevice> devices;
#ifdef _WIN32
        std::string output = RunCommand(adbPath + L" devices -l");
        std::istringstream stream(output);
        std::string line;
        while (std::getline(stream, line)) {
            if (line.empty() || line.find("List of devices") != std::string::npos || line[0] == '*') {
                continue;
            }
            std::istringstream lineStream(line);
            std::string serial, state;
            if (lineStream >> serial >> state) {
                AdbDevice dev;
                dev.serial = serial;
                dev.isAuthorized = (state == "device");
                std::string token;
                while (lineStream >> token) {
                    if (token.find("model:") == 0) {
                        dev.model = token.substr(6);
                    }
                }
                if (dev.model.empty()) dev.model = "Android Device";
                devices.push_back(dev);
            }
        }
#else
        (void)adbPath;
#endif
        return devices;
    }

    // Automates 'adb reverse tcp:<port> tcp:<port>'
    static bool SetupReverseTunnel(const std::wstring& adbPath, uint16_t port = 27183) {
#ifdef _WIN32
        std::wstring cmd = adbPath + L" reverse tcp:" + std::to_wstring(port) + L" tcp:" + std::to_wstring(port);
        std::string output = RunCommand(cmd);
        // Success typically prints the port number (e.g. "27183\n")
        return output.find(std::to_string(port)) != std::string::npos || output.empty();
#else
        (void)adbPath;
        (void)port;
        return true;
#endif
    }

private:
#ifdef _WIN32
    static std::string RunCommand(const std::wstring& cmd) {
        std::string result;
        SECURITY_ATTRIBUTES sa{};
        sa.nLength = sizeof(sa);
        sa.bInheritHandle = TRUE;

        HANDLE hRead = nullptr, hWrite = nullptr;
        if (!CreatePipe(&hRead, &hWrite, &sa, 0)) return {};
        SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0);

        STARTUPINFOW si{};
        si.cb = sizeof(si);
        si.hStdOutput = hWrite;
        si.hStdError = hWrite;
        si.dwFlags |= STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;

        PROCESS_INFORMATION pi{};
        std::vector<wchar_t> cmdBuf(cmd.begin(), cmd.end());
        cmdBuf.push_back(L'\0');

        if (CreateProcessW(nullptr, cmdBuf.data(), nullptr, nullptr, TRUE,
                           CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
            CloseHandle(hWrite);
            hWrite = nullptr;

            char buffer[512];
            DWORD bytesRead = 0;
            while (ReadFile(hRead, buffer, sizeof(buffer), &bytesRead, nullptr) && bytesRead > 0) {
                result.append(buffer, bytesRead);
            }

            WaitForSingleObject(pi.hProcess, 3000);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        } else {
            if (hWrite) CloseHandle(hWrite);
        }

        if (hRead) CloseHandle(hRead);
        return result;
    }
#endif
};

} // namespace castsprint::windows

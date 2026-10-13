#include "log.hpp"

#include <windows.h>

#include <cstdio>
#include <mutex>
#include <string>

namespace castsprint::log {
namespace {
std::mutex g_mutex;
const char* Name(Level l) {
    switch (l) {
    case Level::Debug: return "DEBUG";
    case Level::Info: return "INFO";
    case Level::Warn: return "WARN";
    case Level::Error: return "ERROR";
    }
    return "?";
}
}  // namespace

void Write(Level level, std::string_view component, std::string_view message) {
    SYSTEMTIME t{};
    GetLocalTime(&t);
    char prefix[64];
    std::snprintf(prefix, sizeof(prefix), "%02u:%02u:%02u.%03u [%s] ", t.wHour, t.wMinute, t.wSecond,
                  t.wMilliseconds, Name(level));
    std::string line = prefix;
    line.append(component).append(": ").append(message).append("\n");

    std::lock_guard lock(g_mutex);
    OutputDebugStringA(line.c_str());
    std::fputs(line.c_str(), stderr);
    std::fflush(stderr);
}
}  // namespace castsprint::log

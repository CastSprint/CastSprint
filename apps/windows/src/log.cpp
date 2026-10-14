#include "log.hpp"

#ifdef _WIN32
#include <windows.h>
#else
#include <chrono>
#include <ctime>
#endif

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
    char prefix[64];
#ifdef _WIN32
    SYSTEMTIME t{};
    GetLocalTime(&t);
    std::snprintf(prefix, sizeof(prefix), "%02u:%02u:%02u.%03u [%s] ", t.wHour, t.wMinute, t.wSecond,
                  t.wMilliseconds, Name(level));
#else
    auto now = std::chrono::system_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;
    std::time_t tt = std::chrono::system_clock::to_time_t(now);
    std::tm tm_buf{};
    localtime_r(&tt, &tm_buf);
    std::snprintf(prefix, sizeof(prefix), "%02u:%02u:%02u.%03u [%s] ", tm_buf.tm_hour, tm_buf.tm_min,
                  tm_buf.tm_sec, static_cast<unsigned>(ms.count()), Name(level));
#endif
    std::string line = prefix;
    line.append(component).append(": ").append(message).append("\n");

    std::lock_guard lock(g_mutex);
#ifdef _WIN32
    OutputDebugStringA(line.c_str());
#endif
    std::fputs(line.c_str(), stderr);
    std::fflush(stderr);
}
}  // namespace castsprint::log

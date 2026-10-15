#include "log.hpp"
#include <iostream>
#include <chrono>
#include <iomanip>

namespace castsprint::linux_app {

void Log(LogLevel level, std::string_view msg) {
    const char* tag = "[INFO]";
    switch (level) {
        case LogLevel::Debug:   tag = "[DEBUG]"; break;
        case LogLevel::Info:    tag = "[INFO] "; break;
        case LogLevel::Warning: tag = "[WARN] "; break;
        case LogLevel::Error:   tag = "[ERROR]"; break;
    }

    auto now = std::chrono::system_clock::now();
    auto tt = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;

    struct tm tm_buf;
    localtime_r(&tt, &tm_buf);

    std::cout << std::put_time(&tm_buf, "%H:%M:%S.") << std::setfill('0') << std::setw(3) << ms.count()
              << " " << tag << " CastSprintLinux: " << msg << std::endl;
}

} // namespace castsprint::linux_app

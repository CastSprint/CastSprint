#pragma once
#include <string_view>
#include <iostream>

namespace castsprint::linux_app {

enum class LogLevel {
    Debug,
    Info,
    Warning,
    Error
};

void Log(LogLevel level, std::string_view msg);

} // namespace castsprint::linux_app

#pragma once
// Minimal structured logger: timestamp, level, component, message -> OutputDebugString + stderr.
#include <string_view>

namespace castsprint::log {
enum class Level { Debug, Info, Warn, Error };
void Write(Level level, std::string_view component, std::string_view message);
inline void Info(std::string_view c, std::string_view m) { Write(Level::Info, c, m); }
inline void Warn(std::string_view c, std::string_view m) { Write(Level::Warn, c, m); }
inline void Error(std::string_view c, std::string_view m) { Write(Level::Error, c, m); }
}  // namespace castsprint::log

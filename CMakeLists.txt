cmake_minimum_required(VERSION 3.22)
project(CastSprint VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(CASTSPRINT_BUILD_TESTS "Build CastSprint tests" ON)
option(CASTSPRINT_BUILD_RECEIVERS "Build platform receiver applications" ON)
option(CASTSPRINT_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" ON)

# Shared warning settings applied to every CastSprint target.
add_library(castsprint_warnings INTERFACE)
if(MSVC)
  target_compile_options(castsprint_warnings INTERFACE /W4 /permissive- /utf-8 /Zc:__cplusplus
    $<$<BOOL:${CASTSPRINT_WARNINGS_AS_ERRORS}>:/WX>)
else()
  target_compile_options(castsprint_warnings INTERFACE -Wall -Wextra -Wpedantic -Wconversion -Wshadow
    $<$<BOOL:${CASTSPRINT_WARNINGS_AS_ERRORS}>:-Werror>)
endif()

add_subdirectory(native/protocol)
add_subdirectory(native/sync)
add_subdirectory(native/session)

if(CASTSPRINT_BUILD_RECEIVERS AND WIN32)
  add_subdirectory(apps/windows)
elseif(CASTSPRINT_BUILD_RECEIVERS AND UNIX AND NOT APPLE)
  add_subdirectory(apps/linux)
endif()

if(CASTSPRINT_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests/protocol)
  add_subdirectory(tests/sync)
  add_subdirectory(tests/session)
  if(WIN32)
    add_subdirectory(tests/experimental)
  endif()
  if(WIN32)
    add_test(NAME windows_app_smoke COMMAND castsprint_receiver --smoke-test)
  elseif(UNIX AND NOT APPLE)
    add_test(NAME linux_app_smoke COMMAND castsprint_receiver_linux --smoke-test)
  endif()
endif()


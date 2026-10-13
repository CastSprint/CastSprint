add_executable(castsprint_receiver WIN32
  src/main.cpp
  src/main_window.cpp
  src/d3d11_renderer.cpp
  src/log.cpp
)
target_compile_definitions(castsprint_receiver PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
  _WIN32_WINNT=0x0A00)
target_link_libraries(castsprint_receiver PRIVATE
  CastSprint::protocol castsprint_warnings d3d11 dxgi)
if(MSVC)
  set_property(TARGET castsprint_receiver PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
endif()

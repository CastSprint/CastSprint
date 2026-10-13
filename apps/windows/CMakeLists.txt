add_executable(castsprint_receiver WIN32
  src/main.cpp
  src/main_window.cpp
  src/d3d11_renderer.cpp
  src/audio_player.cpp
  src/mp4_recorder.cpp
  src/lan_server.cpp
  src/log.cpp
)
target_compile_definitions(castsprint_receiver PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
  _WIN32_WINNT=0x0A00)
target_link_libraries(castsprint_receiver PRIVATE
  CastSprint::protocol
  CastSprint::sync
  CastSprint::session
  castsprint_warnings
  d3d11
  dxgi
  ws2_32
  crypt32
  secur32
  mfplat
  mfreadwrite
  mfuuid
  wmcodecdspuuid
  ole32
  mmdevapi
  avrt
  shell32
)
if(MSVC)
  set_property(TARGET castsprint_receiver PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
endif()

add_executable(castsprint_receiver WIN32
  src/main.cpp
  src/main_window.cpp
  src/d3d11_renderer.cpp
  src/audio_player.cpp
  src/mp4_recorder.cpp
  src/lan_server.cpp
  src/log.cpp
  src/airplay/airplay_rtsp_codec.cpp
  src/airplay/airplay_receiver.cpp
  src/experimental/iphone_usb_probe.cpp
  src/experimental/airplay_usb_receiver.cpp
  src/mf_video_decoder.cpp
  resources/version.rc
)
target_include_directories(castsprint_receiver PRIVATE src)
target_compile_definitions(castsprint_receiver PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
  _WIN32_WINNT=0x0A00)
target_link_libraries(castsprint_receiver PRIVATE
  CastSprint::protocol
  CastSprint::sync
  CastSprint::session
  castsprint_warnings
  d3d11
  d3dcompiler
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
  setupapi
  iphlpapi
)
if(MSVC)
  set_property(TARGET castsprint_receiver PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
endif()

install(TARGETS castsprint_receiver
  RUNTIME DESTINATION bin
)


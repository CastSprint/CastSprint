add_executable(probe_tests
  probe_tests.cpp
  ../../apps/windows/src/experimental/iphone_usb_probe.cpp
  ../../apps/windows/src/experimental/airplay_usb_receiver.cpp
  ../../apps/windows/src/airplay/airplay_rtsp_codec.cpp
  ../../apps/windows/src/airplay/airplay_receiver.cpp
)
target_include_directories(probe_tests PRIVATE ../../apps/windows/src/experimental ../../apps/windows/src)
target_link_libraries(probe_tests PRIVATE castsprint_warnings)
if(WIN32)
  target_compile_definitions(probe_tests PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_link_libraries(probe_tests PRIVATE setupapi mfplat mf uuid shlwapi iphlpapi ws2_32)
endif()
add_test(NAME probe_tests COMMAND probe_tests)

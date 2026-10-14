add_executable(probe_tests
  probe_tests.cpp
  ../../apps/windows/src/experimental/iphone_usb_probe.cpp
)
target_include_directories(probe_tests PRIVATE ../../apps/windows/src/experimental)
target_link_libraries(probe_tests PRIVATE castsprint_warnings)
if(WIN32)
  target_link_libraries(probe_tests PRIVATE setupapi mfplat mf uuid shlwapi)
endif()
add_test(NAME probe_tests COMMAND probe_tests)

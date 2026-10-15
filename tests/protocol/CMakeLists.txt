add_executable(protocol_tests protocol_tests.cpp)
target_link_libraries(protocol_tests PRIVATE CastSprint::protocol castsprint_warnings)
if(MSVC)
  # The CHECK macro intentionally uses the conventional do/while(0) wrapper.
  target_compile_options(protocol_tests PRIVATE /wd4127)
endif()
add_test(NAME protocol_tests COMMAND protocol_tests)

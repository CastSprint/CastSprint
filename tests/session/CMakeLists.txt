add_executable(session_tests session_tests.cpp)
target_link_libraries(session_tests PRIVATE CastSprint::session CastSprint::protocol castsprint_warnings)
add_test(NAME session_tests COMMAND session_tests)

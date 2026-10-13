add_executable(sync_tests sync_tests.cpp)
target_link_libraries(sync_tests PRIVATE CastSprint::sync castsprint_warnings)
add_test(NAME sync_tests COMMAND sync_tests)

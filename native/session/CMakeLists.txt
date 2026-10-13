add_library(castsprint_session STATIC
  session_manager.cpp
)
target_include_directories(castsprint_session PUBLIC .)
target_link_libraries(castsprint_session PUBLIC CastSprint::protocol castsprint_warnings)
add_library(CastSprint::session ALIAS castsprint_session)

add_library(castsprint_sync STATIC
  av_sync.cpp
)
target_include_directories(castsprint_sync PUBLIC .)
target_link_libraries(castsprint_sync PUBLIC castsprint_warnings)
add_library(CastSprint::sync ALIAS castsprint_sync)

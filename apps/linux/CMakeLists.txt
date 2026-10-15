add_executable(castsprint_receiver_linux
  src/main.cpp
  src/lan_server.cpp
  src/video_decoder.cpp
  src/audio_player.cpp
  src/log.cpp
)

target_include_directories(castsprint_receiver_linux PRIVATE src)
target_compile_definitions(castsprint_receiver_linux PRIVATE _GNU_SOURCE)

target_link_libraries(castsprint_receiver_linux PRIVATE
  CastSprint::protocol
  CastSprint::sync
  CastSprint::session
  castsprint_warnings
  pthread
)

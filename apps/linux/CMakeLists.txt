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

include(GNUInstallDirs)
install(TARGETS castsprint_receiver_linux
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/castsprint.desktop
  DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
  OPTIONAL
)

install(FILES ${CMAKE_SOURCE_DIR}/assest/logo.png
  DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/256x256/apps
  RENAME castsprint.png
  OPTIONAL
)


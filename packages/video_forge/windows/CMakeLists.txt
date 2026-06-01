cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "video_forge")
project(${PROJECT_NAME} LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(video_forge_bundled_libraries
  $<TARGET_FILE:video_forge>
  PARENT_SCOPE
)

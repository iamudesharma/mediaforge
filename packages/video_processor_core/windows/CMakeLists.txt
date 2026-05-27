cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flutter_video_processor")
project(${PROJECT_NAME} LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(flutter_video_processor_bundled_libraries
  $<TARGET_FILE:video_processor_core>
  PARENT_SCOPE
)

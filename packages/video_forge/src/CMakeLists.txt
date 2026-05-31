cmake_minimum_required(VERSION 3.10)
project(video_forge_library VERSION 1.0.0 LANGUAGES C CXX)

include(FetchContent)
FetchContent_Declare(
  Corrosion
  GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
  GIT_TAG v0.5.1
)
FetchContent_MakeAvailable(Corrosion)

set(RUST_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/../../../native/rust_core/Cargo.toml")

corrosion_import_crate(
  MANIFEST_PATH "${RUST_MANIFEST}"
  CRATES video_forge
  PROFILE release
)

set_target_properties(
  video_forge PROPERTIES
  OUTPUT_NAME "video_forge"
)

if(ANDROID)
  target_link_options(video_forge PRIVATE "-Wl,-z,max-page-size=16384")
endif()

add_library(video_forge_kit SHARED IMPORTED GLOBAL)
set_target_properties(
  video_forge_kit PROPERTIES
  IMPORTED_LOCATION "$<TARGET_FILE:video_forge>"
)

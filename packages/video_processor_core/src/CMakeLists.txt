cmake_minimum_required(VERSION 3.10)
project(video_processor_core_library VERSION 0.1.0 LANGUAGES C CXX)

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
  CRATES video_processor_core
  PROFILE release
)

set_target_properties(
  video_processor_core PROPERTIES
  OUTPUT_NAME "video_processor_core"
)

if(ANDROID)
  target_link_options(video_processor_core PRIVATE "-Wl,-z,max-page-size=16384")
endif()

add_library(flutter_video_processor SHARED IMPORTED GLOBAL)
set_target_properties(
  flutter_video_processor PROPERTIES
  IMPORTED_LOCATION "$<TARGET_FILE:video_processor_core>"
)

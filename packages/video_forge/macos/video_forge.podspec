#
# CocoaPods spec for video_forge (macOS).
#
# The Rust cdylib is bundled by the Flutter native-assets hook (hook/build.dart),
# not via vendored_frameworks. Vendoring a dynamic framework here plus
# `use_frameworks!` makes CocoaPods rebuild a framework with the same install_name
# as the binary inside it → linker error "can't link a dylib with itself".
#
# Before running the example: cargo build --release -p video_forge
# (see scripts/run-video-macos.sh).
#
Pod::Spec.new do |s|
  s.name             = 'video_forge'
  s.version          = '2.1.0'
  s.summary          = 'Rust-powered video processing for Flutter'
  s.description      = <<-DESC
High-performance video compression, transcoding, and thumbnails powered by Rust + FFmpeg.
                       DESC
  s.homepage         = 'https://github.com/iamudesharma/mediaforge'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'video_forge' => 'dev@video-forge.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

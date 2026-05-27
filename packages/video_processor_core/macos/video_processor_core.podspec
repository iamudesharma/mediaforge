#
# CocoaPods spec for video_processor_core (macOS).
#
# The Rust cdylib is bundled by the Flutter native-assets hook (hook/build.dart),
# not via vendored_frameworks. Vendoring a dynamic framework here plus
# `use_frameworks!` makes CocoaPods rebuild a framework with the same install_name
# as the binary inside it → linker error "can't link a dylib with itself".
#
# Before running the example: cargo build --release -p video_processor_core
# (see rust video/scripts/run-macos.sh).
#
Pod::Spec.new do |s|
  s.name             = 'video_processor_core'
  s.version          = '0.1.0'
  s.summary          = 'Rust-powered video processing for Flutter'
  s.description      = <<-DESC
High-performance video compression, transcoding, and thumbnails powered by Rust + FFmpeg.
                       DESC
  s.homepage         = 'https://github.com/your-org/video_processor_core'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'video_processor_core' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

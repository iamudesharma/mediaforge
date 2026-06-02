#
# CocoaPods spec for video_forge (iOS).
#
# Pre-build: ./scripts/run-ios.sh (packages Frameworks/video_forge.framework).
# Do not set OTHER_LDFLAGS => -framework video_forge when using
# vendored_frameworks — CocoaPods + use_frameworks! already links it; duplicate
# -framework causes "Can't link a dylib with itself" (same install_name).
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
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'
  s.static_framework = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'

  framework_path = File.join(__dir__, 'Frameworks', 'video_forge.framework')
  if File.exist?(framework_path)
    s.vendored_frameworks = 'Frameworks/video_forge.framework'
  end
end

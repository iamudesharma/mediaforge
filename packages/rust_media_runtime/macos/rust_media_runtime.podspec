Pod::Spec.new do |s|
  s.name             = 'rust_media_runtime'
  s.version          = '0.1.0'
  s.summary          = 'Rust media runtime playback engine'
  s.description      = <<-DESC
Rust media runtime playback engine for Flutter.
                       DESC
  s.homepage         = 'https://github.com/iamudesharma/rust_image'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'rust_media_runtime' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

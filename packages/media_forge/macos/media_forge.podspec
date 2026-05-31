Pod::Spec.new do |s|
  s.name             = 'media_forge'
  s.version          = '0.1.0'
  s.summary          = 'Media playback runtime engine'
  s.description      = <<-DESC
Media playback runtime engine for Flutter.
                       DESC
  s.homepage         = 'https://github.com/iamudesharma/rust_image'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'media_forge' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

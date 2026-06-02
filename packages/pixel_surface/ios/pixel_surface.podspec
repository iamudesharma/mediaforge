Pod::Spec.new do |s|
  s.name             = 'pixel_surface'
  s.version          = '1.1.0'
  s.summary          = 'Flutter GPU Texture bridge for rust_image workspace'
  s.description      = 'CVPixelBuffer-backed Flutter Texture (no Rust FFI).'
  s.homepage         = 'https://github.com/iamudesharma/rust_image'
  s.license          = { :type => 'MIT' }
  s.author           = { 'rust_image' => 'dev@rust_image.local' }
  s.module_name      = 'pixel_surface'
  s.source           = { :path => '.' }
  s.prepare_command = <<-CMD
    set -e
    mkdir -p "Classes/Darwin"
    rsync -a --delete "../darwin/Classes/" "Classes/Darwin/"
    mkdir -p "Tests"
    rsync -a --delete "../darwin/Tests/" "Tests/"
  CMD
  s.source_files        = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform            = :ios, '16.0'
  s.swift_version       = '5.0'
  s.frameworks          = 'Accelerate', 'Metal', 'CoreVideo', 'VideoToolbox'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*'
    test_spec.requires_app_host = false
  end
end

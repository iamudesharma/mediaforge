#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rust_image_core.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rust_image'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.module_name      = 'rust_image'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  # CocoaPods only compiles sources under the pod directory (not ../darwin).
  s.source_files     = 'Classes/**/*'
  s.resource_bundles = { 'rust_image_mediapipe' => ['../darwin/Resources/mediapipe/**'] }
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust rust_image_core',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/rust_image/librust_image_core.a"],
  }
  rust_ldflags = '$(inherited) -force_load "$(PODS_CONFIGURATION_BUILD_DIR)/rust_image/librust_image_core.a" -Wl,-u,_frb_get_rust_content_hash -Wl,-u,_rust_image_link_rust_for_frb'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => rust_ldflags,
    'DEAD_CODE_STRIPPING' => 'NO',
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => rust_ldflags,
    'DEAD_CODE_STRIPPING' => 'NO',
  }
end
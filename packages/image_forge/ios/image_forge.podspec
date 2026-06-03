#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint image_forge.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'image_forge'
  s.version          = '1.0.0'
  s.summary          = 'Full-featured GPU-accelerated Rust image processing engine for Flutter (filters, face beauty, layer composition, presets, multi-format encoding).'
  s.description      = <<-DESC
Full-featured GPU-accelerated Rust image processing engine for Flutter. Supports filters, face beauty, layer composition, presets, LUT, swipe looks, and multi-format encoding (JPEG, PNG, WebP, AVIF). Headless engine — no UI widgets. No editor.
                       DESC
  s.homepage         = 'https://github.com/iamudesharma/mediaforge'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MediaForge' => 'https://github.com/iamudesharma/mediaforge/issues' }
  s.module_name      = 'image_forge'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  # CocoaPods only compiles sources under the pod directory (not ../darwin).
  s.prepare_command = <<-CMD
    set -e
    mkdir -p "Classes/Darwin"
    rsync -a --delete "../darwin/Classes/" "Classes/Darwin/"
  CMD
  s.source_files = 'Classes/**/*'
  s.resource_bundles = { 'image_forge_mediapipe' => ['../darwin/Resources/mediapipe/**'] }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.dependency 'MediaPipeTasksVision', '0.10.14'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust image_forge',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/image_forge/libimage_forge.a"],
  }
  rust_ldflags = '$(inherited) -force_load "$(PODS_CONFIGURATION_BUILD_DIR)/image_forge/libimage_forge.a" -Wl,-u,_frb_get_rust_content_hash -Wl,-u,_rust_image_link_rust_for_frb'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # Link Rust into the plugin; keep FRB entry symbols for Release (not stripped).
    'OTHER_LDFLAGS' => rust_ldflags,
    'DEAD_CODE_STRIPPING' => 'NO',
  }
  # Propagate to Runner — FRB ExternalLibrary.process() resolves via dlsym(RTLD_DEFAULT).
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => rust_ldflags,
    'DEAD_CODE_STRIPPING' => 'NO',
  }
end
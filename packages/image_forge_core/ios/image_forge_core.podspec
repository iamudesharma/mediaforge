#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint image_forge_core.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'image_forge_core'
  s.version          = '1.0.0'
  s.summary          = 'Lightweight Rust image processing engine for Flutter (resize, crop, rotate, compress, EXIF, filters, GPU compute).'
  s.description      = <<-DESC
Lightweight Rust image processing engine for Flutter. Core operations only:
resize, crop, rotate, compress, thumbnails, EXIF, basic filters, GPU compute,
and multi-format encode/decode. Headless engine — no UI widgets. No face
beauty, mood presets, or LUT support. See image_forge for the full engine.
                       DESC
  s.homepage         = 'https://github.com/iamudesharma/mediaforge'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MediaForge' => 'https://github.com/iamudesharma/mediaforge/issues' }
  s.module_name      = 'image_forge_core'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '15.0'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.swift_version    = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust image_forge_core',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/image_forge_core/libimage_forge_core.a"],
  }
  rust_ldflags = '$(inherited) -force_load "$(PODS_CONFIGURATION_BUILD_DIR)/image_forge_core/libimage_forge_core.a" -Wl,-u,_frb_get_rust_content_hash'

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

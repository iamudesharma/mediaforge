/// FFmpeg libavutil (hwcontext_videotoolbox) references `__isPlatformVersionAtLeast`,
/// which lives in clang's iOS compiler-rt. Rust's iOS link does not pull it in automatically.
fn ios_clang_rt_force_load() -> Option<String> {
    let output = std::process::Command::new("xcrun")
        .args([
            "-sdk",
            "iphoneos",
            "clang",
            "--print-file-name=libclang_rt.ios.a",
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let path = String::from_utf8(output.stdout).ok()?.trim().to_string();
    if path.is_empty() || !std::path::Path::new(&path).is_file() {
        return None;
    }
    Some(format!("-Wl,-force_load,{path}"))
}

fn main() {
    println!("cargo:rerun-if-env-changed=FFMPEG_DIR");
    println!("cargo:rerun-if-env-changed=PKG_CONFIG_PATH");

    if let Ok(ffmpeg_dir) = std::env::var("FFMPEG_DIR") {
        let lib_dir = format!("{ffmpeg_dir}/lib");
        let include_dir = format!("{ffmpeg_dir}/include");
        println!("cargo:rustc-link-search=native={lib_dir}");
        println!("cargo:rustc-link-lib=avcodec");
        println!("cargo:rustc-link-lib=avformat");
        println!("cargo:rustc-link-lib=avutil");
        println!("cargo:rustc-link-lib=swscale");
        println!("cargo:rustc-link-lib=swresample");
        println!("cargo:rustc-link-lib=z");
        println!("cargo:rustc-env=FFMPEG_INCLUDE_DIR={include_dir}");
    }

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-link-lib=c++_shared");
        // FFmpeg MediaCodec/JNI (built with --enable-mediacodec --enable-jni).
        println!("cargo:rustc-link-lib=android");
        println!("cargo:rustc-link-lib=mediandk");
        println!("cargo:rustc-link-lib=log");
        println!("cargo:rustc-link-lib=jnigraphics");
    }

    if matches!(
        std::env::var("CARGO_CFG_TARGET_OS").as_deref(),
        Ok("ios") | Ok("macos")
    ) {
        for framework in [
            "VideoToolbox",
            "CoreMedia",
            "CoreVideo",
            "CoreFoundation",
            "AudioToolbox",
            "Security",
        ] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
        println!("cargo:rustc-link-lib=iconv");
        println!("cargo:rustc-link-lib=bz2");
    }

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios") {
        println!("cargo:rustc-link-arg=-miphoneos-version-min=13.0");
        if let Some(arg) = ios_clang_rt_force_load() {
            println!("cargo:rustc-link-arg={arg}");
        }
    }
}

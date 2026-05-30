//! Native link flags for FFmpeg / VideoToolbox (aligned with `video_processor_core`).
//!
//! Set `FFMPEG_DIR` to a VT-enabled FFmpeg prefix (e.g. `tools/ffmpeg/dist/apple/<triple>`)
//! before building when Homebrew FFmpeg lacks `hevc_videotoolbox`.

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
        eprintln!("[rust_media_runtime/build] FFMPEG_DIR={ffmpeg_dir}");
    }

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-link-lib=c++_shared");
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
}

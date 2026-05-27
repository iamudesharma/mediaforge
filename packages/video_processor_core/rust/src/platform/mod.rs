//! Platform-specific hooks for hardware acceleration.

pub fn platform_name() -> &'static str {
    std::env::consts::OS
}

/// Prefer hardware encoders on mobile (VideoToolbox / MediaCodec).
pub fn default_prefer_hardware_encoder() -> bool {
    cfg!(any(target_os = "android", target_os = "ios"))
}

pub fn supports_hardware_encoding() -> bool {
    matches!(
        std::env::consts::OS,
        "android" | "ios" | "macos" | "linux" | "windows"
    )
}

#[cfg(target_os = "android")]
pub mod android;

#[cfg(target_os = "android")]
pub fn mediacodec_available() -> bool {
    probe_encoder("h264_mediacodec")
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub mod apple {
    pub fn videotoolbox_available() -> bool {
        super::probe_encoder("h264_videotoolbox")
    }
}

#[cfg(target_os = "linux")]
pub mod linux {
    pub fn vaapi_available() -> bool {
        super::probe_encoder("h264_vaapi")
    }
}

#[cfg(target_os = "windows")]
pub mod windows {
    pub fn nvenc_available() -> bool {
        super::probe_encoder("h264_nvenc")
    }
}

fn probe_encoder(name: &str) -> bool {
    ffmpeg_next::encoder::find_by_name(name).is_some()
}

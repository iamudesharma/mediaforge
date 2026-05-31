use crate::error::{Result, VideoProcessorError};
use crate::types::VideoCodec;

#[derive(Clone, Debug)]
pub struct EncoderSelection {
    pub name: String,
    pub is_hardware: bool,
}

pub fn encoder_candidates(codec: &VideoCodec) -> Vec<&'static str> {
    match (codec, std::env::consts::OS) {
        (VideoCodec::H264, "android") => {
            vec!["h264_mediacodec", "libx264", "h264"]
        }
        (VideoCodec::Hevc, "android") => {
            vec!["hevc_mediacodec", "libx265", "hevc"]
        }
        (VideoCodec::H264, "ios") => {
            vec!["h264_videotoolbox", "h264_mediacodec", "libx264", "h264"]
        }
        (VideoCodec::Hevc, "ios") => {
            vec!["hevc_videotoolbox", "hevc_mediacodec", "libx265", "hevc"]
        }
        (VideoCodec::H264, "macos") => {
            vec!["h264_videotoolbox", "libx264", "h264"]
        }
        (VideoCodec::Hevc, "macos") => {
            vec!["hevc_videotoolbox", "libx265", "hevc"]
        }
        (VideoCodec::H264, "linux") => {
            vec!["libx264", "h264_vaapi", "h264_nvenc", "h264"]
        }
        (VideoCodec::Hevc, "linux") => {
            vec!["libx265", "hevc_vaapi", "hevc_nvenc", "hevc"]
        }
        (VideoCodec::H264, "windows") => {
            vec!["libx264", "h264_nvenc", "h264_qsv", "h264"]
        }
        (VideoCodec::Hevc, "windows") => {
            vec!["libx265", "hevc_nvenc", "hevc_qsv", "hevc"]
        }
        (VideoCodec::H264, _) => vec!["libx264", "h264"],
        (VideoCodec::Hevc, _) => vec!["libx265", "hevc"],
    }
}

/// Software encoders only (no HW fallback). Used for burn-in export where frames are CPU YUV420P.
pub fn encoder_candidates_software_only(codec: &VideoCodec) -> Vec<&'static str> {
    encoder_candidates(codec)
        .into_iter()
        .filter(|name| !is_hardware_encoder(name))
        .filter(|name| ffmpeg_next::encoder::find_by_name(name).is_some())
        .collect()
}

/// Burn-in composites CPU YUV420P then encodes. Prefer libx264/libx265 when linked; on mobile
/// FFmpeg builds that only ship MediaCodec / VideoToolbox, use those with YUV420P input.
pub fn encoder_candidates_burn_in(codec: &VideoCodec) -> Vec<&'static str> {
    let sw = encoder_candidates_software_only(codec);
    if !sw.is_empty() {
        return sw;
    }
    if matches!(std::env::consts::OS, "android" | "ios") {
        let hw: Vec<&str> = encoder_candidates(codec)
            .into_iter()
            .filter(|n| is_hardware_encoder(n))
            .filter(|n| ffmpeg_next::encoder::find_by_name(n).is_some())
            .collect();
        if !hw.is_empty() {
            log::warn!(
                "burn-in export: no software encoder for {codec:?} in this FFmpeg build; \
                 using hardware encoder with CPU YUV420P overlay composite"
            );
            return hw;
        }
    }
    sw
}

pub fn encoder_candidates_with_hw(codec: &VideoCodec, prefer_hardware: bool) -> Vec<&'static str> {
    let mut list: Vec<&str> = encoder_candidates(codec)
        .into_iter()
        .filter(|name| ffmpeg_next::encoder::find_by_name(name).is_some())
        .collect();

    if prefer_hardware {
        let hw: Vec<&str> = list
            .iter()
            .copied()
            .filter(|n| is_hardware_encoder(n))
            .collect();
        let sw: Vec<&str> = list
            .iter()
            .copied()
            .filter(|n| !is_hardware_encoder(n))
            .collect();
        hw.into_iter().chain(sw).collect()
    } else {
        list.retain(|n| !is_hardware_encoder(n));
        if list.is_empty() {
            // LGPL mobile builds often ship HW encoders only (VideoToolbox / MediaCodec).
            log::warn!(
                "no software encoder for {codec:?} in this FFmpeg build; falling back to hardware"
            );
            list = encoder_candidates(codec)
                .into_iter()
                .filter(|name| ffmpeg_next::encoder::find_by_name(name).is_some())
                .collect();
        }
        list
    }
}

pub fn is_hardware_encoder(name: &str) -> bool {
    matches!(
        name,
        "h264_mediacodec"
            | "hevc_mediacodec"
            | "h264_videotoolbox"
            | "hevc_videotoolbox"
            | "h264_vaapi"
            | "hevc_vaapi"
            | "h264_nvenc"
            | "hevc_nvenc"
            | "h264_qsv"
            | "hevc_qsv"
    )
}

pub fn select_encoder(codec: &VideoCodec, prefer_hardware: bool) -> Result<EncoderSelection> {
    for name in encoder_candidates_with_hw(codec, prefer_hardware) {
        if ffmpeg_next::encoder::find_by_name(name).is_some() {
            return Ok(EncoderSelection {
                name: name.to_string(),
                is_hardware: is_hardware_encoder(name),
            });
        }
    }

    Err(VideoProcessorError::UnsupportedCodec(format!(
        "no encoder available for {codec:?}"
    )))
}

pub fn software_encoder(codec: &VideoCodec) -> &'static str {
    match codec {
        VideoCodec::H264 => "libx264",
        VideoCodec::Hevc => "libx265",
    }
}

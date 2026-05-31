//! Detect Dolby Vision in a video stream (iPhone HEVC preview must use software decode).

use ffmpeg_next::codec::Id;
use ffmpeg_next::codec::Parameters;

const DV_FOURCCS: &[&str] = &["dvhe", "dvh1", "dvav", "dav1", "dovi"];

/// True when the stream likely carries Dolby Vision (HW VideoToolbox seek is unreliable).
pub fn stream_has_dolby_vision(params: &Parameters, input_path: Option<&str>) -> bool {
    if extradata_signals_dolby_vision(params) {
        return true;
    }
    if codec_tag_signals_dolby_vision(params) {
        return true;
    }
    if let Some(path) = input_path {
        if iphone_mov_hevc_heuristic(params, path) {
            return true;
        }
    }
    false
}

fn hw_preview_enabled() -> bool {
    crate::ffmpeg::hw_decode::enabled()
        && !matches!(
            std::env::var("VFP_DISABLE_HW_PREVIEW").as_deref(),
            Ok("1") | Ok("true") | Ok("yes")
        )
}

/// Whether Apple HW preview decode should be used for this stream.
pub fn should_use_hw_preview(prefer_hw: bool, params: &Parameters, input_path: &str) -> bool {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        prefer_hw
            && hw_preview_enabled()
            && !stream_has_dolby_vision(params, Some(input_path))
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = (prefer_hw, params, input_path);
        false
    }
}

fn extradata_signals_dolby_vision(params: &Parameters) -> bool {
    unsafe {
        let par = params.as_ptr();
        if par.is_null() || (*par).extradata_size <= 0 || (*par).extradata.is_null() {
            return false;
        }
        let data = std::slice::from_raw_parts((*par).extradata, (*par).extradata_size as usize);
        bytes_contain_dv_marker(data)
    }
}

fn codec_tag_signals_dolby_vision(params: &Parameters) -> bool {
    unsafe {
        let par = params.as_ptr();
        if par.is_null() {
            return false;
        }
        let tag = (*par).codec_tag;
        if tag == 0 {
            return false;
        }
        let mut buf = [0u8; 4];
        buf[0] = (tag & 0xff) as u8;
        buf[1] = ((tag >> 8) & 0xff) as u8;
        buf[2] = ((tag >> 16) & 0xff) as u8;
        buf[3] = ((tag >> 24) & 0xff) as u8;
        let fourcc = std::str::from_utf8(&buf).unwrap_or("");
        DV_FOURCCS.iter().any(|m| fourcc.eq_ignore_ascii_case(m))
    }
}

/// iPhone Photos exports: HEVC in `.mov` / `.m4v` (HDR / Dolby Vision) — unreliable for VT seek.
fn iphone_mov_hevc_heuristic(params: &Parameters, input_path: &str) -> bool {
    let lower = input_path.to_ascii_lowercase();
    if !(lower.ends_with(".mov") || lower.ends_with(".m4v")) {
        return false;
    }
    params.id() == Id::HEVC
}

/// iPhone HEVC / DV: software decode with session seek; full demuxer reopen only on decode errors.
pub fn preview_needs_clean_seek(params: &Parameters, input_path: &str) -> bool {
    stream_has_dolby_vision(params, Some(input_path)) || iphone_mov_hevc_heuristic(params, input_path)
}

/// Probe-time hint for Dart: use persistent session + RGBA (not VT pixel-buffer scrub).
pub fn prefer_software_preview(params: &Parameters, input_path: &str) -> bool {
    if preview_needs_clean_seek(params, input_path) {
        return true;
    }
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        // HEVC in MP4/MOV often breaks VT backward-seek; H.264 is fine with VT.
        if params.id() == Id::HEVC {
            return true;
        }
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = input_path;
    }
    false
}

fn bytes_contain_dv_marker(data: &[u8]) -> bool {
    const MARKERS: [&[u8]; 6] = [
        b"dvhe",
        b"dvh1",
        b"dvav",
        b"dovi",
        b"DOVI",
        b"Dovi",
    ];
    MARKERS
        .iter()
        .any(|m| data.windows(m.len()).any(|w| w == *m))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dv_marker_scan() {
        let data = b"prefix dvhe suffix";
        assert!(bytes_contain_dv_marker(data));
        assert!(!bytes_contain_dv_marker(b"plain hevc"));
    }
}

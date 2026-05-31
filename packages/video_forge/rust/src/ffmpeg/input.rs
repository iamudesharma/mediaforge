use std::path::{Path, PathBuf};

use ffmpeg_next::format::{self, context::Input};
use ffmpeg_next::Dictionary;

use crate::error::{Result, VideoProcessorError};

const USER_AGENT: &str =
    "Mozilla/5.0 (compatible; video_forge_kit/1.0; +https://github.com)";

/// True when [input] is a remote URL FFmpeg can open (HTTP, HTTPS, RTMP, RTSP, FTP).
pub fn is_remote_input(input: &str) -> bool {
    let trimmed = input.trim();
    let lower = trimmed.to_ascii_lowercase();
    lower.starts_with("http://")
        || lower.starts_with("https://")
        || lower.starts_with("rtmp://")
        || lower.starts_with("rtsp://")
        || lower.starts_with("ftp://")
}

/// Prefer HTTPS for hosts that commonly redirect or block plain HTTP clients.
pub fn normalize_remote_input(input: &str) -> String {
    let trimmed = input.trim();
    if !trimmed.starts_with("http://") {
        return trimmed.to_string();
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower.contains("googleapis.com")
        || lower.contains("googleusercontent.com")
        || lower.contains("gstatic.com")
    {
        return trimmed.replacen("http://", "https://", 1);
    }
    trimmed.to_string()
}

/// Validates that a local file exists or the value is a supported remote URL.
pub fn ensure_input_accessible(input: &str) -> Result<()> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err(VideoProcessorError::InvalidInput("empty input path".into()));
    }
    if is_remote_input(trimmed) {
        return Ok(());
    }
    let path = Path::new(trimmed);
    if path.exists() {
        Ok(())
    } else {
        Err(VideoProcessorError::FileNotFound(trimmed.to_string()))
    }
}

/// Open a local path or remote URL with FFmpeg (HTTP options applied for network inputs).
///
/// For local MOV/MP4 files, sets `analyzeduration` and `probesize` to handle
/// complex containers (e.g. iPhone Dolby Vision HEVC with `apac` audio) that
/// need deeper probing before codec parameters are resolved.
pub fn open_input(input: &str) -> Result<Input> {
    if is_remote_input(input) {
        let url = normalize_remote_input(input);
        let dict = remote_input_dictionary();
        format::input_with_dictionary(&url, dict)
            .map_err(crate::ffmpeg::map_ffmpeg_error)
    } else {
        let dict = local_probe_dictionary(input);
        format::input_with_dictionary(input, dict)
            .map_err(crate::ffmpeg::map_ffmpeg_error)
    }
}

/// Faster open for video-only preview/scrub (skips probing unknown iPhone `apac` audio).
pub fn open_input_for_preview(input: &str) -> Result<Input> {
    if is_remote_input(input) {
        return open_input(input);
    }
    let mut dict = preview_probe_dictionary(input);
    dict.set("an", "1");
    format::input_with_dictionary(input, dict).map_err(crate::ffmpeg::map_ffmpeg_error)
}

/// Minimal probe for preview — full [local_probe_dictionary] is for metadata/export.
fn preview_probe_dictionary(input: &str) -> Dictionary<'static> {
    let mut dict = Dictionary::new();
    let lower = input.to_ascii_lowercase();
    if lower.ends_with(".mov") || lower.ends_with(".mp4") || lower.ends_with(".m4v") {
        dict.set("analyzeduration", "500000");
        dict.set("probesize", "1000000");
    }
    dict
}

/// Extra probe options for local files that commonly confuse FFmpeg probing.
///
/// iPhone MOV files with Dolby Vision HEVC + Apple spatial audio (`apac`) often
/// trigger "Could not find codec parameters for stream 2" because the default
/// probe size / analysis duration is insufficient for the auxiliary audio track.
fn local_probe_dictionary(input: &str) -> Dictionary<'static> {
    let mut dict = Dictionary::new();
    let lower = input.to_ascii_lowercase();
    if lower.ends_with(".mov") || lower.ends_with(".mp4") || lower.ends_with(".m4v") {
        dict.set("analyzeduration", "5000000");
        dict.set("probesize", "20000000");
    }
    dict
}

fn remote_input_dictionary() -> Dictionary<'static> {
    let mut dict = Dictionary::new();
    dict.set("user_agent", USER_AGENT);
    dict.set("reconnect", "1");
    dict.set("reconnect_streamed", "1");
    dict.set("reconnect_delay_max", "5");
    dict.set("multiple_requests", "1");
    dict.set("rw_timeout", "15000000"); // 15s microseconds
    dict
}

/// Safe file stem for output naming (local path or URL last segment).
pub fn output_stem_from_input(input: &str) -> String {
    let trimmed = input.trim();
    let name = if is_remote_input(trimmed) {
        let without_query = trimmed.split('?').next().unwrap_or(trimmed);
        without_query
            .rsplit('/')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or("remote_video")
    } else {
        Path::new(trimmed)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("output")
    };

    let stem = Path::new(name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(name);

    stem.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

/// Default output path next to a local file, or under [output_dir] for remote inputs.
pub fn default_output_in_dir(
    input: &str,
    output_dir: &Path,
    suffix: &str,
    extension: &str,
) -> PathBuf {
    let stem = output_stem_from_input(input);
    output_dir.join(format!("{stem}{suffix}.{extension}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_remote_urls() {
        assert!(is_remote_input("https://example.com/v.mp4"));
        assert!(is_remote_input("http://cdn.test/video.mov?token=1"));
        assert!(!is_remote_input("/tmp/local.mp4"));
    }

    #[test]
    fn upgrades_google_http_to_https() {
        assert_eq!(
            normalize_remote_input(
                "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/a.mp4"
            ),
            "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/a.mp4"
        );
    }

    #[test]
    fn stem_from_url() {
        assert_eq!(
            output_stem_from_input("https://cdn.example.com/clips/my_video.mp4?sig=abc"),
            "my_video"
        );
    }
}

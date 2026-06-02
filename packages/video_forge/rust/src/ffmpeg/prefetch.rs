//! Download remote inputs to a local file via FFmpeg stream copy (no re-encode).

use std::path::Path;

use ffmpeg_next::codec::Id;
use ffmpeg_next::format;
use ffmpeg_next::media;
use ffmpeg_next::util::rational::Rational;
use uuid::Uuid;

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::{ensure_ffmpeg_initialized, is_remote_input, map_ffmpeg_error, open_input};

/// Stream-copy a remote URL to `{dest_dir}/{uuid}_prefetch.mp4`.
pub fn prefetch_remote_input(url: &str, dest_dir: &Path) -> Result<String> {
    ensure_ffmpeg_initialized()?;
    let trimmed = url.trim();
    if trimmed.is_empty() {
        return Err(VideoForgeError::InvalidInput("empty URL".into()));
    }
    if !is_remote_input(trimmed) {
        return Err(VideoForgeError::InvalidInput(
            "prefetch_remote_input requires an http(s) or streaming URL".into(),
        ));
    }

    std::fs::create_dir_all(dest_dir).map_err(|e| VideoForgeError::IoError(e.to_string()))?;

    let dest = dest_dir.join(format!("{}_prefetch.mp4", Uuid::new_v4()));
    if dest.exists() {
        let _ = std::fs::remove_file(&dest);
    }

    remux_stream_copy(trimmed, &dest)?;

    Ok(dest.to_string_lossy().into_owned())
}

/// PR #4: download a byte range of a remote URL to a local file.
///
/// Currently performs a **full** stream copy of the resource and
/// records the requested `[start_bytes, end_bytes]` bounds in the
/// destination filename. This is intentional: a proper byte-range
/// HTTP `Range` request requires either a custom `AVIO` callback
/// (which ffmpeg-next does not yet expose) or a HEAD-then-partial
/// fetch via `reqwest` (which would duplicate FFmpeg's HTTP stack).
///
/// What this helper *does* buy you today:
/// - Validates `start_bytes <= end_bytes` and the URL is remote.
/// - Records the requested bounds in the destination filename so a
///   follow-up cache layer can dedupe.
/// - Logs the bounds so you can grep for them in production.
///
/// What it does *not* yet do:
/// - Partial byte fetch (Range header).
/// - Moov-aware concatenation (joining head + tail prefetches into
///   a single input).
///
/// Until the follow-up lands, callers that just want the asset
/// locally should call [prefetch_remote_input] (full stream copy,
/// no Range negotiation overhead).
pub fn prefetch_remote_input_range(
    url: &str,
    start_bytes: u64,
    end_bytes: u64,
    dest_dir: &Path,
) -> Result<String> {
    ensure_ffmpeg_initialized()?;
    let trimmed = url.trim();
    if trimmed.is_empty() {
        return Err(VideoForgeError::InvalidInput("empty URL".into()));
    }
    if !is_remote_input(trimmed) {
        return Err(VideoForgeError::InvalidInput(
            "prefetch_remote_input_range requires an http(s) or streaming URL".into(),
        ));
    }
    if end_bytes < start_bytes {
        return Err(VideoForgeError::InvalidInput(format!(
            "prefetch_remote_input_range: end_bytes ({end_bytes}) < start_bytes ({start_bytes})"
        )));
    }

    std::fs::create_dir_all(dest_dir).map_err(|e| VideoForgeError::IoError(e.to_string()))?;
    let dest = dest_dir.join(format!(
        "{}_prefetch_range_{}_{}.mp4",
        Uuid::new_v4(),
        start_bytes,
        end_bytes
    ));
    if dest.exists() {
        let _ = std::fs::remove_file(&dest);
    }

    // Placeholder: fall back to the full stream copy. Once the
    // byte-range AVIO shim lands, this becomes a true Range fetch.
    log::info!(
        "[Prefetch] range {start_bytes}-{end_bytes} for {trimmed} — falling back to full stream copy"
    );
    remux_stream_copy(trimmed, &dest)?;
    Ok(dest.to_string_lossy().into_owned())
}

fn remux_stream_copy(input: &str, output: &Path) -> Result<()> {
    let mut ictx = open_input(input)?;
    let mut octx = format::output(output).map_err(map_ffmpeg_error)?;

    let nb_streams = ictx.nb_streams() as usize;
    let mut stream_mapping = vec![-1isize; nb_streams];
    let mut ist_time_bases = vec![Rational(0, 1); nb_streams];
    let mut ost_time_bases = vec![Rational(0, 1); nb_streams];
    let mut ost_index = 0usize;

    let best_video = ictx.streams().best(media::Type::Video).map(|s| s.index());
    let best_audio = ictx.streams().best(media::Type::Audio).map(|s| s.index());

    for (ist_index, ist) in ictx.streams().enumerate() {
        let medium = ist.parameters().medium();
        let include = match medium {
            media::Type::Video => best_video == Some(ist_index),
            media::Type::Audio => best_audio == Some(ist_index),
            _ => false,
        };
        if !include {
            continue;
        }

        stream_mapping[ist_index] = ost_index as isize;
        ist_time_bases[ist_index] = ist.time_base();

        let mut ost = octx
            .add_stream(ffmpeg_next::encoder::find(Id::None))
            .map_err(map_ffmpeg_error)?;
        ost.set_parameters(ist.parameters());
        unsafe {
            (*ost.parameters().as_mut_ptr()).codec_tag = 0;
        }
        ost_index += 1;
    }

    if ost_index == 0 {
        return Err(VideoForgeError::InvalidInput(
            "remote input has no copyable video or audio stream".into(),
        ));
    }

    octx.write_header().map_err(map_ffmpeg_error)?;

    for (idx, _) in octx.streams().enumerate() {
        ost_time_bases[idx] = octx
            .stream(idx)
            .ok_or_else(|| {
                VideoForgeError::FfmpegError(format!("missing output stream {idx}"))
            })?
            .time_base();
    }

    for (stream, packet) in ictx.packets() {
        let ist_index = stream.index();
        let mapped = stream_mapping[ist_index];
        if mapped < 0 {
            continue;
        }
        let ost_time_base = ost_time_bases[mapped as usize];
        let mut pkt = packet;
        pkt.rescale_ts(ist_time_bases[ist_index], ost_time_base);
        pkt.set_position(-1);
        pkt.set_stream(mapped as usize);
        pkt.write_interleaved(&mut octx).map_err(map_ffmpeg_error)?;
    }

    octx.write_trailer().map_err(map_ffmpeg_error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_local_path() {
        let err = prefetch_remote_input("/tmp/x.mp4", Path::new("/tmp")).unwrap_err();
        assert!(matches!(err, VideoForgeError::InvalidInput(_)));
    }

    #[test]
    fn rejects_empty_url() {
        let err = prefetch_remote_input("", Path::new("/tmp")).unwrap_err();
        assert!(matches!(err, VideoForgeError::InvalidInput(_)));
    }

    #[test]
    fn range_rejects_local_path() {
        let err =
            prefetch_remote_input_range("/tmp/x.mp4", 0, 1024, Path::new("/tmp")).unwrap_err();
        assert!(matches!(err, VideoForgeError::InvalidInput(_)));
    }

    #[test]
    fn range_rejects_empty_url() {
        let err = prefetch_remote_input_range("", 0, 1024, Path::new("/tmp")).unwrap_err();
        assert!(matches!(err, VideoForgeError::InvalidInput(_)));
    }

    #[test]
    fn range_rejects_end_before_start() {
        let err = prefetch_remote_input_range(
            "https://example.com/v.mp4",
            1024,
            512,
            Path::new("/tmp"),
        )
        .unwrap_err();
        match err {
            VideoForgeError::InvalidInput(msg) => {
                assert!(msg.contains("end_bytes (512) < start_bytes (1024)"), "got: {msg}");
            }
            other => panic!("expected InvalidInput, got {other:?}"),
        }
    }
}

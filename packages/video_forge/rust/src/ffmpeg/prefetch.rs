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
}

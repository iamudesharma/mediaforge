//! Stream-copy concat of homogeneous MP4 segments (same codec/resolution).

use ffmpeg_next::codec::Id;
use ffmpeg_next::format::{self, context::Output};
use ffmpeg_next::Rational;

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::map_ffmpeg_error;
use crate::ffmpeg::open_input;

/// Concatenate [input_paths] into [output_path] using stream copy (no re-encode).
pub fn concat_video_files(input_paths: &[String], output_path: &str) -> Result<()> {
    if input_paths.is_empty() {
        return Err(VideoForgeError::InvalidInput(
            "concat_video_files: no inputs".into(),
        ));
    }
    if input_paths.len() == 1 {
        std::fs::copy(&input_paths[0], output_path).map_err(|e| {
            VideoForgeError::IoError(format!("concat copy single segment: {e}"))
        })?;
        return Ok(());
    }

    log::info!(
        "[concat] joining {} segment(s) → {}",
        input_paths.len(),
        output_path
    );

    let mut octx: Output = format::output(output_path).map_err(map_ffmpeg_error)?;
    let mut nb_streams = 0usize;
    let mut ist_time_bases: Vec<Rational> = Vec::new();
    let mut ost_time_bases: Vec<Rational> = Vec::new();
    let mut pts_offset: Vec<i64> = Vec::new();
    let mut last_end: Vec<i64> = Vec::new();

    for (file_idx, path) in input_paths.iter().enumerate() {
        let mut ictx = open_input(path)?;
        let file_streams = ictx.nb_streams() as usize;

        if file_idx == 0 {
            nb_streams = file_streams;
            ist_time_bases = vec![Rational(0, 1); nb_streams];
            pts_offset = vec![0i64; nb_streams];
            last_end = vec![0i64; nb_streams];

            for (ist_index, ist) in ictx.streams().enumerate() {
                ist_time_bases[ist_index] = ist.time_base();
                let mut ost = octx
                    .add_stream(ffmpeg_next::encoder::find(Id::None))
                    .map_err(map_ffmpeg_error)?;
                ost.set_parameters(ist.parameters());
                unsafe {
                    (*ost.parameters().as_mut_ptr()).codec_tag = 0;
                }
            }
            octx.write_header().map_err(map_ffmpeg_error)?;
            for idx in 0..nb_streams {
                ost_time_bases.push(
                    octx.stream(idx)
                        .ok_or_else(|| {
                            VideoForgeError::FfmpegError(format!("missing output stream {idx}"))
                        })?
                        .time_base(),
                );
            }
        } else if file_streams != nb_streams {
            return Err(VideoForgeError::InvalidInput(format!(
                "concat segment {file_idx} has {file_streams} streams, expected {nb_streams}"
            )));
        } else {
            for si in 0..nb_streams {
                pts_offset[si] = last_end[si];
            }
        }

        let file_ist_tbs: Vec<Rational> = ictx.streams().map(|s| s.time_base()).collect();

        for (stream, packet) in ictx.packets() {
            let si = stream.index();
            if si >= nb_streams {
                continue;
            }
            let mut pkt = packet;
            let in_tb = file_ist_tbs.get(si).copied().unwrap_or(ist_time_bases[si]);
            let ost_tb = ost_time_bases[si];
            let off = pts_offset[si];

            if let Some(pts) = pkt.pts() {
                pkt.set_pts(Some(pts.saturating_add(off)));
            }
            if let Some(dts) = pkt.dts() {
                pkt.set_dts(Some(dts.saturating_add(off)));
            }
            if let Some(pts) = pkt.pts() {
                let dur = pkt.duration().max(1);
                last_end[si] = pts.saturating_add(dur);
            }

            pkt.rescale_ts(in_tb, ost_tb);
            pkt.set_position(-1);
            pkt.set_stream(si);
            pkt.write_interleaved(&mut octx).map_err(map_ffmpeg_error)?;
        }
    }

    octx.write_trailer().map_err(map_ffmpeg_error)?;
    log::info!("[concat] done → {}", output_path);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_input_list() {
        let err = concat_video_files(&[], "/tmp/out.mp4").unwrap_err();
        assert!(matches!(err, VideoForgeError::InvalidInput(_)));
    }
}

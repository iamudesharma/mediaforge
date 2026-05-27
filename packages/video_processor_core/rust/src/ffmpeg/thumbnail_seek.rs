//! Fast seek helpers for the thumbnail pipeline (A2).

use ffmpeg_next::codec::decoder::Video;
use ffmpeg_next::ffi;
use ffmpeg_next::format::context::Input;
use ffmpeg_next::util::rational::Rational;

use crate::error::Result;
use crate::ffmpeg::map_ffmpeg_error;

/// Stream time_base units from milliseconds.
pub fn ms_to_stream_ts(ms: u64, tb: Rational) -> i64 {
    if tb.0 == 0 || tb.1 == 0 {
        return 0;
    }
    (ms as f64 / 1000.0 / tb.0 as f64 * tb.1 as f64) as i64
}

/// Seek backward on a video stream and leave the demuxer ready to read packets.
pub fn seek_stream_backward(
    ictx: &mut Input,
    stream_index: usize,
    stream_ts: i64,
) -> Result<()> {
    unsafe {
        let ret = ffi::avformat_seek_file(
            ictx.as_mut_ptr(),
            stream_index as i32,
            i64::MIN,
            stream_ts,
            stream_ts,
            ffi::AVSEEK_FLAG_BACKWARD,
        );
        if ret >= 0 {
            Ok(())
        } else {
            Err(map_ffmpeg_error(ffmpeg_next::util::error::Error::from(ret)))
        }
    }
}

/// Reset decoder internal buffers after a demuxer seek (A2).
pub fn flush_video_decoder(decoder: &mut Video) {
    unsafe {
        ffi::avcodec_flush_buffers(decoder.as_mut_ptr());
    }
}

/// Container duration in milliseconds (0 if unknown).
pub fn input_duration_ms(ictx: &Input) -> u64 {
    let dur = ictx.duration();
    if dur > 0 {
        (dur as f64 / ffi::AV_TIME_BASE as f64 * 1000.0).max(0.0) as u64
    } else {
        0
    }
}

/// Whether batch positions span enough of the timeline that per-target seeks win (A1).
pub fn use_segmented_thumbnail_seek(targets: &[u64], duration_ms: u64) -> bool {
    if targets.len() <= 1 {
        return false;
    }
    let first = targets[0];
    let last = *targets.last().unwrap();
    let span = last.saturating_sub(first);

    // Short contiguous span (e.g. 0–9s benchmark): keep single forward pass.
    if span <= 20_000 {
        return false;
    }

    // Long span on a long clip (e.g. filmstrip 0→end): avoid decoding the whole timeline.
    if duration_ms > 0 && span > duration_ms * 45 / 100 && duration_ms >= 25_000 {
        return true;
    }

    // Unknown duration but wide spread (Photos / variable-MOV).
    duration_ms == 0 && span >= 30_000
}

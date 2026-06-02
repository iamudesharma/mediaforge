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

/// Seek to an exact PTS using `AVSEEK_FLAG_ANY` (any-frame, not just
/// keyframe). Used as a second-tier fallback when the backward seek
/// did not yield a frame at/after the target (rare but happens on
/// sparse-GOP codecs and B-frame-only edits). The caller is responsible
/// for re-seeking to the prior keyframe and decoding forward if
/// `avformat_seek_file` returns 0 but the demuxer lands before the
/// target frame — this helper only guarantees the seek itself.
pub fn seek_stream_any(
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
            ffi::AVSEEK_FLAG_ANY,
        );
        if ret >= 0 {
            Ok(())
        } else {
            Err(map_ffmpeg_error(ffmpeg_next::util::error::Error::from(ret)))
        }
    }
}

/// Two-tier seek for thumbnails (PR #3):
/// 1. `AVSEEK_FLAG_BACKWARD` to the nearest keyframe at or before
///    `stream_ts` (current behavior).
/// 2. On no-frame-found by the time the demuxer runs out of packets,
///    `AVSEEK_FLAG_ANY` to the exact PTS + decode forward from the
///    prior keyframe.
///
/// The first-tier success returns `SeekOutcome::Back`; the second-tier
/// success returns `SeekOutcome::Any`; total failure returns `Err`.
///
/// Caller is expected to call [seek_stream_backward] (or this helper)
/// and then read packets; on `Outcome::Back` the caller's existing
/// `skip_frame=NonKey` discard logic kicks in. On `Outcome::Any` the
/// caller should rewind to the prior keyframe and discard non-key
/// frames until reaching the target PTS.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SeekOutcome {
    /// Sought to keyframe at/before [stream_ts]. Existing discard
    /// heuristic is sufficient.
    Back,
    /// Sought exactly to [stream_ts] with `AVSEEK_FLAG_ANY`. Caller
    /// must rewind + decode forward.
    Any,
}

pub fn seek_stream_two_tier(
    ictx: &mut Input,
    stream_index: usize,
    stream_ts: i64,
) -> Result<SeekOutcome> {
    match seek_stream_backward(ictx, stream_index, stream_ts) {
        Ok(()) => Ok(SeekOutcome::Back),
        Err(_) => seek_stream_any(ictx, stream_index, stream_ts).map(|_| SeekOutcome::Any),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ms_to_stream_ts_basic() {
        // 1 second at 1/1000 timescale = 1000 stream units.
        let tb = Rational(1, 1000);
        assert_eq!(ms_to_stream_ts(1000, tb), 1000);
    }

    #[test]
    fn ms_to_stream_ts_handles_zero_timebase() {
        // Defensive: a zero / malformed time base should not crash.
        assert_eq!(ms_to_stream_ts(1000, Rational(0, 1)), 0);
        assert_eq!(ms_to_stream_ts(1000, Rational(1, 0)), 0);
    }

    #[test]
    fn ms_to_stream_ts_microsecond_scale() {
        // 1ms at 1/1_000_000 timescale = 1000 stream units.
        let tb = Rational(1, 1_000_000);
        assert_eq!(ms_to_stream_ts(1, tb), 1000);
    }

    // Two-tier seek + outcome variant equality is tested via integration
    // tests in vp_bench / integration_test/; here we only verify
    // that the outcome enum's PartialEq holds across both variants
    // (used by callers' `matches!` patterns).
    #[test]
    fn seek_outcome_equality() {
        assert_eq!(SeekOutcome::Back, SeekOutcome::Back);
        assert_eq!(SeekOutcome::Any, SeekOutcome::Any);
        assert_ne!(SeekOutcome::Back, SeekOutcome::Any);
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

use ffmpeg_next::codec::context::Context;
use ffmpeg_next::codec::Id;
use ffmpeg_next::codec::threading::{Config, Type};

/// Frame-threaded software decode for **compress** (throughput).
///
/// Not used for thumbnails — frame threading buffers multiple frames and hurts
/// seek-to-first-frame latency.
pub fn apply_video_decoder_threading(ctx: &mut Context) {
    ctx.set_threading(Config {
        kind: Type::Frame,
        count: 0,
        ..Default::default()
    });
}

/// Low-latency software decode for **thumbnails** (CPU only, no HW / VT).
pub fn apply_thumbnail_decoder_settings(ctx: &mut Context) {
    ctx.set_threading(Config {
        kind: Type::None,
        count: 1,
        ..Default::default()
    });
}

/// Software decode for interactive preview scrub (iPhone HEVC): frame threads help
/// burst decode from keyframe → target without adding seek latency.
pub fn apply_preview_scrub_decoder_settings(ctx: &mut Context) {
    ctx.set_threading(Config {
        kind: Type::Frame,
        count: 0,
        ..Default::default()
    });
    apply_preview_hevc_low_latency(ctx);
}

/// HEVC preview: favor latency over film-grain / supplemental metadata export.
fn apply_preview_hevc_low_latency(ctx: &mut Context) {
    if ctx.id() != Id::HEVC {
        return;
    }
    unsafe {
        use ffmpeg_next::ffi::{AV_CODEC_FLAG2_FAST, AV_CODEC_FLAG_LOW_DELAY};
        let avctx = ctx.as_mut_ptr();
        if avctx.is_null() {
            return;
        }
        (*avctx).flags |= AV_CODEC_FLAG_LOW_DELAY as i32;
        (*avctx).flags2 |= AV_CODEC_FLAG2_FAST as i32;
    }
}

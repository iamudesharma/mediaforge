use ffmpeg_next::codec::context::Context;
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

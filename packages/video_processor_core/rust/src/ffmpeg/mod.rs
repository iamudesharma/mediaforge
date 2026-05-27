pub mod decode;
pub mod hw;
pub mod hw_decode;
pub mod vt_link;
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub mod vt_pipeline;
pub mod init;
pub mod input;
pub mod interrupt;
pub mod thumbnail_seek;
pub mod large_file;
pub mod packet_pool;
pub mod prefetch;
pub mod probe_cache;

pub use decode::{apply_thumbnail_decoder_settings, apply_video_decoder_threading};
pub use hw::{EncoderSelection, select_encoder};
pub use hw_decode::{enabled as hw_decode_enabled, open_video_decoder, HwFrameTransfer};
pub use vt_link::VtLinkMode;
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub use vt_pipeline::VtScaler;
pub use init::{ensure_ffmpeg_initialized, map_ffmpeg_error};
pub use input::{
    ensure_input_accessible, is_remote_input, normalize_remote_input, open_input,
    output_stem_from_input,
};
pub use packet_pool::PacketPool;
pub use prefetch::prefetch_remote_input;
pub use probe_cache::{get as probe_cache_get, insert as probe_cache_insert};
pub use interrupt::InterruptContext;
pub use thumbnail_seek::{
    flush_video_decoder, input_duration_ms, ms_to_stream_ts, seek_stream_backward,
    use_segmented_thumbnail_seek,
};

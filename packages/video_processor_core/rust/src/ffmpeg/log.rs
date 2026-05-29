//! FFmpeg log noise control for interactive preview (scrub/playback).
//!
//! iPhone MOV preview triggers benign `apac` probe warnings and Dolby Vision RPU
//! info lines. Set `VFP_VERBOSE_FFMPEG=1` to restore full libav logs.

use std::sync::atomic::{AtomicI32, Ordering};

const AV_LOG_ERROR: i32 = 32;

pub fn verbose_ffmpeg() -> bool {
    matches!(
        std::env::var("VFP_VERBOSE_FFMPEG").as_deref(),
        Ok("1") | Ok("true") | Ok("yes")
    )
}

/// RAII: raise FFmpeg log threshold for a preview decode scope (restores on drop).
pub struct PreviewLogScope {
    prev: i32,
}

impl PreviewLogScope {
    pub fn quiet() -> Self {
        unsafe {
            let prev = ffmpeg_next::ffi::av_log_get_level();
            if !verbose_ffmpeg() {
                ffmpeg_next::ffi::av_log_set_level(AV_LOG_ERROR);
            }
            Self { prev }
        }
    }
}

impl Drop for PreviewLogScope {
    fn drop(&mut self) {
        if !verbose_ffmpeg() {
            unsafe {
                ffmpeg_next::ffi::av_log_set_level(self.prev);
            }
        }
    }
}

static WORKER_PREV: AtomicI32 = AtomicI32::new(i32::MIN);

/// Dedicated preview worker: keep libav quiet for the thread lifetime.
pub fn preview_worker_thread_enter() {
    if verbose_ffmpeg() {
        return;
    }
    unsafe {
        let prev = ffmpeg_next::ffi::av_log_get_level();
        WORKER_PREV.store(prev, Ordering::SeqCst);
        ffmpeg_next::ffi::av_log_set_level(AV_LOG_ERROR);
    }
}

pub fn preview_worker_thread_exit() {
    if verbose_ffmpeg() {
        return;
    }
    let prev = WORKER_PREV.load(Ordering::SeqCst);
    if prev != i32::MIN {
        unsafe {
            ffmpeg_next::ffi::av_log_set_level(prev);
        }
    }
}

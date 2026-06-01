//! Phase 2: paced frame presentation (~30 fps) decoupled from Dart's variable tick rate.
//! Phase 1: hard resync — seek demuxer to audio clock when presented video lags by several seconds.

use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use parking_lot::Mutex;

use crate::api::runtime::{
    AudioFrame, FrameQueue, MediaVideoFrame, PacketQueue, PlaybackClock, PlaybackState,
};

macro_rules! presenter_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*);
    };
}

/// Audio ahead of last **presented** video PTS — trigger demuxer seek (not packet drop only).
pub const HARD_RESYNC_DRIFT_MS: u64 = 2000;
/// Minimum time between automatic hard resyncs.
pub const HARD_RESYNC_COOLDOWN_MS: u64 = 3000;
/// Suppress hard resync right after UI/demuxer seek while queues refill.
pub const HARD_RESYNC_SEEK_GRACE_MS: u64 = 2000;
/// Presenter tick interval (~60 fps UI cadence; decode may be 30fps).
pub const PRESENTER_INTERVAL_MS: u64 = 16;

/// Shared seek signalling used by UI seek, hard resync, and the demuxer thread.
pub struct SeekController {
    seek_target_ms: Arc<AtomicI64>,
    seek_was_playing: Arc<AtomicBool>,
    demuxer_active: Arc<AtomicBool>,
    clock: Arc<PlaybackClock>,
    audio_clock_ms: Arc<AtomicU64>,
    last_seek_at: Mutex<Option<Instant>>,
    video_packet_queue: Arc<PacketQueue>,
    audio_packet_queue: Arc<PacketQueue>,
    video_frame_queue: Arc<FrameQueue<MediaVideoFrame>>,
    audio_frame_queue: Arc<FrameQueue<AudioFrame>>,
    pub seek_generation: Arc<AtomicU64>,
    display_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
    frozen_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
}

impl SeekController {
    pub fn new(
        seek_target_ms: Arc<AtomicI64>,
        seek_was_playing: Arc<AtomicBool>,
        demuxer_active: Arc<AtomicBool>,
        clock: Arc<PlaybackClock>,
        audio_clock_ms: Arc<AtomicU64>,
        video_packet_queue: Arc<PacketQueue>,
        audio_packet_queue: Arc<PacketQueue>,
        video_frame_queue: Arc<FrameQueue<MediaVideoFrame>>,
        audio_frame_queue: Arc<FrameQueue<AudioFrame>>,
        seek_generation: Arc<AtomicU64>,
        display_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
        frozen_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
    ) -> Self {
        Self {
            seek_target_ms,
            seek_was_playing,
            demuxer_active,
            clock,
            audio_clock_ms,
            last_seek_at: Mutex::new(None),
            video_packet_queue,
            audio_packet_queue,
            video_frame_queue,
            audio_frame_queue,
            seek_generation,
            display_frame,
            frozen_frame,
        }
    }

    pub fn request_seek(&self, time_ms: u64, reason: &str) {
        // Increment seek generation immediately
        let new_gen = self.seek_generation.fetch_add(1, Ordering::SeqCst) + 1;

        presenter_log!(
            "[SeekController] request_seek target_ms={} gen={} reason={} demuxer_active={}",
            time_ms,
            new_gen,
            reason,
            self.demuxer_active.load(Ordering::Relaxed)
        );

        *self.last_seek_at.lock() = Some(Instant::now());
        // Align audio clock immediately so hard resync / presenter do not use pre-seek PTS.
        self.audio_clock_ms.store(time_ms, Ordering::Relaxed);

        // Freeze the last presented frame
        let mut display = self.display_frame.lock();
        if let Some(frame) = display.as_ref() {
            let mut frozen = frame.clone();
            frozen.seek_generation = new_gen;
            *self.frozen_frame.lock() = Some(frozen);
            presenter_log!("[SeekController] Froze last good frame for seek gen={} pts={}ms", new_gen, frame.pts_ms);
        } else {
            *self.frozen_frame.lock() = None;
        }

        // Clear active presented frame (display queue)
        *display = None;

        if self.demuxer_active.load(Ordering::Relaxed) {
            let was_playing = self.clock.get_state() == PlaybackState::Playing;
            self.seek_was_playing
                .store(was_playing, Ordering::Relaxed);
            self.clock.seek(time_ms);
            self.seek_target_ms
                .store(time_ms as i64, Ordering::Release);
            self.video_frame_queue.flush_video();
            self.audio_frame_queue.flush();
            self.video_packet_queue.flush();
            self.audio_packet_queue.flush();
        } else {
            self.clock.seek(time_ms);
            self.video_packet_queue.flush();
            self.audio_packet_queue.flush();
            self.video_frame_queue.flush_video();
            self.audio_frame_queue.flush();
            self.clock.seek_complete(false, time_ms);
        }
    }
}

struct HardResyncState {
    last_resync_at: Mutex<Option<Instant>>,
}

impl HardResyncState {
    fn new() -> Self {
        Self {
            last_resync_at: Mutex::new(None),
        }
    }

    fn maybe_resync(
        &self,
        display_frame: &Arc<Mutex<Option<MediaVideoFrame>>>,
        seek: &SeekController,
        clock: &PlaybackClock,
        audio_clock_ms: &AtomicU64,
        video_frame_queue: &FrameQueue<MediaVideoFrame>,
    ) {
        if self.maybe_resync_precheck(seek, clock, audio_clock_ms, video_frame_queue) {
            display_frame.lock().take();
            self.finish_resync(seek, clock, audio_clock_ms, video_frame_queue);
        }
    }

    fn maybe_resync_precheck(
        &self,
        seek: &SeekController,
        clock: &PlaybackClock,
        audio_clock_ms: &AtomicU64,
        video_frame_queue: &FrameQueue<MediaVideoFrame>,
    ) -> bool {
        if clock.get_state() != PlaybackState::Playing {
            return false;
        }
        if clock.get_state() == PlaybackState::Seeking {
            return false;
        }
        if seek.seek_target_ms.load(Ordering::Acquire) >= 0 {
            return false;
        }
        if let Some(t) = *seek.last_seek_at.lock() {
            if t.elapsed() < Duration::from_millis(HARD_RESYNC_SEEK_GRACE_MS) {
                return false;
            }
        }
        let audio_ms = audio_clock_ms.load(Ordering::Relaxed);
        if audio_ms == 0 {
            return false;
        }
        let presented_ms = clock.get_last_presented_pts_ms();
        let decoded_ms = video_frame_queue.latest_pts();
        // Backward seek: stale presented PTS from before seek must not trigger forward resync.
        if presented_ms > audio_ms.saturating_add(500) {
            clock.reset_presented_pts_for_seek(audio_ms);
            return false;
        }
        if decoded_ms == 0 && presented_ms > audio_ms.saturating_add(HARD_RESYNC_DRIFT_MS) {
            clock.reset_presented_pts_for_seek(audio_ms);
            return false;
        }
        let drift = audio_ms
            .saturating_sub(presented_ms)
            .max(audio_ms.saturating_sub(decoded_ms));
        if drift < HARD_RESYNC_DRIFT_MS {
            return false;
        }
        let mut last = self.last_resync_at.lock();
        if let Some(t) = *last {
            if t.elapsed() < Duration::from_millis(HARD_RESYNC_COOLDOWN_MS) {
                return false;
            }
        }
        *last = Some(Instant::now());
        true
    }

    fn finish_resync(
        &self,
        seek: &SeekController,
        clock: &PlaybackClock,
        audio_clock_ms: &AtomicU64,
        video_frame_queue: &FrameQueue<MediaVideoFrame>,
    ) {
        let audio_ms = audio_clock_ms.load(Ordering::Relaxed);
        let presented_ms = clock.get_last_presented_pts_ms();
        let decoded_ms = video_frame_queue.latest_pts();
        let drift = audio_ms
            .saturating_sub(presented_ms)
            .max(audio_ms.saturating_sub(decoded_ms));
        presenter_log!(
            "[HardResync] drift={}ms audio={} presented={} decoded={} → seek demuxer to audio clock",
            drift,
            audio_ms,
            presented_ms,
            decoded_ms
        );
        seek.request_seek(audio_ms, "hard_resync");
    }
}

/// Paced presenter: selects at most one display frame per interval from the decode queue.
pub struct PresenterRuntime {
    is_running: Arc<AtomicBool>,
    thread_handle: Mutex<Option<thread::JoinHandle<()>>>,
    display_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
    hard_resync: Arc<HardResyncState>,
    pub(crate) frozen_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
}

impl PresenterRuntime {
    pub fn new() -> Self {
        Self {
            is_running: Arc::new(AtomicBool::new(false)),
            thread_handle: Mutex::new(None),
            display_frame: Arc::new(Mutex::new(None)),
            hard_resync: Arc::new(HardResyncState::new()),
            frozen_frame: Arc::new(Mutex::new(None)),
        }
    }

    pub fn take_display_frame(&self) -> Option<MediaVideoFrame> {
        self.display_frame.lock().take()
    }

    pub fn get_display_frame(&self) -> Arc<Mutex<Option<MediaVideoFrame>>> {
        self.display_frame.clone()
    }

    #[allow(dead_code)]
    pub fn clear_display_frame(&self) {
        self.display_frame.lock().take();
    }

    pub fn get_frozen_frame(&self) -> Option<MediaVideoFrame> {
        self.frozen_frame.lock().clone()
    }

    pub fn clear_frozen_frame(&self) {
        *self.frozen_frame.lock() = None;
    }

    pub fn start(
        &self,
        clock: Arc<PlaybackClock>,
        video_frame_queue: Arc<FrameQueue<MediaVideoFrame>>,
        audio_clock_ms: Arc<AtomicU64>,
        seek: Arc<SeekController>,
    ) {
        if self.is_running.swap(true, Ordering::SeqCst) {
            presenter_log!("[PresenterRuntime] Already running");
            return;
        }

        let is_running = self.is_running.clone();
        let display_frame = self.display_frame.clone();
        let hard_resync = self.hard_resync.clone();
        let interval = Duration::from_millis(PRESENTER_INTERVAL_MS);
        let frozen_frame = self.frozen_frame.clone();

        presenter_log!(
            "[PresenterRuntime] Starting paced presenter interval_ms={} (~{} Hz)",
            PRESENTER_INTERVAL_MS,
            1000 / PRESENTER_INTERVAL_MS.max(1)
        );

        let handle = thread::spawn(move || {
            let mut next_tick = Instant::now();
            let mut last_present_log = Instant::now() - Duration::from_secs(5);
            let mut last_gen = 0u64;

            // Frame pacing history tracking
            let mut last_presented_frame_pts: Option<u64> = None;
            let mut last_presented_frame_time: Option<Instant> = None;
            let mut pacing_interval_average_ms: Option<f64> = None;
            let mut pacing_drift_average_ms: Option<f64> = None;

            while is_running.load(Ordering::SeqCst) {
                let now = Instant::now();
                if now < next_tick {
                    thread::sleep(next_tick - now);
                }
                next_tick = Instant::now() + interval;

                let current_gen = seek.seek_generation.load(Ordering::Relaxed);
                if current_gen != last_gen {
                    presenter_log!("[PresenterRuntime] Invalidate presenter frame pacing history: gen={} -> {}", last_gen, current_gen);
                    last_gen = current_gen;
                    last_presented_frame_pts = None;
                    last_presented_frame_time = None;
                    pacing_interval_average_ms = None;
                    pacing_drift_average_ms = None;
                }

                let state = clock.get_state();
                if state != PlaybackState::Playing {
                    continue;
                }

                hard_resync.maybe_resync(
                    &display_frame,
                    seek.as_ref(),
                    clock.as_ref(),
                    &audio_clock_ms,
                    &video_frame_queue,
                );

                let media_ms = {
                    let audio_ms = audio_clock_ms.load(Ordering::Relaxed);
                    if audio_ms > 0 {
                        audio_ms
                    } else {
                        clock.get_media_time_ms()
                    }
                };

                if let Some(frame) = video_frame_queue.dequeue_best_for_time(media_ms) {
                    let pts = frame.pts_ms;
                    clock.advance_presented_pts(pts);
                    
                    // Update pacing history
                    let frame_time = Instant::now();
                    if let (Some(last_pts), Some(last_time)) = (last_presented_frame_pts, last_presented_frame_time) {
                        let pts_delta = pts.saturating_sub(last_pts) as f64;
                        let time_delta = frame_time.duration_since(last_time).as_millis() as f64;
                        
                        let prev_avg_int = pacing_interval_average_ms.unwrap_or(pts_delta);
                        pacing_interval_average_ms = Some(prev_avg_int * 0.9 + pts_delta * 0.1);
                        
                        let drift = (time_delta - pts_delta).abs();
                        let prev_avg_drift = pacing_drift_average_ms.unwrap_or(drift);
                        pacing_drift_average_ms = Some(prev_avg_drift * 0.9 + drift * 0.1);
                    }
                    last_presented_frame_pts = Some(pts);
                    last_presented_frame_time = Some(frame_time);

                    *display_frame.lock() = Some(frame);
                    *frozen_frame.lock() = None; // Reset frozen frame on new frame presentation

                    if last_present_log.elapsed() >= Duration::from_secs(2) {
                        presenter_log!(
                            "[PresenterRuntime] presented pts={}ms clock={}ms vq={} pacing_int={:?} pacing_drift={:?}",
                            pts,
                            media_ms,
                            video_frame_queue.len(),
                            pacing_interval_average_ms,
                            pacing_drift_average_ms
                        );
                        last_present_log = Instant::now();
                    }
                }
            }

            presenter_log!("[PresenterRuntime] Presenter thread exited");
        });

        *self.thread_handle.lock() = Some(handle);
    }

    pub fn stop(&self) {
        if !self.is_running.swap(false, Ordering::SeqCst) {
            return;
        }
        presenter_log!("[PresenterRuntime] Stopping");
        *self.display_frame.lock() = None;
        *self.frozen_frame.lock() = None;
        if let Some(handle) = self.thread_handle.lock().take() {
            let _ = handle.join();
        }
    }
}

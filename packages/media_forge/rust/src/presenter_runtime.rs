//! Frame-ready presentation pump: the decoder signals when a new presentable
//! frame is selected; the presenter waits efficiently (Condvar) until one of:
//! new frame ready / playback stops / seek generation changes / disposed.
//! No 60/120 Hz polling when there is no new frame. No presentation while
//! paused / completed / backgrounded / disposed.

use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use parking_lot::{Condvar, Mutex};

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
/// Kept for backward-compat telemetry; the pump itself is frame-ready
/// (event-driven) and does not poll at this rate when idle.
pub const PRESENTER_INTERVAL_MS: u64 = 16;
/// Max wait while playing without a new frame (one 30 fps interval).
const FRAME_READY_WAIT_PLAYING_MS: u64 = 33;
/// Max wait while paused/backgrounded (no presentation requested).
const FRAME_READY_WAIT_IDLE_MS: u64 = 200;
/// Require sustained starvation before freezing the clock. A brief gap
/// between decoder frames must remain invisible to the user.
const REBUFFER_ENTER_DELAY_MS: u64 = 750;
/// Require a larger recovery condition than the enter condition: two frames
/// must remain available for a short period before playback resumes.
const REBUFFER_RESUME_DELAY_MS: u64 = 350;
const REBUFFER_RESUME_FRAMES: usize = 2;

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
    frame_ready: Mutex<Option<Arc<(Mutex<u64>, Condvar)>>>,
}

impl SeekController {
    #[allow(clippy::too_many_arguments)]
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
            frame_ready: Mutex::new(None),
        }
    }

    pub fn set_frame_ready(&self, signal: Arc<(Mutex<u64>, Condvar)>) {
        *self.frame_ready.lock() = Some(signal);
    }

    fn notify_frame_ready(&self) {
        if let Some(sig) = self.frame_ready.lock().clone() {
            let lock = &sig.0;
            let cvar = &sig.1;
            let mut v = lock.lock();
            *v = v.wrapping_add(1);
            cvar.notify_all();
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
            let was_playing = matches!(
                self.clock.get_state(),
                PlaybackState::Playing | PlaybackState::Rebuffering
            );
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
        // Wake the frame-ready pump: generation changed (§5).
        self.notify_frame_ready();
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
        // A missing video frame is starvation, not an A/V synchronization
        // problem. Seeking here flushes packet/frame queues and causes a
        // localhost stream to issue a new Range read while it is still
        // waiting for the current piece. Keep the last frame and let the
        // existing demux/decode pipeline refill instead.
        if video_frame_queue.len() == 0 {
            presenter_log!(
                "[HardResync] suppressed during video starvation audio={}ms",
                audio_ms
            );
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

/// Frame-ready presenter: waits efficiently until a new frame is ready,
/// playback stops, seek generation changes, or disposal. Presents at most
/// one display frame per wake through the pixel_surface bridge. No
/// presentation while paused / completed / backgrounded / disposed.
pub struct PresenterRuntime {
    is_running: Arc<AtomicBool>,
    /// Suspended (backgrounded): pump parked, no bridge calls.
    is_suspended: Arc<AtomicBool>,
    thread_handle: Mutex<Option<thread::JoinHandle<()>>>,
    display_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
    hard_resync: Arc<HardResyncState>,
    pub(crate) frozen_frame: Arc<Mutex<Option<MediaVideoFrame>>>,
    frame_ready: Mutex<Option<Arc<(Mutex<u64>, Condvar)>>>,
}

impl PresenterRuntime {
    pub fn new() -> Self {
        Self {
            is_running: Arc::new(AtomicBool::new(false)),
            is_suspended: Arc::new(AtomicBool::new(false)),
            thread_handle: Mutex::new(None),
            display_frame: Arc::new(Mutex::new(None)),
            hard_resync: Arc::new(HardResyncState::new()),
            frozen_frame: Arc::new(Mutex::new(None)),
            frame_ready: Mutex::new(None),
        }
    }

    pub fn set_frame_ready(&self, signal: Arc<(Mutex<u64>, Condvar)>) {
        *self.frame_ready.lock() = Some(signal);
    }

    /// Lifecycle suspension (§13): park the pump, emit no bridge calls.
    pub fn suspend(&self) {
        self.is_suspended.store(true, Ordering::SeqCst);
        if let Some(sig) = self.frame_ready.lock().clone() {
            sig.1.notify_all();
        }
    }

    pub fn resume(&self) {
        self.is_suspended.store(false, Ordering::SeqCst);
        if let Some(sig) = self.frame_ready.lock().clone() {
            sig.1.notify_all();
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
        self.is_suspended.store(false, Ordering::SeqCst);

        let is_running = self.is_running.clone();
        let is_suspended = self.is_suspended.clone();
        let display_frame = self.display_frame.clone();
        let hard_resync = self.hard_resync.clone();
        let frozen_frame = self.frozen_frame.clone();
        let frame_ready = self.frame_ready.lock().clone();

        presenter_log!(
            "[PresenterRuntime] Starting frame-ready pump (event-driven, no vsync polling)"
        );

        let handle = thread::spawn(move || {
            let mut last_present_log = Instant::now() - Duration::from_secs(5);
            let mut last_gen = seek.seek_generation.load(Ordering::Relaxed);

            // Frame pacing history tracking
            let mut last_presented_frame_pts: Option<u64> = None;
            let mut last_presented_frame_time: Option<Instant> = None;
            let mut pacing_interval_average_ms: Option<f64> = None;
            let mut pacing_drift_average_ms: Option<f64> = None;
            let mut starvation_started: Option<Instant> = None;
            let mut recovery_ready_started: Option<Instant> = None;
            let mut observed_version: u64 = frame_ready
                .as_ref()
                .map(|sig| *sig.0.lock())
                .unwrap_or(0);

            while is_running.load(Ordering::SeqCst) {
                // §5/§13: never present while suspended; park efficiently.
                if is_suspended.load(Ordering::SeqCst) {
                    if let Some(sig) = frame_ready.as_ref() {
                        let lock = &sig.0;
                        let cvar = &sig.1;
                        let mut guard = lock.lock();
                        let _ = cvar.wait_for(&mut guard, Duration::from_millis(FRAME_READY_WAIT_IDLE_MS));
                        observed_version = *guard;
                    } else {
                        thread::sleep(Duration::from_millis(FRAME_READY_WAIT_IDLE_MS));
                    }
                    continue;
                }

                let current_gen = seek.seek_generation.load(Ordering::Relaxed);
                if current_gen != last_gen {
                    presenter_log!("[PresenterRuntime] Invalidate presenter frame pacing history: gen={} -> {}", last_gen, current_gen);
                    last_gen = current_gen;
                    last_presented_frame_pts = None;
                    last_presented_frame_time = None;
                    pacing_interval_average_ms = None;
                    pacing_drift_average_ms = None;
                    // Generation change wakes immediately (no stale wait).
                }

                let state = clock.get_state();
                if state != PlaybackState::Playing && state != PlaybackState::Rebuffering {
                    starvation_started = None;
                    recovery_ready_started = None;
                    // Paused/completed/backgrounded: no presentation requests.
                    // Wait efficiently for state change / new seek / stop.
                    if let Some(sig) = frame_ready.as_ref() {
                        let lock = &sig.0;
                        let cvar = &sig.1;
                        let mut guard = lock.lock();
                        // Wake early on frame-ready signal (e.g. seek flush),
                        // otherwise re-check state after the idle timeout.
                        let _ = cvar.wait_for(&mut guard, Duration::from_millis(FRAME_READY_WAIT_IDLE_MS));
                        observed_version = *guard;
                    } else {
                        thread::sleep(Duration::from_millis(FRAME_READY_WAIT_IDLE_MS));
                    }
                    continue;
                }

                // Native rebuffering is a latched state. No frame is
                // requested while starved, so the last texture remains on
                // screen and the audio callback outputs silence with a
                // frozen clock. Recovery requires a small frame cushion and
                // hysteresis before returning to Playing.
                if state == PlaybackState::Rebuffering {
                    if video_frame_queue.len() >= REBUFFER_RESUME_FRAMES {
                        recovery_ready_started.get_or_insert_with(Instant::now);
                        if recovery_ready_started
                            .map(|t| t.elapsed() >= Duration::from_millis(REBUFFER_RESUME_DELAY_MS))
                            .unwrap_or(false)
                        {
                            clock.resume_from_rebuffering();
                            recovery_ready_started = None;
                            starvation_started = None;
                        }
                    } else {
                        recovery_ready_started = None;
                    }
                    if let Some(sig) = frame_ready.as_ref() {
                        let lock = &sig.0;
                        let cvar = &sig.1;
                        let mut guard = lock.lock();
                        let _ = cvar.wait_for(
                            &mut guard,
                            Duration::from_millis(FRAME_READY_WAIT_PLAYING_MS),
                        );
                        observed_version = *guard;
                    } else {
                        thread::sleep(Duration::from_millis(FRAME_READY_WAIT_PLAYING_MS));
                    }
                    continue;
                }

                // Playing: wait for a new frame, seek, stop or timeout.
                // Exactly one wake per presentable frame — no 60/120 Hz poll.
                if let Some(sig) = frame_ready.as_ref() {
                    let lock = &sig.0;
                    let cvar = &sig.1;
                    let mut guard = lock.lock();
                    if *guard == observed_version && video_frame_queue.is_empty() {
                        let _ = cvar.wait_for(&mut guard, Duration::from_millis(FRAME_READY_WAIT_PLAYING_MS));
                    }
                    observed_version = *guard;
                } else {
                    thread::sleep(Duration::from_millis(FRAME_READY_WAIT_PLAYING_MS));
                }

                if !is_running.load(Ordering::SeqCst) {
                    break;
                }
                if is_suspended.load(Ordering::SeqCst) {
                    continue;
                }
                if seek.seek_generation.load(Ordering::Relaxed) != last_gen {
                    continue; // re-loop to invalidate pacing history
                }
                if clock.get_state() != PlaybackState::Playing {
                    continue;
                }

                if video_frame_queue.is_empty() {
                    let started = starvation_started.get_or_insert_with(Instant::now);
                    if started.elapsed() >= Duration::from_millis(REBUFFER_ENTER_DELAY_MS) {
                        clock.enter_rebuffering();
                        recovery_ready_started = None;
                    }
                    continue;
                }
                starvation_started = None;

                hard_resync.maybe_resync(
                    &display_frame,
                    seek.as_ref(),
                    clock.as_ref(),
                    &audio_clock_ms,
                    &video_frame_queue,
                );

                // `PlaybackClock` is synchronized from the sample-accurate
                // audio callback whenever audio is flowing. Reading the
                // clock here, rather than a raw nonzero audio timestamp,
                // also keeps presentation moving if an output callback is
                // briefly unavailable (for example after a seek or device
                // reconfiguration). A stale audio timestamp must not leave
                // decoded video permanently queued behind a frozen PTS.
                let media_ms = clock.get_media_time_ms();

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
                } else {
                    // Frames are decoded but their PTS is still ahead of the
                    // synchronized clock. Do not spin here: repeated
                    // sub-millisecond reads otherwise prevent the fallback
                    // clock from advancing when an audio callback is late.
                    // A short condition-variable wait also wakes immediately
                    // for a seek, stop, or newly decoded frame.
                    if let Some(sig) = frame_ready.as_ref() {
                        let lock = &sig.0;
                        let cvar = &sig.1;
                        let mut guard = lock.lock();
                        let _ = cvar.wait_for(&mut guard, Duration::from_millis(1));
                        observed_version = *guard;
                    } else {
                        thread::sleep(Duration::from_millis(1));
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
        // Wake the pump so it exits promptly (§5: stops on disposed).
        if let Some(sig) = self.frame_ready.lock().clone() {
            sig.1.notify_all();
        }
        *self.display_frame.lock() = None;
        *self.frozen_frame.lock() = None;
        if let Some(handle) = self.thread_handle.lock().take() {
            let _ = handle.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_ready_signal_wakes_waiter() {
        let sig: Arc<(Mutex<u64>, Condvar)> =
            Arc::new((Mutex::new(0), Condvar::new()));
        let sig2 = sig.clone();
        let handle = thread::spawn(move || {
            let (lock, cvar) = &*sig2;
            let mut guard = lock.lock();
            let v0 = *guard;
            let _ = cvar.wait_for(&mut guard, Duration::from_millis(2000));
            assert_ne!(*guard, v0);
        });
        thread::sleep(Duration::from_millis(50));
        {
            let lock = &sig.0;
            let cvar = &sig.1;
            let mut v = lock.lock();
            *v = v.wrapping_add(1);
            cvar.notify_all();
        }
        handle.join().unwrap();
    }

    #[test]
    fn presenter_advances_when_audio_clock_stops_after_seek() {
        // A seek sets the audio clock to its target before the next audio
        // callback. The presenter must not treat that one timestamp as a
        // permanent master clock or future video frames can never become due.
        let clock = Arc::new(PlaybackClock::new());
        clock.start();
        clock.sync_from_audio_ms(100);
        let audio_clock = Arc::new(AtomicU64::new(100));
        let video_packets = Arc::new(PacketQueue::new(8));
        let audio_packets = Arc::new(PacketQueue::new(8));
        let video_frames = Arc::new(FrameQueue::new(8));
        let audio_frames = Arc::new(FrameQueue::new(8));
        video_frames.enqueue(MediaVideoFrame {
            pts_ms: 120,
            width: 1,
            height: 1,
            pixels: vec![0; 4],
            pixel_buffer_ptr: 0,
            seek_generation: 0,
        });

        let presenter = PresenterRuntime::new();
        let signal: Arc<(Mutex<u64>, Condvar)> =
            Arc::new((Mutex::new(0), Condvar::new()));
        presenter.set_frame_ready(signal.clone());
        let seek = Arc::new(SeekController::new(
            Arc::new(AtomicI64::new(-1)),
            Arc::new(AtomicBool::new(false)),
            Arc::new(AtomicBool::new(false)),
            clock.clone(),
            audio_clock.clone(),
            video_packets,
            audio_packets,
            video_frames.clone(),
            audio_frames,
            Arc::new(AtomicU64::new(0)),
            presenter.get_display_frame(),
            presenter.frozen_frame.clone(),
        ));
        seek.set_frame_ready(signal);
        presenter.start(clock, video_frames.clone(), audio_clock, seek);

        let deadline = Instant::now() + Duration::from_millis(500);
        let mut presented = None;
        while Instant::now() < deadline {
            if let Some(frame) = presenter.take_display_frame() {
                presented = Some(frame);
                break;
            }
            thread::sleep(Duration::from_millis(5));
        }
        presenter.stop();

        assert_eq!(presented.map(|frame| frame.pts_ms), Some(120));
    }
}

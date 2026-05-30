//! Acceptance threshold tests — keep in sync with Dart [MediaPlaybackAcceptance].

#[cfg(test)]
mod acceptance {
    use crate::presenter_runtime::{
        HARD_RESYNC_COOLDOWN_MS, HARD_RESYNC_DRIFT_MS, HARD_RESYNC_SEEK_GRACE_MS,
        PRESENTER_INTERVAL_MS,
    };
    use crate::video_decode::{CATCHUP_KEYFRAME_ONLY_MS, CATCHUP_SKIP_NON_KEYFRAME_MS};

    #[test]
    fn rust_dart_threshold_alignment() {
        assert_eq!(PRESENTER_INTERVAL_MS, 16);
        assert_eq!(CATCHUP_SKIP_NON_KEYFRAME_MS, 500);
        assert_eq!(CATCHUP_KEYFRAME_ONLY_MS, 1500);
        assert_eq!(HARD_RESYNC_DRIFT_MS, 2000);
        assert_eq!(HARD_RESYNC_COOLDOWN_MS, 3000);
        assert_eq!(HARD_RESYNC_SEEK_GRACE_MS, 2000);
    }
}

//! Centralized env flag names and accessors for the engine.
//!
//! Adding a new engine feature? Add its flag name here, add a constant, and
//! add a line to [`log_startup_banner`]. Tests live in
//! `engine::env_flags::tests` at the bottom of this file.

/// Master switch for the `VtPixelBufferPool` + global cap + LRU eviction
/// pipeline (Apple-only). `0` (default) preserves today's per-frame
/// `CVPixelBufferCreate` path.
pub const ENGINE_VT_POOL: &str = "VFP_ENGINE_VT_POOL";

/// Global IOSurface budget in MiB across all `VtPixelBufferPool` instances.
/// `0` disables the cap. Default `256`.
pub const VT_POOL_GLOBAL_CAP_MB: &str = "VFP_VT_POOL_GLOBAL_CAP_MB";

/// Cap on the number of distinct `(width, height, kCVPixelFormatType_*)`
/// pools the `VtPoolCache` will keep alive. When the cap is hit, the
/// least-recently-used pool is evicted. Default `8`.
pub const VT_POOL_MAX_POOLS: &str = "VFP_VT_POOL_MAX_POOLS";

/// Eviction policy when the global cap is hit. `soft` (default) drops the
/// `Arc` strong ref so the pool dies when its last consumer releases.
/// `none` disables eviction.
pub const VT_POOL_EVICTION: &str = "VFP_VT_POOL_EVICTION";

/// Base cooldown (ms) between consecutive fires of the same recovery
/// strategy. Default `200`.
pub const RECOVERY_COOLDOWN_MS: &str = "VFP_RECOVERY_COOLDOWN_MS";

/// Maximum cooldown (ms) after exponential backoff. Default `2000`.
pub const RECOVERY_COOLDOWN_MAX_MS: &str = "VFP_RECOVERY_COOLDOWN_MAX_MS";

/// `2^shift` cap on the backoff multiplier. Default `4` (16× base).
pub const RECOVERY_COOLDOWN_BACKOFF_SHIFT: &str = "VFP_RECOVERY_COOLDOWN_BACKOFF_SHIFT";

/// Comma-separated `flush,jump,reopen,reset` budget. Default `"4,2,2,1"`.
pub const RECOVERY_BUDGET: &str = "VFP_RECOVERY_BUDGET";

/// Pacer: below this drift (ms) the frame is released immediately.
/// Default `80`.
pub const PACER_SOFT_DRIFT_MS: &str = "VFP_PACER_SOFT_DRIFT_MS";

/// Pacer: above this drift (ms) the `start` instant is snapped forward /
/// backward by the drift amount. Default `300`.
pub const PACER_HARD_DRIFT_MS: &str = "VFP_PACER_HARD_DRIFT_MS";

/// Pacer: above this drift (ms) a `PacerAction::ReSeek` is returned so the
/// engine re-seeks the demuxer. Default `1500`.
pub const PACER_RESEEK_DRIFT_MS: &str = "VFP_PACER_RESEEK_DRIFT_MS";

/// Telemetry: interval (ms) between queue-depth log lines. `0` disables.
/// Default `1000`.
pub const TELEMETRY_INTERVAL_MS: &str = "VFP_ENGINE_TELEMETRY_INTERVAL_MS";

/// Returns `true` when the env flag is set to `"1"`, `"true"`, or `"yes"`.
pub fn bool_flag(name: &str) -> bool {
    matches!(
        std::env::var(name).as_deref(),
        Ok("1") | Ok("true") | Ok("yes")
    )
}

/// Parses the env flag as a `u64`. Returns `default` on missing/invalid.
pub fn int_flag(name: &str, default: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(default)
}

/// Parses the env flag as a `u64`, falling back to `default` on missing.
pub fn str_flag(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_string())
}

/// Reports whether the named engine feature is active in this process.
pub fn is_engine_active(name: &str) -> bool {
    bool_flag(name)
}

/// Emit one log line per enabled engine flag and per explicitly-set
/// tuning knob. The banner is grep-friendly: every line starts with
/// `[Engine]` so a person can `grep '\[Engine\]'` to see what was active.
///
/// Call this once at session start, after `ensure_ffmpeg_initialized`.
pub fn log_startup_banner() {
    let feature_flags: &[(&str, &str)] = &[
        (ENGINE_VT_POOL, "VtPixelBufferPool + global cap + LRU eviction"),
        ("VFP_ENGINE_PACER", "Pacer drift correction + FrameQueue latest-wins"),
        ("VFP_ENGINE_LIFECYCLE", "DecoderState machine + health metrics"),
        ("VFP_ENGINE_REFILL", "RefillThread + PacketQueue (decoder stays on main worker)"),
        ("VFP_ENGINE_RECOVERY", "SeekRecovery classifier + cooldown/backoff"),
        ("VFP_ENGINE_TELEMETRY", "queue-depth telemetry thread"),
    ];
    for (flag, label) in feature_flags {
        if bool_flag(flag) {
            log::info!("[Engine] {flag}=1 active ({label})");
        }
    }

    let tuning_flags: &[(&str, &str)] = &[
        (VT_POOL_GLOBAL_CAP_MB, "global IOSurface cap (MiB)"),
        (VT_POOL_MAX_POOLS, "max distinct (w,h,format) pools"),
        (VT_POOL_EVICTION, "eviction policy"),
        (RECOVERY_COOLDOWN_MS, "recovery base cooldown (ms)"),
        (RECOVERY_COOLDOWN_MAX_MS, "recovery max cooldown (ms)"),
        (RECOVERY_COOLDOWN_BACKOFF_SHIFT, "recovery backoff shift (2^shift)"),
        (RECOVERY_BUDGET, "recovery budget (flush,jump,reopen,reset)"),
        (PACER_SOFT_DRIFT_MS, "pacer soft drift (ms)"),
        (PACER_HARD_DRIFT_MS, "pacer hard drift (ms)"),
        (PACER_RESEEK_DRIFT_MS, "pacer re-seek drift (ms)"),
        (TELEMETRY_INTERVAL_MS, "telemetry interval (ms, 0=off)"),
    ];
    for (flag, label) in tuning_flags {
        if let Ok(v) = std::env::var(flag) {
            log::info!("[Engine] {flag}={v} ({label})");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Serializes all env-flag test mutations. `std::env::set_var` /
    /// `remove_var` mutate process-wide state; without this lock two
    /// tests using the same variable name would race.
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    /// Helper: a fresh process env for tests. The host's env is global
    /// state; this wrapper scopes the lifetime.
    fn with_flag<F: FnOnce()>(name: &str, value: &str, f: F) {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let prev = std::env::var(name).ok();
        // SAFETY: tests in this module are serialized by ENV_LOCK.
        unsafe {
            std::env::set_var(name, value);
        }
        f();
        unsafe {
            match prev {
                Some(v) => std::env::set_var(name, v),
                None => std::env::remove_var(name),
            }
        }
    }

    #[test]
    fn bool_flag_accepts_known_truthy_values() {
        for v in ["1", "true", "yes"] {
            with_flag("VFP_TEST_BOOL", v, || {
                assert!(bool_flag("VFP_TEST_BOOL"));
            });
        }
    }

    #[test]
    fn bool_flag_rejects_unknown_values() {
        with_flag("VFP_TEST_BOOL", "0", || {
            assert!(!bool_flag("VFP_TEST_BOOL"));
        });
        with_flag("VFP_TEST_BOOL", "no", || {
            assert!(!bool_flag("VFP_TEST_BOOL"));
        });
        assert!(!bool_flag("VFP_TEST_BOOL_DEFINITELY_NOT_SET_XYZ"));
    }

    #[test]
    fn int_flag_uses_default_on_missing_or_invalid() {
        assert_eq!(int_flag("VFP_TEST_INT_MISSING", 42), 42);
        with_flag("VFP_TEST_INT", "not-a-number", || {
            assert_eq!(int_flag("VFP_TEST_INT", 42), 42);
        });
    }

    #[test]
    fn int_flag_parses_valid() {
        with_flag("VFP_TEST_INT", "123", || {
            assert_eq!(int_flag("VFP_TEST_INT", 0), 123);
        });
    }

    #[test]
    fn str_flag_uses_default_on_missing() {
        assert_eq!(str_flag("VFP_TEST_STR_MISSING", "fallback"), "fallback");
    }

    #[test]
    fn is_engine_active_truthy_and_falsy() {
        with_flag("VFP_TEST_ACTIVE", "1", || {
            assert!(is_engine_active("VFP_TEST_ACTIVE"));
        });
        with_flag("VFP_TEST_ACTIVE", "yes", || {
            assert!(is_engine_active("VFP_TEST_ACTIVE"));
        });
        with_flag("VFP_TEST_ACTIVE", "0", || {
            assert!(!is_engine_active("VFP_TEST_ACTIVE"));
        });
        assert!(!is_engine_active("VFP_TEST_DEFINITELY_NOT_SET_ABC"));
    }

    #[test]
    fn log_startup_banner_does_not_panic() {
        // We can't easily capture log output, but we can ensure the
        // function runs to completion under various flag combinations.
        // We can't nest `with_flag` (the env lock is not reentrant),
        // so we set/clear the flags in sequence under one lock.
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let prev_vt = std::env::var(ENGINE_VT_POOL).ok();
        let prev_cap = std::env::var(VT_POOL_GLOBAL_CAP_MB).ok();
        let prev_max = std::env::var(VT_POOL_MAX_POOLS).ok();
        unsafe {
            std::env::set_var(ENGINE_VT_POOL, "1");
            std::env::set_var(VT_POOL_GLOBAL_CAP_MB, "128");
            std::env::set_var(VT_POOL_MAX_POOLS, "4");
        }
        log_startup_banner();
        // Off path
        unsafe {
            std::env::set_var(ENGINE_VT_POOL, "0");
            std::env::remove_var(VT_POOL_GLOBAL_CAP_MB);
            std::env::remove_var(VT_POOL_MAX_POOLS);
        }
        log_startup_banner();
        // Restore previous state.
        unsafe {
            match prev_vt {
                Some(v) => std::env::set_var(ENGINE_VT_POOL, v),
                None => std::env::remove_var(ENGINE_VT_POOL),
            }
            match prev_cap {
                Some(v) => std::env::set_var(VT_POOL_GLOBAL_CAP_MB, v),
                None => std::env::remove_var(VT_POOL_GLOBAL_CAP_MB),
            }
            match prev_max {
                Some(v) => std::env::set_var(VT_POOL_MAX_POOLS, v),
                None => std::env::remove_var(VT_POOL_MAX_POOLS),
            }
        }
    }
}

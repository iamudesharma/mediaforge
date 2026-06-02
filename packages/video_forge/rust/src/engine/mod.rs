//! Video engine internals: lifecycle, recovery, pacing, queues, and
//! Apple-specific VT pool management. Each sub-module is gated by its own
//! `VFP_ENGINE_*` env flag and is a no-op on platforms where it does not
//! apply (see individual sub-modules for cfg gates).
//!
//! Startup banner: [`log_startup_banner`] emits one log line per enabled
//! flag, mirroring what is enabled at session end. Together they make it
//! possible to grep the log and confirm the engine ran the whole session
//! without falling back to the pre-engine code path.
//!
//! Sub-modules planned (this PR adds [`vt_pool`] and [`seek_recovery`];
//! the rest land in the same PR behind their own env flags):
//! - [`vt_pool`] — Apple `CVPixelBufferPool` + global cap + LRU eviction
//! - [`lifecycle`] — `DecoderState` machine, `DecoderHealth` metrics
//! - [`seek_recovery`] — classifier + cooldown/backoff budget
//! - [`frame_queue`] — bounded `FrameQueue<T>` with `LatestWins` mode
//! - [`pacer`] — wall-clock pacer with drift correction + re-seek action
//! - [`refill`] — demuxer `RefillThread` v1 (packet-queue only; no decoder)
//! - [`telemetry`] — queue-depth telemetry thread

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub mod vt_pool;

pub mod env_flags;
pub mod frame_queue;
pub mod lifecycle;
pub mod pacer;
pub mod refill;
pub mod seek_recovery;
pub mod telemetry;

pub use env_flags::{
    bool_flag, int_flag, is_engine_active, log_startup_banner, str_flag, ENGINE_VT_POOL,
    PACER_HARD_DRIFT_MS, PACER_RESEEK_DRIFT_MS, PACER_SOFT_DRIFT_MS, RECOVERY_BUDGET,
    RECOVERY_COOLDOWN_BACKOFF_SHIFT, RECOVERY_COOLDOWN_MAX_MS, RECOVERY_COOLDOWN_MS,
    TELEMETRY_INTERVAL_MS, VT_POOL_EVICTION, VT_POOL_GLOBAL_CAP_MB, VT_POOL_MAX_POOLS,
};
pub use frame_queue::{FrameQueue, FrameQueueMode, FrameQueueStats};
pub use lifecycle::{DecoderHealth, DecoderState, HealthSnapshot, Lifecycle, Transition};
pub use pacer::{Pacer, PacerAction, PacerStats};
pub use refill::{
    PacketQueue, PacketRef, RefillCommand, RefillStats, RefillStatsSnapshot, RefillThread,
};
pub use seek_recovery::{
    classify, parse_budget_spec, BudgetSlot, RecoveryBudget, RecoveryBudgetStats,
    RecoverySignal, RecoveryStrategy,
};
pub use telemetry::{TelemetrySample, TelemetrySource, TelemetryThread};

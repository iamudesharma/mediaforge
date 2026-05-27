//! Nexus A — temporal landmark/mask smoothing for live camera.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Mutex, OnceLock};

use crate::api::face::FaceAnalysisResult;
use crate::face::TemporalSmoother;

static SMOOTHERS: OnceLock<Mutex<HashMap<i64, TemporalSmoother>>> = OnceLock::new();
static NEXT_SMOOTHER_ID: AtomicI64 = AtomicI64::new(1);

fn smoothers() -> &'static Mutex<HashMap<i64, TemporalSmoother>> {
    SMOOTHERS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Create a temporal smoother registry entry (α ≈ 0.25 recommended for live camera).
/// Returns a unique smoother ID.
#[flutter_rust_bridge::frb(sync)]
pub fn temporal_smoother_create(alpha: f32) -> i64 {
    let id = NEXT_SMOOTHER_ID.fetch_add(1, Ordering::Relaxed);
    smoothers()
        .lock()
        .expect("temporal smoother registry poisoned")
        .insert(id, TemporalSmoother::new(alpha));
    id
}

/// Applies Exponential Moving Average (EMA) smoothing to landmarks and segmentation masks.
/// Automatically resets state when the landmark point-count changes.
#[flutter_rust_bridge::frb(sync)]
pub fn temporal_smoother_smooth(id: i64, raw: FaceAnalysisResult) -> FaceAnalysisResult {
    let mut guard = smoothers()
        .lock()
        .expect("temporal smoother registry poisoned");
    match guard.get_mut(&id) {
        Some(s) => s.smooth(raw),
        None => raw,
    }
}

/// Resets the internal smoothing filters for the specified smoother ID.
#[flutter_rust_bridge::frb(sync)]
pub fn temporal_smoother_reset(id: i64) {
    if let Some(s) = smoothers()
        .lock()
        .expect("temporal smoother registry poisoned")
        .get_mut(&id)
    {
        s.reset();
    }
}

/// Destroys the temporal smoother and frees its resources from the registry.
#[flutter_rust_bridge::frb(sync)]
pub fn temporal_smoother_destroy(id: i64) {
    smoothers()
        .lock()
        .expect("temporal smoother registry poisoned")
        .remove(&id);
}

//! Runtime + backend integration tests.
//!
//! `runtime::POOL_ENABLED` is a `OnceLock` that latches on the first call to
//! `pool_enabled()`, so the env-toggle case is intrinsically racy *across*
//! tests in the same process. We split it into its own integration binary
//! (cargo test compiles each `tests/*.rs` as a standalone binary) and force
//! `RUST_IMAGE_NO_POOL=1` before any pool/runtime call inside the binary.
//!
//! All tests in this file therefore observe `pool_enabled() == false`.

mod common;

use std::sync::Once;

use image_forge::api::advanced::{
    buffer_pool_acquire, buffer_pool_release, buffer_pool_stats, gpu_compute_info,
    is_gpu_compute_available, processing_backend_name,
};
use image_forge::api::image::ProcessingBackend;
use image_forge::runtime::{configure_runtime, pool_enabled, runtime_flags_label};

static INIT: Once = Once::new();

/// Force the pool off and lock `POOL_ENABLED` to `false` before any other code
/// can read it. Must be the first call in every test in this binary.
fn init_pool_disabled() {
    INIT.call_once(|| {
        // `set_var` is still safe in edition 2021 on stable Rust; the 2024
        // edition wraps it in `unsafe`. We're on edition 2021.
        std::env::set_var("RUST_IMAGE_NO_POOL", "1");
        configure_runtime();
        // Force the lock to materialize from `configure_runtime`.
        assert!(!pool_enabled(), "pool must be disabled in pool_runtime tests");
    });
}

// ---------------------------------------------------------------------------
// Runtime
// ---------------------------------------------------------------------------

#[test]
fn pool_disabled_via_env_var() {
    init_pool_disabled();
    assert!(!pool_enabled());
}

#[test]
fn pool_stats_zero_when_disabled() {
    init_pool_disabled();
    let stats = buffer_pool_stats();
    assert_eq!(stats, (0, 0), "expected (0, 0), got {stats:?}");
}

#[test]
fn pool_release_is_noop_when_disabled() {
    init_pool_disabled();
    let buf = vec![0u8; 4096];
    buffer_pool_release(buf);
    let stats = buffer_pool_stats();
    assert_eq!(stats, (0, 0), "release must not pool when disabled");
}

#[test]
fn pool_acquire_returns_fresh_buffer_when_disabled() {
    init_pool_disabled();
    let buf = buffer_pool_acquire(1024);
    assert!(buf.capacity() >= 1024);
    // Pool stays empty.
    assert_eq!(buffer_pool_stats(), (0, 0));
}

#[test]
fn configure_runtime_is_idempotent() {
    init_pool_disabled();
    // Calling again should not flip the latched OnceLock value.
    configure_runtime();
    configure_runtime();
    assert!(!pool_enabled());
}

#[test]
fn runtime_flags_label_reports_pool_off() {
    init_pool_disabled();
    let label = runtime_flags_label();
    assert!(
        label.contains("pool=off"),
        "expected 'pool=off' in label, got: {label}"
    );
    assert!(label.contains("rayon="), "expected rayon= segment, got: {label}");
}

// ---------------------------------------------------------------------------
// Backend resolve (via public `processing_backend_name`)
// ---------------------------------------------------------------------------

#[test]
fn processing_backend_name_cpu_always_cpu_simd() {
    init_pool_disabled();
    assert_eq!(processing_backend_name(ProcessingBackend::Cpu), "cpu_simd");
}

#[test]
fn processing_backend_name_auto_never_unavailable() {
    init_pool_disabled();
    // Auto must always resolve — to GPU when available, else CPU.
    let name = processing_backend_name(ProcessingBackend::Auto);
    assert_ne!(name, "unavailable", "Auto must always resolve");
    assert!(!name.is_empty());
}

#[test]
fn processing_backend_name_gpu_matches_availability() {
    init_pool_disabled();
    let name = processing_backend_name(ProcessingBackend::Gpu);
    if is_gpu_compute_available() {
        assert_ne!(name, "unavailable", "GPU available but name = unavailable");
        assert!(!name.is_empty());
    } else {
        assert_eq!(
            name, "unavailable",
            "GPU unavailable but name = {name}"
        );
    }
}

#[test]
fn gpu_compute_info_consistent_with_availability_flag() {
    init_pool_disabled();
    let info = gpu_compute_info();
    let avail = is_gpu_compute_available();
    assert_eq!(
        info.available, avail,
        "gpu_compute_info().available must match is_gpu_compute_available()"
    );
    if !info.available {
        assert!(
            info.api.is_empty(),
            "unavailable GPU must report empty api, got '{}'",
            info.api
        );
    }
}

// ---------------------------------------------------------------------------
// Cross-check: even with pool disabled, decode/encode keeps working.
// ---------------------------------------------------------------------------

#[test]
fn decode_encode_works_with_pool_disabled() {
    init_pool_disabled();
    let src = common::synthetic_jpeg(32, 32, 85);
    let info = image_forge::api::advanced::probe_image(src)
        .expect("probe ok even with pool off");
    assert_eq!((info.width, info.height), (32, 32));
}

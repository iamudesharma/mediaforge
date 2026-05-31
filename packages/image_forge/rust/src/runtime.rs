//! Process-wide runtime knobs (pool, Rayon) — read once at [configure_runtime].
use std::sync::OnceLock;

static POOL_ENABLED: OnceLock<bool> = OnceLock::new();

fn env_is_truthy(key: &str) -> bool {
    std::env::var(key)
        .map(|v| {
            let v = v.trim();
            v == "1" || v.eq_ignore_ascii_case("true") || v.eq_ignore_ascii_case("yes")
        })
        .unwrap_or(false)
}

/// Call from [crate::api::image::init_app] before any image work.
pub fn configure_runtime() {
    let pool_on = !env_is_truthy("RUST_IMAGE_NO_POOL")
        && !env_is_truthy("RUST_IMAGE_BENCH_NO_POOL");
    let _ = POOL_ENABLED.set(pool_on);

    if let Ok(n) = std::env::var("RUST_IMAGE_RAYON_THREADS") {
        if let Ok(n) = n.trim().parse::<usize>() {
            if n > 0 {
                let _ = rayon::ThreadPoolBuilder::new()
                    .num_threads(n)
                    .build_global();
            }
        }
    }
}

pub fn pool_enabled() -> bool {
    *POOL_ENABLED.get_or_init(|| {
        !env_is_truthy("RUST_IMAGE_NO_POOL") && !env_is_truthy("RUST_IMAGE_BENCH_NO_POOL")
    })
}

pub fn runtime_flags_label() -> String {
    format!(
        "pool={} rayon={}",
        if pool_enabled() { "on" } else { "off" },
        std::env::var("RAYON_NUM_THREADS")
            .or_else(|_| std::env::var("RUST_IMAGE_RAYON_THREADS"))
            .unwrap_or_else(|_| "default".into())
    )
}

use image_forge::api::image::ProcessingBackend;
use image_forge::backend::{self, EffectiveBackend};

#[test]
fn resolve_cpu_always_cpu() {
    let eff = backend::resolve(ProcessingBackend::Cpu).unwrap();
    assert_eq!(eff, EffectiveBackend::Cpu);
}

#[test]
fn resolve_auto_falls_back_when_gpu_unavailable() {
    if backend::gpu_available() {
        let eff = backend::resolve(ProcessingBackend::Auto).unwrap();
        assert_eq!(eff, EffectiveBackend::Gpu);
    } else {
        let eff = backend::resolve(ProcessingBackend::Auto).unwrap();
        assert_eq!(eff, EffectiveBackend::Cpu);
    }
}

#[test]
fn resolve_gpu_errors_when_unavailable() {
    if !backend::gpu_available() {
        let err = backend::resolve(ProcessingBackend::Gpu).unwrap_err();
        assert!(!err.is_empty());
    }
}

#[cfg(not(feature = "gpu"))]
#[test]
fn resolve_gpu_errors_without_feature() {
    let err = backend::resolve(ProcessingBackend::Gpu).unwrap_err();
    assert!(err.contains("GPU"));
}

use crate::api::image::ProcessingBackend;

/// Represents the resolved physical execution engine (CPU vs GPU).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EffectiveBackend {
    Cpu,
    Gpu,
}

/// Resolves a requested processing backend (`Auto`/`Gpu`/`Cpu`) to an actual executable backend.
pub fn resolve(requested: ProcessingBackend) -> Result<EffectiveBackend, String> {
    match requested {
        ProcessingBackend::Cpu => Ok(EffectiveBackend::Cpu),
        ProcessingBackend::Gpu => {
            if gpu_available() {
                Ok(EffectiveBackend::Gpu)
            } else {
                Err(gpu_unavailable_message())
            }
        }
        ProcessingBackend::Auto => {
            if gpu_available() {
                Ok(EffectiveBackend::Gpu)
            } else {
                Ok(EffectiveBackend::Cpu)
            }
        }
    }
}

pub fn gpu_available() -> bool {
    #[cfg(feature = "gpu")]
    {
        crate::gpu::is_available()
    }
    #[cfg(not(feature = "gpu"))]
    {
        false
    }
}

pub fn active_api_name(requested: ProcessingBackend) -> String {
    match resolve(requested) {
        Ok(EffectiveBackend::Gpu) => gpu_api_name(),
        Ok(EffectiveBackend::Cpu) => "cpu_simd".into(),
        Err(_) => "unavailable".into(),
    }
}

fn gpu_api_name() -> String {
    #[cfg(feature = "gpu")]
    {
        let (_, api, _) = crate::gpu::capabilities();
        api
    }
    #[cfg(not(feature = "gpu"))]
    {
        String::new()
    }
}

fn gpu_unavailable_message() -> String {
    #[cfg(feature = "gpu")]
    {
        "GPU compute unavailable on this device. Use ProcessingBackend.cpu or .auto.".into()
    }
    #[cfg(not(feature = "gpu"))]
    {
        "GPU feature not enabled. Rebuild rust_image_core with feature `gpu`.".into()
    }
}

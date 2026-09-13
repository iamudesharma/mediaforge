//! Android JVM registration for FFmpeg MediaCodec hwaccel.
//!
//! `libavcodec` MediaCodec decoding requires the JVM pointer via
//! `av_jni_set_java_vm` before `av_hwdevice_ctx_create(MEDIACODEC)`.
//! The `.so` entry point [`JNI_OnLoad`] registers it once on library load,
//! mirroring `video_forge`'s `platform/android.rs`. Compiled out on
//! non-Android targets.

use std::ffi::c_void;
use std::sync::Once;

extern "C" {
    fn av_jni_set_java_vm(vm: *mut c_void, log_ctx: *mut c_void) -> i32;
}

static JVM_REGISTERED: Once = Once::new();

/// Register the JVM with FFmpeg (safe to call more than once).
pub fn register_java_vm(vm: *mut c_void) {
    JVM_REGISTERED.call_once(|| unsafe {
        let rc = av_jni_set_java_vm(vm, std::ptr::null_mut());
        eprintln!("[media_forge] av_jni_set_java_vm rc={}", rc);
    });
}

/// Called by the JVM when the native library loads.
#[no_mangle]
pub unsafe extern "C" fn JNI_OnLoad(
    vm: *mut c_void,
    _reserved: *mut c_void,
) -> i32 {
    register_java_vm(vm);
    // JNI_VERSION_1_6
    0x00010006
}

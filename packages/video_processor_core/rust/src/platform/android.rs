//! Android FFmpeg / MediaCodec setup.

use std::ffi::c_void;
use std::sync::Once;

static JNI_INIT: Once = Once::new();

extern "C" {
    fn av_jni_set_java_vm(vm: *mut c_void, log_ctx: *mut c_void) -> i32;
}

/// Register the process JavaVM with FFmpeg (call from a JNI-attached thread).
pub fn register_java_vm(vm: *mut c_void) {
    JNI_INIT.call_once(|| {
        let ret = unsafe { av_jni_set_java_vm(vm, std::ptr::null_mut()) };
        if ret < 0 {
            log::warn!("av_jni_set_java_vm failed ({ret}); MediaCodec may use NDK path only");
        } else {
            log::debug!("FFmpeg JNI: JavaVM registered");
        }
    });
}

#[cfg(target_os = "android")]
pub fn register_java_vm_from_env(env: &jni::JNIEnv<'_>) {
    if let Ok(jvm) = env.get_java_vm() {
        register_java_vm(jvm.get_java_vm_pointer() as *mut c_void);
    }
}

/// Called by the runtime when `libvideo_processor_core.so` is loaded.
#[cfg(target_os = "android")]
#[no_mangle]
pub unsafe extern "C" fn JNI_OnLoad(
    java_vm: *mut jni::sys::JavaVM,
    _reserved: *mut c_void,
) -> jni::sys::jint {
    register_java_vm(java_vm as *mut c_void);
    jni::sys::JNI_VERSION_1_6
}

/// No-op if JNI_OnLoad already ran; FRB threads are attached when Rust API is called.
pub fn ensure_ffmpeg_jni() {}

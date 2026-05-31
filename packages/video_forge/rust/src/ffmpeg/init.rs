use std::sync::Once;

use ffmpeg_next::util::error::Error as FfmpegError;

use crate::error::{Result, VideoProcessorError};

static INIT: Once = Once::new();

pub fn ensure_ffmpeg_initialized() -> Result<()> {
    INIT.call_once(|| {
        // Required so ffmpeg_next::Error::to_string() returns real messages (not empty).
        ffmpeg_next::util::error::register_all();
        let _ = ffmpeg_next::format::network::init();
        ffmpeg_next::device::register_all();
        #[cfg(target_os = "android")]
        {
            // JNI_OnLoad registers the VM when the .so is loaded; this covers late attach.
            crate::platform::android::ensure_ffmpeg_jni();
        }
    });
    Ok(())
}

pub fn map_ffmpeg_error(err: FfmpegError) -> VideoProcessorError {
    let mut msg = ffmpeg_error_message(&err);
    if let Some(hint) = remote_error_hint(&err) {
        msg = format!("{msg} — {hint}");
    }
    VideoProcessorError::FfmpegError(msg)
}

fn ffmpeg_error_message(err: &FfmpegError) -> String {
    let s = err.to_string();
    if !s.is_empty() && s != "Unknown error occurred" {
        return s;
    }
    match err {
        FfmpegError::InvalidData => "invalid data (corrupt packet or unsupported pixel format)".into(),
        FfmpegError::EncoderNotFound => "encoder not found".into(),
        FfmpegError::DecoderNotFound => "decoder not found".into(),
        FfmpegError::External => {
            #[cfg(target_os = "android")]
            {
                return "MediaCodec/JNI failure (often pixel-format mismatch; ensure native lib is rebuilt)"
                    .into();
            }
            #[cfg(not(target_os = "android"))]
            {
                return "external library failure".into();
            }
        }
        FfmpegError::Eof => "unexpected end of stream".into(),
        FfmpegError::Other { errno } => format!("ffmpeg/os errno {errno}"),
        _ => format!("{err:?}"),
    }
}

fn remote_error_hint(err: &FfmpegError) -> Option<&'static str> {
    match err {
        FfmpegError::HttpForbidden => Some(
            "HTTP 403 Forbidden (server blocked the request; try HTTPS, another URL, or check access)",
        ),
        FfmpegError::HttpNotFound => Some("HTTP 404 Not Found"),
        FfmpegError::HttpUnauthorized => Some("HTTP 401 Unauthorized"),
        FfmpegError::HttpBadRequest => Some("HTTP 400 Bad Request"),
        FfmpegError::HttpServerError => Some("HTTP 5xx server error"),
        FfmpegError::ProtocolNotFound => Some(
            "protocol not enabled in FFmpeg build (rebuild with network protocols)",
        ),
        _ => None,
    }
}

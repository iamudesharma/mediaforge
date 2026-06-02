use thiserror::Error;

#[derive(Debug, Clone, Error)]
pub enum VideoForgeError {
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("file not found: {0}")]
    FileNotFound(String),
    #[error("unsupported codec: {0}")]
    UnsupportedCodec(String),
    #[error("job not found: {0}")]
    JobNotFound(String),
    #[error("job cancelled")]
    Cancelled,
    #[error("I/O error: {0}")]
    IoError(String),
    #[error("ffmpeg error: {0}")]
    FfmpegError(String),
    #[error("queue full: max concurrent jobs reached")]
    QueueFull,
    #[error("internal error: {0}")]
    Internal(String),
    /// Recovery cooldown active (engine::seek_recovery). The caller
    /// may escalate to a more aggressive strategy or skip the
    /// operation. Distinct from `Internal` so callers can pattern-match
    /// on it.
    #[error("recovery cooldown active for {0:?}, remaining {1}ms")]
    CooldownActive(String, u64),
    /// All attempts of a particular recovery strategy have been
    /// exhausted. Caller should treat the session as unrecoverable for
    /// the current failure.
    #[error("recovery budget exhausted for {0:?}")]
    RecoveryBudgetExhausted(String),
}

impl VideoForgeError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidInput(_) => "invalid_input",
            Self::FileNotFound(_) => "file_not_found",
            Self::UnsupportedCodec(_) => "unsupported_codec",
            Self::JobNotFound(_) => "job_not_found",
            Self::Cancelled => "cancelled",
            Self::IoError(_) => "io_error",
            Self::FfmpegError(_) => "ffmpeg_error",
            Self::QueueFull => "queue_full",
            Self::Internal(_) => "internal",
            Self::CooldownActive(_, _) => "cooldown_active",
            Self::RecoveryBudgetExhausted(_) => "recovery_budget_exhausted",
        }
    }
}

pub type Result<T> = std::result::Result<T, VideoForgeError>;

/// Deprecated alias for [`VideoForgeError`] kept for one release to avoid breaking
/// downstream callers (e.g. `video_forge_kit`, `media_studio`) that still match
/// on the old name. New code should use [`VideoForgeError`].
#[deprecated(
    since = "2.0.0",
    note = "renamed to `VideoForgeError`; will be removed in 2.1.0"
)]
pub type VideoProcessorError = VideoForgeError;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cooldown_active_error_codes() {
        let e = VideoForgeError::CooldownActive("Flush".to_string(), 250);
        assert_eq!(e.code(), "cooldown_active");
        let s = format!("{e}");
        assert!(s.contains("Flush"));
        assert!(s.contains("250"));
    }

    #[test]
    fn recovery_budget_exhausted_error_codes() {
        let e = VideoForgeError::RecoveryBudgetExhausted("DemuxerReopen".to_string());
        assert_eq!(e.code(), "recovery_budget_exhausted");
        let s = format!("{e}");
        assert!(s.contains("DemuxerReopen"));
    }

    #[test]
    fn existing_error_codes_unchanged() {
        assert_eq!(VideoForgeError::QueueFull.code(), "queue_full");
        assert_eq!(VideoForgeError::Cancelled.code(), "cancelled");
        assert_eq!(
            VideoForgeError::InvalidInput("x".into()).code(),
            "invalid_input"
        );
    }
}

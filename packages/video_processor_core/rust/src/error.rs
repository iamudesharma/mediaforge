use thiserror::Error;

#[derive(Debug, Clone, Error)]
pub enum VideoProcessorError {
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
}

impl VideoProcessorError {
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
        }
    }
}

pub type Result<T> = std::result::Result<T, VideoProcessorError>;

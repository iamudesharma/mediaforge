use crate::jobs::registry::CancellationToken;

pub struct InterruptContext {
    token: CancellationToken,
}

impl InterruptContext {
    pub fn new(token: CancellationToken) -> Self {
        Self { token }
    }

    pub fn check(&self) -> bool {
        self.token.is_cancelled()
    }
}

/// Attach cancellation polling to an input context when supported by the linked FFmpeg build.
pub fn attach_interrupt(
    _ictx: &mut ffmpeg_next::format::context::Input,
    _token: CancellationToken,
) {
    // FFmpeg interrupt callbacks require raw AVFormatContext access; cancellation is
    // polled in the decode loop via InterruptContext for portability across ffmpeg-next versions.
}

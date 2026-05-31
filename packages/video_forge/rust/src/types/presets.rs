use super::{QualityPreset, VideoQuality as Vq};

/// Social / messaging app style compression targets (DX presets).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CompressionPreset {
    /// Balanced default (1080p cap, CRF 23).
    Standard,
    /// ~1080p, moderate bitrate — feeds & stories.
    Instagram,
    /// ~720p, smaller files — chat apps.
    Whatsapp,
    /// ~1280p, good quality/size balance.
    Telegram,
    /// 1080p, higher bitrate for uploads.
    Youtube,
    /// Near-lossless export (large files).
    Lossless,
    /// Aggressive size reduction (720p, high CRF).
    LowBandwidth,
}

impl CompressionPreset {
    pub fn quality_preset(self) -> QualityPreset {
        match self {
            Self::Standard => QualityPreset {
                crf: 23,
                max_bitrate: 3_000_000,
                max_dimension: 1080,
                max_fps: 30.0,
            },
            Self::Instagram => QualityPreset {
                crf: 24,
                max_bitrate: 2_500_000,
                max_dimension: 1080,
                max_fps: 30.0,
            },
            Self::Whatsapp => QualityPreset {
                crf: 28,
                max_bitrate: 1_000_000,
                max_dimension: 720,
                max_fps: 30.0,
            },
            Self::Telegram => QualityPreset {
                crf: 23,
                max_bitrate: 2_800_000,
                max_dimension: 1280,
                max_fps: 30.0,
            },
            Self::Youtube => QualityPreset {
                crf: 20,
                max_bitrate: 6_000_000,
                max_dimension: 1080,
                max_fps: 60.0,
            },
            Self::Lossless => QualityPreset {
                crf: 12,
                max_bitrate: 20_000_000,
                max_dimension: 2160,
                max_fps: 60.0,
            },
            Self::LowBandwidth => QualityPreset {
                crf: 30,
                max_bitrate: 800_000,
                max_dimension: 480,
                max_fps: 24.0,
            },
        }
    }

    /// Prefer hardware encoders for mobile-style presets when on phone SoCs.
    pub fn prefer_hardware(self) -> bool {
        !matches!(self, Self::Lossless)
    }
}

impl Vq {
    pub fn as_compression_preset(self) -> Option<CompressionPreset> {
        match self {
            Self::Low => Some(CompressionPreset::LowBandwidth),
            Self::Medium => Some(CompressionPreset::Standard),
            Self::High => Some(CompressionPreset::Youtube),
            Self::Custom => None,
            Self::Instagram => Some(CompressionPreset::Instagram),
            Self::Whatsapp => Some(CompressionPreset::Whatsapp),
            Self::Telegram => Some(CompressionPreset::Telegram),
            Self::Youtube => Some(CompressionPreset::Youtube),
            Self::Lossless => Some(CompressionPreset::Lossless),
        }
    }

    pub fn preset(self) -> QualityPreset {
        if let Some(p) = self.as_compression_preset() {
            return p.quality_preset();
        }
        match self {
            Self::Low => CompressionPreset::LowBandwidth.quality_preset(),
            Self::Medium => CompressionPreset::Standard.quality_preset(),
            Self::High => CompressionPreset::Youtube.quality_preset(),
            Self::Custom => QualityPreset {
                crf: 23,
                max_bitrate: 3_000_000,
                max_dimension: 1080,
                max_fps: 30.0,
            },
            Self::Instagram
            | Self::Whatsapp
            | Self::Telegram
            | Self::Youtube
            | Self::Lossless => unreachable!(),
        }
    }
}

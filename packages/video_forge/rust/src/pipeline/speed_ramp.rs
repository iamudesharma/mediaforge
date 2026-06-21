//! Clip playback speed for export (frame selection + output timeline).

use crate::types::SpeedSegment;

/// Controls which source frames are encoded and their output timeline position.
pub struct SpeedController {
    base_speed: f32,
    segments: Vec<SpeedSegment>,
    min_interval_ms: u64,
    last_output_ms: Option<u64>,
}

impl SpeedController {
    pub fn new(speed: f32, max_fps: Option<f32>, segments: Vec<SpeedSegment>) -> Self {
        let fps = max_fps.unwrap_or(30.0).max(1.0);
        let mut segs = segments;
        segs.sort_by_key(|s| s.start_ms);
        Self {
            base_speed: speed.clamp(0.25, 4.0),
            segments: segs,
            min_interval_ms: (1000.0 / fps as f64).max(1.0) as u64,
            last_output_ms: None,
        }
    }

    pub fn is_active(&self) -> bool {
        (self.base_speed - 1.0).abs() > 0.001 || !self.segments.is_empty()
    }

    fn rate_at(&self, local_ms: u64) -> f32 {
        for seg in &self.segments {
            if local_ms >= seg.start_ms && local_ms < seg.end_ms {
                return seg.rate.clamp(0.25, 4.0);
            }
        }
        self.base_speed
    }

    /// Map source time (clip-local ms) → output timeline ms by integrating piecewise rates.
    pub fn source_to_output_ms(&self, source_relative_ms: u64) -> u64 {
        if self.segments.is_empty() {
            return (source_relative_ms as f64 / self.base_speed as f64).round() as u64;
        }

        let mut output = 0u64;
        let mut cursor = 0u64;
        for seg in &self.segments {
            if cursor >= source_relative_ms {
                break;
            }
            if source_relative_ms <= seg.start_ms {
                let span = source_relative_ms.saturating_sub(cursor);
                output += (span as f64 / self.base_speed as f64).round() as u64;
                return output;
            }
            if cursor < seg.start_ms {
                let span = seg.start_ms.saturating_sub(cursor);
                output += (span as f64 / self.base_speed as f64).round() as u64;
                cursor = seg.start_ms;
            }
            let seg_end = seg.end_ms.min(source_relative_ms);
            if seg_end > cursor {
                let span = seg_end.saturating_sub(cursor);
                output += (span as f64 / seg.rate as f64).round() as u64;
                cursor = seg_end;
            }
        }
        if source_relative_ms > cursor {
            let span = source_relative_ms.saturating_sub(cursor);
            output += (span as f64 / self.base_speed as f64).round() as u64;
        }
        output
    }

    /// Returns output timeline ms when this source frame should be encoded.
    pub fn output_ms_for_encode(&mut self, source_relative_ms: u64) -> Option<u64> {
        if !self.is_active() {
            return Some(source_relative_ms);
        }
        let output_ms = self.source_to_output_ms(source_relative_ms);
        if let Some(last) = self.last_output_ms {
            if output_ms.saturating_sub(last) < self.min_interval_ms {
                return None;
            }
        }
        self.last_output_ms = Some(output_ms);
        Some(output_ms)
    }

    /// Output duration for a source span using base speed only (planning helper).
    pub fn output_duration_ms(source_duration_ms: u64, speed: f32) -> u64 {
        let s = speed.clamp(0.25, 4.0);
        ((source_duration_ms as f64) / s as f64).round() as u64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn double_speed_skips_frames() {
        let mut ctrl = SpeedController::new(2.0, Some(30.0), vec![]);
        assert!(ctrl.output_ms_for_encode(0).is_some());
        assert!(ctrl.output_ms_for_encode(16).is_none());
        let out = ctrl.output_ms_for_encode(67);
        assert!(out.is_some());
        assert_eq!(out.unwrap(), 34);
    }

    #[test]
    fn half_speed_doubles_duration() {
        assert_eq!(SpeedController::output_duration_ms(1000, 0.5), 2000);
    }

    #[test]
    fn speed_segment_overrides_middle() {
        let segs = vec![SpeedSegment {
            start_ms: 1000,
            end_ms: 2000,
            rate: 2.0,
        }];
        let ctrl = SpeedController::new(1.0, Some(30.0), segs);
        assert_eq!(ctrl.source_to_output_ms(500), 500);
        assert_eq!(ctrl.source_to_output_ms(1500), 1250);
        assert_eq!(ctrl.source_to_output_ms(2500), 2000);
    }
}

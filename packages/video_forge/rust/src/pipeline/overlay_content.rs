//! Category 2 text content animation — visible substring / reveal progress.

use crate::types::TextContentAnimation;

/// Progress 0–1 for content animation at `local_ms`.
pub fn content_reveal_progress(
    animation: TextContentAnimation,
    local_ms: u64,
    duration_ms: u64,
) -> f32 {
    if animation == TextContentAnimation::None || duration_ms == 0 {
        return 1.0;
    }
    (local_ms as f32 / duration_ms as f32).clamp(0.0, 1.0)
}

/// Substring of [text] visible at [progress] for the given animation kind.
pub fn visible_text(text: &str, animation: TextContentAnimation, progress: f32) -> String {
    if progress >= 1.0 || animation == TextContentAnimation::None {
        return text.to_string();
    }
    if progress <= 0.0 {
        return String::new();
    }

    match animation {
        TextContentAnimation::None => text.to_string(),
        TextContentAnimation::Typewriter => {
            let total = text.chars().count();
            let n = (total as f32 * progress).ceil() as usize;
            text.chars().take(n).collect()
        }
        TextContentAnimation::WordReveal => {
            let words: Vec<&str> = text.split_whitespace().collect();
            if words.is_empty() {
                return String::new();
            }
            let n = (words.len() as f32 * progress).ceil().max(1.0) as usize;
            words.iter().take(n).copied().collect::<Vec<_>>().join(" ")
        }
        TextContentAnimation::CharacterStagger => {
            let chars: Vec<char> = text.chars().collect();
            if chars.is_empty() {
                return String::new();
            }
            let n = (chars.len() as f32 * progress).floor() as usize;
            chars.into_iter().take(n).collect()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typewriter_partial() {
        let s = visible_text("Hello", TextContentAnimation::Typewriter, 0.4);
        assert_eq!(s, "He");
    }

    #[test]
    fn word_reveal() {
        let s = visible_text(
            "one two three",
            TextContentAnimation::WordReveal,
            0.5,
        );
        assert_eq!(s, "one two");
    }
}

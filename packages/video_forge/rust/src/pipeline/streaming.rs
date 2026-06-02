//! MP4 mux flags for streaming-friendly output.

use crate::types::OutputProfile;

/// PR #4: legacy `movflags(bool, bool)` helper, kept for one release
/// to give existing call sites a deprecation window. New code should
/// use [movflags_for_profile].
pub fn movflags(fast_start: bool, fragmented: bool) -> String {
    let mut flags = Vec::new();
    if fast_start {
        flags.push("+faststart");
    }
    if fragmented {
        flags.push("+frag_keyframe");
        flags.push("+empty_moov");
        flags.push("+default_base_moof");
    }
    flags.join("")
}

/// MP4 movflags for a given [OutputProfile]. Returns the empty string
/// for HLS (HLS uses different option names: `hls_segment_type`,
/// `hls_time`, `hls_playlist_type`).
///
/// Examples:
/// - `ProgressiveMp4 { fast_start: true }` -> `+faststart`
/// - `ProgressiveMp4 { fast_start: false }` -> ``
/// - `FragmentedMp4 { fragment_duration_ms: 2000 }` ->
///   `+frag_keyframe+frag_duration_ms=2000`
pub fn movflags_for_profile(profile: &OutputProfile) -> String {
    match profile {
        OutputProfile::ProgressiveMp4 { fast_start } => {
            if *fast_start {
                "+faststart".to_string()
            } else {
                String::new()
            }
        }
        OutputProfile::FragmentedMp4 {
            fragment_duration_ms,
        } => {
            // `+frag_keyframe` so each fragment starts on a keyframe
            // (the default is frag-every-frame which produces lots of
            // tiny fragments). `+empty_moov` avoids writing a moov
            // header before the first fragment (CMAF / DASH friendly).
            // `+frag_duration_ms` is the lower bound for fragment
            // length; FFmpeg rounds up to the next keyframe.
            format!("+frag_keyframe+empty_moov+frag_duration_ms={fragment_duration_ms}")
        }
        // HLS uses its own option set (see [hls_options]).
        OutputProfile::Hls { .. } => String::new(),
    }
}

/// FFmpeg muxer / format options for the HLS profile. Returns a
/// `Vec<(name, value)>` suitable for `octx.set_options(...)` or
/// `format::output_with(...)`. The caller is responsible for
/// attaching the `Output` and writing the playlist/segments.
pub fn hls_options(profile: &OutputProfile) -> Vec<(&'static str, String)> {
    let OutputProfile::Hls {
        segment_duration_ms,
        master_playlist,
        hls_version,
    } = profile
    else {
        return Vec::new();
    };
    let mut opts = vec![
        ("hls_time", segment_duration_ms.to_string()),
        ("hls_playlist_type", "vod".to_string()),
        ("hls_segment_type", "mpegts".to_string()),
        ("hls_version", hls_version.to_string()),
    ];
    if *master_playlist {
        // FFmpeg does not auto-generate a master.m3u8 with a single
        // rendition. We instead expose `hls_master_pl_url` so the
        // caller can build a master playlist from this output's
        // bandwidth metadata. The kit can layer a 1-rendition master
        // on top.
        opts.push(("master_pl_url", "master.m3u8".to_string()));
    }
    opts
}

/// True if the output is a fragmented or live-streaming container
/// (HLS / fMP4). When true, the encoder must keep `set_gop` aligned
/// to the fragment / segment length, otherwise the demuxer on the
/// receiving end cannot keyframe-align.
pub fn requires_gop_alignment(profile: &OutputProfile) -> bool {
    matches!(
        profile,
        OutputProfile::FragmentedMp4 { .. } | OutputProfile::Hls { .. }
    )
}

/// Recommended GOP (keyframe interval) in milliseconds for streaming
/// outputs. For fMP4 this is the fragment length; for HLS it is the
/// segment length (so each segment starts with a keyframe).
pub fn recommended_keyint_ms(profile: &OutputProfile) -> u32 {
    match profile {
        OutputProfile::FragmentedMp4 {
            fragment_duration_ms,
        } => *fragment_duration_ms,
        OutputProfile::Hls {
            segment_duration_ms,
            ..
        } => *segment_duration_ms,
        OutputProfile::ProgressiveMp4 { .. } => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn faststart_flag() {
        assert!(movflags(true, false).contains("faststart"));
    }

    #[test]
    fn fragmented_flags() {
        let f = movflags(false, true);
        assert!(f.contains("frag_keyframe"));
        assert!(f.contains("empty_moov"));
    }

    #[test]
    fn progressive_faststart() {
        let f = movflags_for_profile(&OutputProfile::ProgressiveMp4 { fast_start: true });
        assert_eq!(f, "+faststart");
    }

    #[test]
    fn progressive_no_faststart() {
        let f = movflags_for_profile(&OutputProfile::ProgressiveMp4 { fast_start: false });
        assert!(f.is_empty());
    }

    #[test]
    fn fragmented_flags_for_profile() {
        let f = movflags_for_profile(&OutputProfile::FragmentedMp4 {
            fragment_duration_ms: 2000,
        });
        assert!(f.contains("frag_keyframe"));
        assert!(f.contains("frag_duration_ms=2000"));
    }

    #[test]
    fn hls_movflags_is_empty() {
        let f = movflags_for_profile(&OutputProfile::Hls {
            segment_duration_ms: 6000,
            master_playlist: false,
            hls_version: 6,
        });
        assert!(f.is_empty(), "HLS uses hls_* options, not movflags");
    }

    #[test]
    fn hls_options_basic() {
        let opts = hls_options(&OutputProfile::Hls {
            segment_duration_ms: 4000,
            master_playlist: false,
            hls_version: 6,
        });
        let map: std::collections::HashMap<_, _> =
            opts.iter().map(|(k, v)| (*k, v.clone())).collect();
        assert_eq!(map.get("hls_time").unwrap(), "4000");
        assert_eq!(map.get("hls_playlist_type").unwrap(), "vod");
        assert_eq!(map.get("hls_segment_type").unwrap(), "mpegts");
        assert_eq!(map.get("hls_version").unwrap(), "6");
        assert!(!map.contains_key("master_pl_url"));
    }

    #[test]
    fn hls_options_with_master_playlist() {
        let opts = hls_options(&OutputProfile::Hls {
            segment_duration_ms: 6000,
            master_playlist: true,
            hls_version: 6,
        });
        assert!(opts.iter().any(|(k, _)| *k == "master_pl_url"));
    }

    #[test]
    fn requires_gop_alignment_for_streaming() {
        assert!(!requires_gop_alignment(&OutputProfile::ProgressiveMp4 {
            fast_start: true
        }));
        assert!(requires_gop_alignment(&OutputProfile::FragmentedMp4 {
            fragment_duration_ms: 2000
        }));
        assert!(requires_gop_alignment(&OutputProfile::Hls {
            segment_duration_ms: 6000,
            master_playlist: false,
            hls_version: 6
        }));
    }

    #[test]
    fn recommended_keyint_for_streaming() {
        assert_eq!(
            recommended_keyint_ms(&OutputProfile::FragmentedMp4 {
                fragment_duration_ms: 2000
            }),
            2000
        );
        assert_eq!(
            recommended_keyint_ms(&OutputProfile::Hls {
                segment_duration_ms: 6000,
                master_playlist: false,
                hls_version: 6
            }),
            6000
        );
        assert_eq!(
            recommended_keyint_ms(&OutputProfile::ProgressiveMp4 {
                fast_start: true
            }),
            0
        );
    }
}

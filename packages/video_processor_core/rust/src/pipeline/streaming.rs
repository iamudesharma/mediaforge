/// MP4 mux flags for streaming-friendly output.

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
}

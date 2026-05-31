//! Short-lived cache for remote [MediaInfo] probes (avoids repeated HTTP opens).

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use crate::ffmpeg::normalize_remote_input;
use crate::types::MediaInfo;

const TTL: Duration = Duration::from_secs(60);

static CACHE: LazyLock<Mutex<HashMap<String, (Instant, MediaInfo)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn get(url: &str) -> Option<MediaInfo> {
    let key = normalize_remote_input(url);
    let mut map = CACHE.lock().expect("probe cache");
    let (inserted, info) = map.get(&key)?;
    if inserted.elapsed() > TTL {
        map.remove(&key);
        return None;
    }
    Some(info.clone())
}

pub fn insert(url: &str, info: MediaInfo) {
    let key = normalize_remote_input(url);
    CACHE
        .lock()
        .expect("probe cache")
        .insert(key, (Instant::now(), info));
}

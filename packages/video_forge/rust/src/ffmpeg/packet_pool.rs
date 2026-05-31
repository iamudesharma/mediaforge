//! Reusable [Packet] buffers for encoder drain paths (reduces alloc/ref churn).

use ffmpeg_next::Packet;

const DEFAULT_CAPACITY: usize = 8;

/// Small pool of empty FFmpeg packets.
pub struct PacketPool {
    free: Vec<Packet>,
    capacity: usize,
}

impl PacketPool {
    pub fn new(capacity: usize) -> Self {
        let cap = capacity.max(1);
        Self {
            free: (0..cap).map(|_| Packet::empty()).collect(),
            capacity: cap,
        }
    }

    pub fn with_default_capacity() -> Self {
        Self::new(DEFAULT_CAPACITY)
    }

    pub fn acquire(&mut self) -> Packet {
        self.free.pop().unwrap_or_else(Packet::empty)
    }

    pub fn release(&mut self, packet: Packet) {
        if self.free.len() < self.capacity {
            self.free.push(packet);
        }
    }
}

impl Default for PacketPool {
    fn default() -> Self {
        Self::with_default_capacity()
    }
}

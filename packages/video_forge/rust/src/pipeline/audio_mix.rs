//! Streaming/chunked audio mix + AAC encode for export (bounded memory).

use ffmpeg_next::codec::{
    self, context::Context as CodecContext, encoder::audio::Encoder as AudioEncoder, Id,
};
use ffmpeg_next::format::{self, context::Output, sample::Type as SampleType};
use ffmpeg_next::software::resampling::Context as Resampler;
use ffmpeg_next::util::frame::audio::Audio;
use ffmpeg_next::util::format::sample::Sample;
use ffmpeg_next::util::rational::Rational;
use ffmpeg_next::{encoder, media, ChannelLayout, Packet};

use crate::error::{Result, VideoProcessorError};
use crate::ffmpeg::interrupt::InterruptContext;
use crate::ffmpeg::{ensure_input_accessible, map_ffmpeg_error, open_input};
use crate::types::AudioTrackInput;

const OUTPUT_SAMPLE_RATE: u32 = 48_000;
const OUTPUT_CHANNELS: usize = 2;
const FRAME_SAMPLES: usize = 1024;

fn ms_to_samples(ms: u64, sample_rate: u32) -> u64 {
    ms.saturating_mul(sample_rate as u64) / 1000
}

fn samples_to_ms(samples: u64, sample_rate: u32) -> u64 {
    samples.saturating_mul(1000) / sample_rate as u64
}

pub struct MixedAudioOutput {
    pub stream_index: usize,
    encoder: AudioEncoder,
}

/// Adds an opened AAC audio stream to [octx] before `write_header`.
///
/// The encoder must be opened before `write_header` so MP4 gets the AAC
/// AudioSpecificConfig/extradata AVFoundation expects. Reconstructing the
/// encoder from stream parameters after the header can produce files that
/// FFmpeg decodes but AVPlayer opens silently.
pub fn add_aac_output_stream(octx: &mut Output) -> Result<MixedAudioOutput> {
    let codec = encoder::find(Id::AAC)
        .ok_or_else(|| VideoProcessorError::UnsupportedCodec("aac".into()))?;
    let enc_ctx = CodecContext::new_with_codec(codec);
    let mut encoder = enc_ctx.encoder().audio().map_err(map_ffmpeg_error)?;
    encoder.set_rate(OUTPUT_SAMPLE_RATE as i32);
    encoder.set_channel_layout(ChannelLayout::STEREO);
    encoder.set_format(Sample::F32(SampleType::Planar));
    encoder.set_bit_rate(192_000);
    encoder.set_time_base(Rational(1, OUTPUT_SAMPLE_RATE as i32));

    if octx.format().flags().contains(format::Flags::GLOBAL_HEADER) {
        encoder.set_flags(codec::Flags::GLOBAL_HEADER);
    }
    let encoder = encoder.open_as(codec).map_err(map_ffmpeg_error)?;

    let mut ost = octx.add_stream(codec).map_err(map_ffmpeg_error)?;
    ost.set_parameters(&encoder);
    ost.set_time_base(Rational(1, OUTPUT_SAMPLE_RATE as i32));
    Ok(MixedAudioOutput {
        stream_index: ost.index(),
        encoder,
    })
}

struct ChunkedAudioDecoder {
    ictx: format::context::Input,
    stream_index: usize,
    decoder: ffmpeg_next::decoder::Audio,
    resampler: Resampler,
    pending: Vec<f32>,
    exhausted: bool,
}

impl ChunkedAudioDecoder {
    fn open(path: &str, seek_ms: u64) -> Result<Self> {
        ensure_input_accessible(path)?;
        let mut ictx = open_input(path)?;
        let stream = ictx
            .streams()
            .best(media::Type::Audio)
            .ok_or_else(|| VideoProcessorError::InvalidInput(format!("no audio in {path}")))?;
        let stream_index = stream.index();
        let params = stream.parameters();
        let dec_ctx = CodecContext::from_parameters(params).map_err(map_ffmpeg_error)?;
        let decoder = dec_ctx.decoder().audio().map_err(map_ffmpeg_error)?;
        let in_layout = decoder.channel_layout();
        let in_format = decoder.format();
        let resampler = Resampler::get(
            in_format,
            in_layout,
            decoder.rate(),
            Sample::F32(SampleType::Packed),
            ChannelLayout::STEREO,
            OUTPUT_SAMPLE_RATE,
        )
        .map_err(map_ffmpeg_error)?;

        if seek_ms > 0 {
            let tb = stream.time_base();
            let ts = (seek_ms as f64 / 1000.0 / tb.0 as f64 * tb.1 as f64) as i64;
            let _ = ictx.seek(ts, ..ts);
        }

        Ok(Self {
            ictx,
            stream_index,
            decoder,
            resampler,
            pending: Vec::new(),
            exhausted: false,
        })
    }

    fn ensure_samples(
        &mut self,
        count: usize,
        interrupt: &InterruptContext,
    ) -> Result<()> {
        while self.pending.len() < count && !self.exhausted {
            self.decode_more(interrupt)?;
        }
        Ok(())
    }

    fn push_resampled(&mut self, resampled: &Audio) {
        let nb = resampled.samples();
        if nb == 0 {
            return;
        }
        let data = resampled.data(0);
        let need = nb * OUTPUT_CHANNELS * std::mem::size_of::<f32>();
        if data.len() >= need {
            let slice = unsafe {
                std::slice::from_raw_parts(data.as_ptr() as *const f32, nb * OUTPUT_CHANNELS)
            };
            self.pending.extend_from_slice(slice);
        }
    }

    fn decode_more(&mut self, interrupt: &InterruptContext) -> Result<()> {
        let mut decoded = Audio::empty();
        let mut resampled = Audio::empty();
        loop {
            if interrupt.check() {
                return Err(VideoProcessorError::Cancelled);
            }

            if self.decoder.receive_frame(&mut decoded).is_ok() {
                self.resampler
                    .run(&decoded, &mut resampled)
                    .map_err(map_ffmpeg_error)?;
                self.push_resampled(&resampled);
                return Ok(());
            }

            let mut got = false;
            for (stream, packet) in self.ictx.packets() {
                if interrupt.check() {
                    return Err(VideoProcessorError::Cancelled);
                }
                if stream.index() != self.stream_index {
                    continue;
                }
                got = true;
                self.decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;
                break;
            }
            if !got {
                self.decoder.send_eof().map_err(map_ffmpeg_error)?;
                self.exhausted = true;
                if self.decoder.receive_frame(&mut decoded).is_ok() {
                    self.resampler
                        .run(&decoded, &mut resampled)
                        .map_err(map_ffmpeg_error)?;
                    self.push_resampled(&resampled);
                }
                return Ok(());
            }
        }
    }

    fn pop_stereo_frame(&mut self) -> Option<[f32; 2]> {
        if self.pending.len() < OUTPUT_CHANNELS {
            return None;
        }
        let l = self.pending[0];
        let r = self.pending[1];
        self.pending.drain(..OUTPUT_CHANNELS);
        Some([l, r])
    }
}

struct MixLane {
    timeline_start_ms: u64,
    timeline_end_ms: u64,
    volume: f32,
    decoder: ChunkedAudioDecoder,
}

impl MixLane {
    fn from_track(track: &AudioTrackInput, output_duration_ms: u64) -> Result<Option<Self>> {
        if track.muted {
            return Ok(None);
        }
        let timeline_start_ms = track.timeline_start_ms;
        let duration_ms = track
            .duration_ms
            .min(output_duration_ms.saturating_sub(timeline_start_ms));
        if duration_ms == 0 {
            return Ok(None);
        }
        let timeline_end_ms = timeline_start_ms.saturating_add(duration_ms);
        let decoder = ChunkedAudioDecoder::open(&track.source_path, track.source_start_ms)?;
        Ok(Some(Self {
            timeline_start_ms,
            timeline_end_ms,
            volume: track.volume.clamp(0.0, 1.0),
            decoder,
        }))
    }

    fn contributes_at_ms(&self, out_ms: u64) -> bool {
        out_ms >= self.timeline_start_ms && out_ms < self.timeline_end_ms
    }
}

/// Encode mixed audio into an existing AAC output stream (after video packets are written).
pub fn write_mixed_audio(
    octx: &mut Output,
    output: &mut MixedAudioOutput,
    video_input: &str,
    clip_start_ms: u64,
    output_duration_ms: u64,
    include_original: bool,
    tracks: &[AudioTrackInput],
    interrupt: &InterruptContext,
) -> Result<()> {
    if output_duration_ms == 0 {
        return Ok(());
    }

    let sample_rate = OUTPUT_SAMPLE_RATE;
    let total_out_samples = ms_to_samples(output_duration_ms, sample_rate);

    let mut lanes: Vec<MixLane> = Vec::new();
    if include_original {
        if let Ok(decoder) = ChunkedAudioDecoder::open(video_input, clip_start_ms) {
            lanes.push(MixLane {
                timeline_start_ms: 0,
                timeline_end_ms: output_duration_ms,
                volume: 1.0,
                decoder,
            });
        } else {
            log::warn!("export: no decodable original audio in {video_input}");
        }
    }
    for track in tracks {
        if let Some(lane) = MixLane::from_track(track, output_duration_ms)? {
            lanes.push(lane);
        }
    }

    if lanes.is_empty() {
        return Err(VideoProcessorError::InvalidInput(
            "no audio lanes to mix".into(),
        ));
    }

    let ost = octx
        .stream(output.stream_index)
        .ok_or_else(|| VideoProcessorError::FfmpegError("missing audio out stream".into()))?;
    let time_base = ost.time_base();
    let encoder = &mut output.encoder;

    let mut out_frame = Audio::empty();
    out_frame.set_rate(OUTPUT_SAMPLE_RATE);
    out_frame.set_channel_layout(ChannelLayout::STEREO);
    out_frame.set_format(Sample::F32(SampleType::Planar));

    let mut out_sample_cursor: u64 = 0;
    let mut pts_samples: i64 = 0;

    while out_sample_cursor < total_out_samples {
        if interrupt.check() {
            return Err(VideoProcessorError::Cancelled);
        }

        let chunk_samples =
            FRAME_SAMPLES.min((total_out_samples - out_sample_cursor) as usize);
        let mut mix_l = vec![0.0f32; chunk_samples];
        let mut mix_r = vec![0.0f32; chunk_samples];

        for sample_i in 0..chunk_samples {
            let out_pos = out_sample_cursor + sample_i as u64;
            let out_ms = samples_to_ms(out_pos, sample_rate);
            for lane in lanes.iter_mut() {
                if !lane.contributes_at_ms(out_ms) {
                    continue;
                }
                lane.decoder
                    .ensure_samples(OUTPUT_CHANNELS, interrupt)?;
                if let Some([l, r]) = lane.decoder.pop_stereo_frame() {
                    let vol = lane.volume;
                    mix_l[sample_i] += l * vol;
                    mix_r[sample_i] += r * vol;
                }
            }
        }

        unsafe {
            out_frame.alloc(
                Sample::F32(SampleType::Planar),
                chunk_samples,
                ChannelLayout::STEREO,
            );
            out_frame.set_samples(chunk_samples);
        }
        let bytes = chunk_samples * std::mem::size_of::<f32>();

        let line_size = unsafe { (*out_frame.as_ptr()).linesize[0] as usize };
        if line_size >= bytes {
            unsafe {
                let frame_ptr = out_frame.as_mut_ptr();
                std::ptr::copy_nonoverlapping(
                    mix_l.as_ptr() as *const u8,
                    (*frame_ptr).data[0],
                    bytes,
                );
                std::ptr::copy_nonoverlapping(
                    mix_r.as_ptr() as *const u8,
                    (*frame_ptr).data[1],
                    bytes,
                );
            }
        }

        out_frame.set_pts(Some(pts_samples));
        pts_samples += chunk_samples as i64;
        out_sample_cursor += chunk_samples as u64;

        encoder.send_frame(&out_frame).map_err(map_ffmpeg_error)?;
        let mut packet = Packet::empty();
        while encoder.receive_packet(&mut packet).is_ok() {
            packet.set_stream(output.stream_index);
            packet.rescale_ts(Rational(1, OUTPUT_SAMPLE_RATE as i32), time_base);
            packet.write_interleaved(octx).map_err(map_ffmpeg_error)?;
        }
    }

    encoder.send_eof().map_err(map_ffmpeg_error)?;
    let mut packet = Packet::empty();
    while encoder.receive_packet(&mut packet).is_ok() {
        packet.set_stream(output.stream_index);
        packet.rescale_ts(Rational(1, OUTPUT_SAMPLE_RATE as i32), time_base);
        packet.write_interleaved(octx).map_err(map_ffmpeg_error)?;
    }

    Ok(())
}

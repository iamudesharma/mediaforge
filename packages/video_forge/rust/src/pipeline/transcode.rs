use std::collections::HashMap;
use std::path::{Path, PathBuf};

use ffmpeg_next::codec::{self, context::Context as CodecContext, Id};
use ffmpeg_next::format::{self, Pixel};
use ffmpeg_next::software::scaling::{context::Context as ScalerContext, flag::Flags};
use ffmpeg_next::util::frame::video::Video;
use ffmpeg_next::{media, picture, Dictionary, Rational};

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::hw::{
    encoder_candidates_burn_in, encoder_candidates_with_hw, is_hardware_encoder,
};
use crate::ffmpeg::{
    apply_video_decoder_threading, ensure_ffmpeg_initialized, ensure_input_accessible,
    is_remote_input, map_ffmpeg_error, open_input, open_video_decoder, HwFrameTransfer,
    InterruptContext, PacketPool, VtLinkMode,
};
#[cfg(any(target_os = "ios", target_os = "macos"))]
use crate::ffmpeg::vt_pipeline::{self, VtScaler};
use crate::jobs::progress::ProgressReporter;
use crate::jobs::registry::CancellationToken;
use crate::pipeline::audio_mix;
use crate::pipeline::overlay_burn::OverlayCompositor;
use crate::pipeline::streaming::{movflags, movflags_for_profile};
use crate::types::{effective_output_profile, CompressOptions, CompressResult, VideoCodec};

/// Never target more than ~82% of measured source video bitrate when compressing.
const SOURCE_BITRATE_SHRINK: f64 = 0.82;
const MIN_TARGET_BITRATE_BPS: u64 = 150_000;

fn pts_to_ms(pts: i64, tb: Rational) -> u64 {
    if tb.0 == 0 || tb.1 == 0 {
        return 0;
    }
    ((pts as f64 * 1000.0 * tb.0 as f64 / tb.1 as f64).max(0.0)) as u64
}

fn ms_to_seek_ts(ms: u64, tb: Rational) -> i64 {
    if tb.0 == 0 || tb.1 == 0 {
        return 0;
    }
    (ms as f64 / 1000.0 / tb.0 as f64 * tb.1 as f64) as i64
}

struct VideoTranscoder {
    ost_index: usize,
    decoder: ffmpeg_next::decoder::Video,
    encoder: ffmpeg_next::encoder::Video,
    scaler: Option<ScalerContext>,
    scaler_src_w: u32,
    scaler_src_h: u32,
    enc_pixel: Pixel,
    out_w: u32,
    out_h: u32,
    scale_needed: bool,
    hw_transfer: Option<HwFrameTransfer>,
    input_time_base: Rational,
    frame_count: u64,
    encoder_name: String,
    is_hardware: bool,
    hw_decode: bool,
    vt_link: VtLinkMode,
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    vt_scaler: Option<VtScaler>,
    max_fps: Option<f32>,
    last_encoded_ms: Option<u64>,
    clip_end_ms: Option<u64>,
    stop_encoding: bool,
    burn_in: Option<OverlayCompositor>,
    /// After CPU overlay burn (YUV420P), convert to encoder pixel format (e.g. NV12 for MediaCodec).
    burn_submit_scaler: Option<ScalerContext>,
    burn_submit_frame: Video,
}

fn describe_pipeline_mode(
    vt_link: VtLinkMode,
    hw_decode: bool,
    scale_needed: bool,
) -> String {
    match vt_link {
        VtLinkMode::ZeroCopy => "vt_zero_copy".into(),
        VtLinkMode::GpuScale => "vt_gpu_scale".into(),
        VtLinkMode::None => {
            if hw_decode && scale_needed {
                "hw_decode+swscale".into()
            } else if hw_decode {
                "hw_decode".into()
            } else if scale_needed {
                "sw_decode+swscale".into()
            } else {
                "sw_decode".into()
            }
        }
    }
}

impl VideoTranscoder {
    fn pipeline_mode(&self) -> String {
        describe_pipeline_mode(self.vt_link, self.hw_decode, self.scale_needed)
    }
    fn should_drop_frame(&mut self, frame_ms: u64) -> bool {
        let Some(max_fps) = self.max_fps else {
            return false;
        };
        let min_interval_ms = (1000.0 / max_fps as f64).max(1.0) as u64;
        if let Some(last) = self.last_encoded_ms {
            if frame_ms.saturating_sub(last) < min_interval_ms {
                return true;
            }
        }
        self.last_encoded_ms = Some(frame_ms);
        false
    }

    fn past_clip_end(&self, frame_ms: u64) -> bool {
        self.clip_end_ms
            .is_some_and(|end| frame_ms > end)
    }
    fn drain_encoder(
        &mut self,
        octx: &mut format::context::Output,
        ost_time_base: Rational,
        packet_pool: &mut PacketPool,
    ) -> Result<()> {
        let mut packet = packet_pool.acquire();
        while self.encoder.receive_packet(&mut packet).is_ok() {
            packet.set_stream(self.ost_index);
            packet.rescale_ts(self.input_time_base, ost_time_base);
            packet.write_interleaved(octx).map_err(map_ffmpeg_error)?;
        }
        packet_pool.release(packet);
        Ok(())
    }

    fn ensure_scaler(&mut self, src: &Video) -> Result<()> {
        if !self.scale_needed {
            return Ok(());
        }
        let src_w = src.width();
        let src_h = src.height();
        if self.scaler.is_some() && self.scaler_src_w == src_w && self.scaler_src_h == src_h {
            return Ok(());
        }
        self.scaler = Some(
            ScalerContext::get(
                src.format(),
                src_w,
                src_h,
                self.enc_pixel,
                self.out_w,
                self.out_h,
                Flags::FAST_BILINEAR,
            )
            .map_err(map_ffmpeg_error)?,
        );
        self.scaler_src_w = src_w;
        self.scaler_src_h = src_h;
        Ok(())
    }

    fn ensure_scaled_frame(&self, scaled: &mut Video) -> Result<()> {
        if scaled.width() == self.out_w
            && scaled.height() == self.out_h
            && scaled.format() == self.enc_pixel
        {
            return Ok(());
        }
        unsafe {
            scaled.alloc(self.enc_pixel, self.out_w, self.out_h);
        }
        Ok(())
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    fn send_vt_gpu_scaled(
        &mut self,
        src: &mut Video,
        octx: &mut format::context::Output,
        ost_time_base: Rational,
        packet_pool: &mut PacketPool,
    ) -> Result<()> {
        let vt = self
            .vt_scaler
            .as_mut()
            .ok_or_else(|| VideoForgeError::Internal("VT scaler missing".into()))?;
        vt.transfer_from(src)?;
        let out = vt.output_frame();
        let pts = out.timestamp();
        out.set_pts(pts);
        out.set_kind(picture::Type::None);
        self.encoder.send_frame(out).map_err(map_ffmpeg_error)?;
        self.drain_encoder(octx, ost_time_base, packet_pool)
    }

    fn send_to_encoder(
        &mut self,
        src: &mut Video,
        frame_ms: u64,
        octx: &mut format::context::Output,
        ost_time_base: Rational,
        scaled: &mut Video,
        packet_pool: &mut PacketPool,
    ) -> Result<()> {
        let pts = src.timestamp();
        src.set_pts(pts);
        src.set_kind(picture::Type::None);

        if self.scale_needed {
            self.ensure_scaler(src)?;
            self.ensure_scaled_frame(scaled)?;
            let s = self.scaler.as_mut().expect("scaler");
            s.run(src, scaled).map_err(map_ffmpeg_error)?;
            scaled.set_pts(pts);
            scaled.set_kind(picture::Type::None);
            if let Some(comp) = &mut self.burn_in {
                comp.apply_on_yuv420(scaled, frame_ms)?;
            }
            self.send_yuv420_to_encoder(scaled, octx, ost_time_base, packet_pool)?;
        } else {
            if let Some(comp) = &mut self.burn_in {
                comp.apply_on_yuv420(src, frame_ms)?;
            }
            self.send_yuv420_to_encoder(src, octx, ost_time_base, packet_pool)?;
        }
        Ok(())
    }

    /// Submit a YUV420P frame (after optional overlay burn) to the encoder, converting pixel
    /// format when the encoder expects NV12 (Android MediaCodec).
    fn send_yuv420_to_encoder(
        &mut self,
        yuv420: &mut Video,
        octx: &mut format::context::Output,
        ost_time_base: Rational,
        packet_pool: &mut PacketPool,
    ) -> Result<()> {
        if let Some(s) = &mut self.burn_submit_scaler {
            s.run(yuv420, &mut self.burn_submit_frame)
                .map_err(map_ffmpeg_error)?;
            let pts = yuv420.timestamp();
            self.burn_submit_frame.set_pts(pts);
            self.burn_submit_frame.set_kind(picture::Type::None);
            self.encoder
                .send_frame(&mut self.burn_submit_frame)
                .map_err(map_ffmpeg_error)?;
        } else {
            self.encoder.send_frame(yuv420).map_err(map_ffmpeg_error)?;
        }
        self.drain_encoder(octx, ost_time_base, packet_pool)
    }

    fn process_decoded(
        &mut self,
        frame: &mut Video,
        frame_ms: u64,
        octx: &mut format::context::Output,
        ost_time_base: Rational,
        scaled: &mut Video,
        packet_pool: &mut PacketPool,
    ) -> Result<()> {
        #[cfg(any(target_os = "ios", target_os = "macos"))]
        if self.burn_in.is_none()
            && crate::ffmpeg::hw_decode::is_hw_pixel_format(frame.format())
        {
            match self.vt_link {
                VtLinkMode::ZeroCopy => {
                    return self.send_to_encoder(
                        frame,
                        frame_ms,
                        octx,
                        ost_time_base,
                        scaled,
                        packet_pool,
                    );
                }
                VtLinkMode::GpuScale => {
                    return self.send_vt_gpu_scaled(frame, octx, ost_time_base, packet_pool);
                }
                VtLinkMode::None => {}
            }
        }

        if let Some(hw) = &self.hw_transfer {
            if crate::ffmpeg::hw_decode::is_hw_pixel_format(frame.format()) {
                let mut sw = Video::empty();
                hw.transfer_to_sw(frame, &mut sw)?;
                return self.send_to_encoder(
                    &mut sw,
                    frame_ms,
                    octx,
                    ost_time_base,
                    scaled,
                    packet_pool,
                );
            }
        }
        self.send_to_encoder(
            frame,
            frame_ms,
            octx,
            ost_time_base,
            scaled,
            packet_pool,
        )
    }
}

pub fn run_compress(
    options: CompressOptions,
    token: CancellationToken,
    progress: &mut ProgressReporter,
) -> Result<CompressResult> {
    ensure_ffmpeg_initialized()?;

    let input = options.input_path.trim();
    ensure_input_accessible(input)?;

    let output_path = resolve_output_path(input, options.output_path.as_deref())?;
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| VideoForgeError::IoError(e.to_string()))?;
    }

    // Remove stale partial output from a previous failed run.
    if output_path.exists() {
        let _ = std::fs::remove_file(&output_path);
    }

    let result = run_compress_inner(&options, input, &output_path, &token, progress);

    if result.is_err() && output_path.exists() {
        let _ = std::fs::remove_file(&output_path);
    }

    result
}

fn run_compress_inner(
    options: &CompressOptions,
    input: &str,
    output_path: &Path,
    token: &CancellationToken,
    progress: &mut ProgressReporter,
) -> Result<CompressResult> {
    progress.emit(
        crate::types::ProcessingPhase::Probing,
        0.0,
        0,
        0.0,
        0,
        true,
    );

    let preset = options.quality.preset();
    let crf = options.crf.unwrap_or(preset.crf);
    let max_w = options.max_width.unwrap_or(preset.max_dimension);
    let max_h = options.max_height.unwrap_or(preset.max_dimension);
    let preset_max_bitrate = preset.max_bitrate;

    let file_size = if is_remote_input(input) {
        0
    } else {
        std::fs::metadata(input)
            .map(|m| m.len())
            .unwrap_or(0)
    };

    let mut ictx = open_input(input)?;
    let mut octx = format::output(output_path).map_err(map_ffmpeg_error)?;

    let duration = ictx.duration().max(1) as f64;
    let clip_start_ms = options.start_ms.unwrap_or(0);
    let clip_end_ms = options.end_ms;
    let encode_span_ms = clip_end_ms
        .map(|end| end.saturating_sub(clip_start_ms).max(1))
        .unwrap_or_else(|| (duration / 1000.0).max(1.0) as u64);
    let interrupt = InterruptContext::new(token.clone());

    let nb_streams = ictx.nb_streams() as usize;
    let mut stream_mapping = vec![-1isize; nb_streams];
    let mut ist_time_bases = vec![Rational(0, 1); nb_streams];
    let mut ost_time_bases = vec![Rational(0, 1); nb_streams];
    let mut transcoders: HashMap<usize, VideoTranscoder> = HashMap::new();
    let mut ost_index = 0usize;

    // iPhone .mov files often have AAC + Apple spatial audio (apac) + metadata tracks.
    // Only process the primary video/audio streams FFmpeg can decode and mux.
    let best_video_index = ictx.streams().best(media::Type::Video).map(|s| s.index());
    let use_mixed_audio = !options.audio_tracks.is_empty();
    let stream_copy_audio = options.include_audio && !use_mixed_audio;
    let best_audio_index = if stream_copy_audio {
        ictx.streams().best(media::Type::Audio).map(|s| s.index())
    } else {
        None
    };
    let mut mixed_audio_output: Option<audio_mix::MixedAudioOutput> = None;

    for (ist_index, ist) in ictx.streams().enumerate() {
        let medium = ist.parameters().medium();
        if medium == media::Type::Video {
            if best_video_index != Some(ist_index) {
                continue;
            }
        } else if medium == media::Type::Audio {
            if best_audio_index != Some(ist_index) {
                continue;
            }
            if !audio_stream_is_copyable(&ist) {
                log::warn!(
                    "Skipping unsupported audio stream {} ({})",
                    ist_index,
                    ist.parameters().id().name()
                );
                continue;
            }
        } else {
            continue;
        }

        stream_mapping[ist_index] = ost_index as isize;
        ist_time_bases[ist_index] = ist.time_base();

        if medium == media::Type::Video {
            let target_bitrate = resolve_video_target_bitrate(
                &ictx,
                &ist,
                file_size,
                preset_max_bitrate,
                options.target_bitrate,
                max_w,
                max_h,
                best_audio_index,
            )?;
            let transcoder = create_video_transcoder(
                &ist,
                &mut octx,
                &options.codec,
                options.prefer_hardware_encoder,
                crf,
                target_bitrate,
                max_w,
                max_h,
                options.max_fps,
                clip_end_ms,
                &options.burn_in_overlays,
            )?;
            transcoders.insert(ist_index, transcoder);
        } else {
            // Stream-copy audio (no re-encode).
            let mut ost = octx
                .add_stream(ffmpeg_next::encoder::find(Id::None))
                .map_err(map_ffmpeg_error)?;
            ost.set_parameters(ist.parameters());
            unsafe {
                (*ost.parameters().as_mut_ptr()).codec_tag = 0;
            }
        }

        ost_index += 1;
    }

    if transcoders.is_empty() && best_audio_index.is_none() && options.audio_tracks.is_empty() {
        return Err(VideoForgeError::InvalidInput("no video or audio streams".into()));
    }

    if use_mixed_audio {
        mixed_audio_output = Some(audio_mix::add_aac_output_stream(&mut octx)?);
    }

    if clip_start_ms > 0 {
        if let Some(vidx) = best_video_index {
            let tb = ist_time_bases[vidx];
            let seek_ts = ms_to_seek_ts(clip_start_ms, tb);
            if ictx.seek(seek_ts, ..seek_ts).is_err() {
                log::warn!(
                    "compress seek to {clip_start_ms}ms failed; decoding from start"
                );
            }
        }
    }

    let mut header_opts = Dictionary::new();
    // PR #4: prefer [CompressOptions::output_profile] when set;
    // otherwise fall back to the legacy `fast_start` + `fragmented_mp4`
    // booleans (handled by `effective_output_profile`).
    let profile = effective_output_profile(options);
    let flags = movflags_for_profile(&profile);
    if !flags.is_empty() {
        header_opts.set("movflags", &flags);
    }
    // HLS does not use `movflags`; it uses the `hls_*` option family.
    // For the HLS profile we open the output as `hls` muxer so the
    // user-supplied output path is treated as a `.m3u8` playlist
    // prefix (FFmpeg writes `playlist0.ts`, `playlist1.ts`, ...
    // alongside).
    match &profile {
        crate::types::OutputProfile::Hls { .. } => {
            log::info!(
                "[Compress] HLS output profile active (segment_duration_ms={:?})",
                match &profile {
                    crate::types::OutputProfile::Hls {
                        segment_duration_ms,
                        ..
                    } => *segment_duration_ms,
                    _ => 0,
                }
            );
        }
        _ => {}
    }
    octx.write_header_with(header_opts)
        .map_err(map_ffmpeg_error)?;

    for (idx, _) in octx.streams().enumerate() {
        ost_time_bases[idx] = octx
            .stream(idx)
            .ok_or_else(|| VideoForgeError::FfmpegError(format!("missing output stream {idx}")))?
            .time_base();
    }

    progress.emit(
        crate::types::ProcessingPhase::Encoding,
        0.05,
        0,
        0.0,
        0,
        true,
    );

    let mut decoded = Video::empty();
    let mut scaled = Video::empty();
    let mut packet_pool = PacketPool::with_default_capacity();

    for (stream, packet) in ictx.packets() {
        if interrupt.check() {
            return Err(VideoForgeError::Cancelled);
        }

        let ist_index = stream.index();
        let mapped = stream_mapping[ist_index];
        if mapped < 0 {
            continue;
        }
        let ost_time_base = ost_time_bases[mapped as usize];

        if let Some(transcoder) = transcoders.get_mut(&ist_index) {
            if transcoder.stop_encoding {
                continue;
            }

            let pkt_ms = pts_to_ms(packet.pts().unwrap_or(0), ist_time_bases[ist_index]);
            if pkt_ms < clip_start_ms {
                continue;
            }
            if transcoder.past_clip_end(pkt_ms) {
                transcoder.stop_encoding = true;
                continue;
            }

            transcoder
                .decoder
                .send_packet(&packet)
                .map_err(map_ffmpeg_error)?;

            while transcoder.decoder.receive_frame(&mut decoded).is_ok() {
                if interrupt.check() {
                    return Err(VideoForgeError::Cancelled);
                }

                let frame_ms =
                    pts_to_ms(decoded.pts().unwrap_or(0), transcoder.input_time_base);
                if frame_ms < clip_start_ms {
                    continue;
                }
                if transcoder.past_clip_end(frame_ms) {
                    transcoder.stop_encoding = true;
                    break;
                }
                if transcoder.should_drop_frame(frame_ms) {
                    continue;
                }

                transcoder.frame_count += 1;
                let relative_ms = frame_ms.saturating_sub(clip_start_ms);
                let percent =
                    (relative_ms as f64 / encode_span_ms as f64).clamp(0.0, 0.95) as f32;
                progress.emit(
                    crate::types::ProcessingPhase::Encoding,
                    percent,
                    transcoder.frame_count,
                    0.0,
                    0,
                    false,
                );

                transcoder.process_decoded(
                    &mut decoded,
                    frame_ms,
                    &mut octx,
                    ost_time_base,
                    &mut scaled,
                    &mut packet_pool,
                )?;
            }
        } else {
            let pkt_ms = pts_to_ms(packet.pts().unwrap_or(0), ist_time_bases[ist_index]);
            if pkt_ms < clip_start_ms {
                continue;
            }
            if clip_end_ms.is_some_and(|end| pkt_ms > end) {
                continue;
            }

            let mut pkt = packet;
            pkt.rescale_ts(ist_time_bases[ist_index], ost_time_base);
            pkt.set_position(-1);
            pkt.set_stream(mapped as usize);
            pkt.write_interleaved(&mut octx).map_err(map_ffmpeg_error)?;
        }
    }

    // Flush video encoders/decoders.
    for (&ist_index, transcoder) in transcoders.iter_mut() {
        let mapped = stream_mapping[ist_index];
        if mapped < 0 {
            continue;
        }
        let ost_time_base = ost_time_bases[mapped as usize];
        let mut decoded = Video::empty();
        let mut scaled = Video::empty();

        transcoder.decoder.send_eof().map_err(map_ffmpeg_error)?;
        while transcoder.decoder.receive_frame(&mut decoded).is_ok() {
            let frame_ms =
                pts_to_ms(decoded.pts().unwrap_or(0), transcoder.input_time_base);
            transcoder.process_decoded(
                &mut decoded,
                frame_ms,
                &mut octx,
                ost_time_base,
                &mut scaled,
                &mut packet_pool,
            )?;
        }

        transcoder.encoder.send_eof().map_err(map_ffmpeg_error)?;
        transcoder.drain_encoder(&mut octx, ost_time_base, &mut packet_pool)?;
    }

    if let Some(mixed_audio) = mixed_audio_output.as_mut() {
        progress.emit(
            crate::types::ProcessingPhase::Encoding,
            0.96,
            0,
            0.0,
            0,
            true,
        );
        let include_original =
            options.include_audio && !options.mute_original_audio;
        audio_mix::write_mixed_audio(
            &mut octx,
            mixed_audio,
            input,
            clip_start_ms,
            encode_span_ms,
            include_original,
            &options.audio_tracks,
            &interrupt,
        )?;
    }

    progress.emit(
        crate::types::ProcessingPhase::Muxing,
        0.98,
        transcoders.values().map(|t| t.frame_count).sum(),
        0.0,
        0,
        true,
    );

    octx.write_trailer().map_err(map_ffmpeg_error)?;

    let file_size = std::fs::metadata(output_path)
        .map_err(|e| VideoForgeError::IoError(e.to_string()))?
        .len();

    if file_size < 1024 {
        return Err(VideoForgeError::FfmpegError(
            "output file too small — encode likely failed".into(),
        ));
    }

    let first = transcoders.values().next();
    let encoder_name = first
        .map(|t| t.encoder_name.clone())
        .unwrap_or_else(|| "unknown".into());
    let used_hw = first
        .map(|t| t.is_hardware || t.hw_decode)
        .unwrap_or(false);
    let pipeline_mode = first
        .map(|t| t.pipeline_mode())
        .unwrap_or_else(|| "unknown".into());

    let info =
        crate::pipeline::metadata::probe_media_info(output_path.to_string_lossy().as_ref())?;

    progress.done();

    Ok(CompressResult {
        output_path: output_path.to_string_lossy().into_owned(),
        duration_ms: info.duration_ms,
        file_size,
        used_hardware_acceleration: used_hw,
        encoder_name,
        pipeline_mode,
    })
}

fn create_video_transcoder(
    ist: &format::stream::Stream,
    octx: &mut format::context::Output,
    codec: &VideoCodec,
    prefer_hw: bool,
    crf: u8,
    target_bitrate: u64,
    max_w: u32,
    max_h: u32,
    max_fps: Option<f32>,
    clip_end_ms: Option<u64>,
    burn_in_specs: &[crate::types::BurnInOverlay],
) -> Result<VideoTranscoder> {
    let global_header = octx
        .format()
        .flags()
        .contains(format::flag::Flags::GLOBAL_HEADER);

    // Burn-in composites CPU YUV420P; HW decode/encode paths are unreliable for that pipeline.
    let burn_in_active = !burn_in_specs.is_empty();
    let prefer_hw_decode = !burn_in_active
        && prefer_hw
        && crate::ffmpeg::hw_decode::prefer_hw_decode_with_encode();
    let (mut decoder, mut hw_transfer) =
        open_video_decoder(ist.parameters(), prefer_hw_decode)?;
    let hw_decode = hw_transfer.is_some();

    let src_w = decoder.width();
    let src_h = decoder.height();
    let (out_w, out_h) = scale_dimensions(src_w, src_h, max_w, max_h);

    let candidates = if burn_in_active {
        let list = encoder_candidates_burn_in(codec);
        if list.is_empty() {
            return Err(VideoForgeError::UnsupportedCodec(format!(
                "burn-in export needs libx264/libx265 or a mobile hardware encoder (MediaCodec / VideoToolbox) for {codec:?}"
            )));
        }
        list
    } else {
        encoder_candidates_with_hw(codec, prefer_hw)
    };
    let mut last_err: Option<VideoForgeError> = None;
    let mut opened_pair: Option<(ffmpeg_next::encoder::Video, usize, String, VtLinkMode)> =
        None;

    for encoder_name in candidates {
        if ffmpeg_next::encoder::find_by_name(encoder_name).is_none() {
            continue;
        }
        match try_open_video_encoder(
            ist,
            octx,
            &mut decoder,
            encoder_name,
            out_w,
            out_h,
            global_header,
            crf,
            target_bitrate,
            is_hardware_encoder(encoder_name),
            hw_transfer.as_mut(),
            burn_in_active,
        ) {
            Ok((encoder, ost_idx, vt_mode)) => {
                opened_pair = Some((encoder, ost_idx, encoder_name.to_string(), vt_mode));
                break;
            }
            Err(e) => {
                log::warn!("encoder {encoder_name} failed: {e}; trying fallback");
                last_err = Some(e);
            }
        }
    }

    let (encoder, ost_idx, encoder_name, vt_link) = match opened_pair {
        Some(pair) => pair,
        None => {
            if let Some(e) = last_err {
                return Err(e);
            }
            if !prefer_hw && matches!(std::env::consts::OS, "android" | "ios") {
                return Err(VideoForgeError::UnsupportedCodec(format!(
                    "no encoder for {codec:?} (this mobile build has hardware encoders only; use preferHardwareEncoder: true)"
                )));
            }
            return Err(VideoForgeError::UnsupportedCodec(format!(
                "no encoder for {codec:?}"
            )));
        }
    };

    // MediaCodec encoders are configured on 16-aligned dimensions; scaler output must match.
    let (out_w, out_h) = if encoder_name.contains("mediacodec") {
        (align_even_16(out_w), align_even_16(out_h))
    } else {
        (out_w, out_h)
    };

    let burn_in = OverlayCompositor::new(burn_in_specs, out_w, out_h)?;

    let (burn_submit_scaler, burn_submit_frame) =
        setup_burn_in_submit_buffer(burn_in.as_ref(), &encoder, out_w, out_h)?;

    let (enc_pixel, scale_needed, vt_link) = if burn_in_active {
        (Pixel::YUV420P, true, VtLinkMode::None)
    } else if vt_link != VtLinkMode::None {
        (Pixel::VIDEOTOOLBOX, false, vt_link)
    } else if encoder_name.contains("mediacodec") {
        (Pixel::NV12, true, vt_link)
    } else {
        let sw_pixel = hw_transfer
            .as_ref()
            .map(|h| h.sw_format)
            .unwrap_or_else(|| decoder.format());
        let enc_pixel = Pixel::YUV420P;
        (
            enc_pixel,
            out_w != src_w || out_h != src_h || sw_pixel != enc_pixel,
            vt_link,
        )
    };

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    let vt_scaler = if vt_link == VtLinkMode::GpuScale {
        Some(VtScaler::new(
            hw_transfer
                .as_mut()
                .expect("VT gpu scale requires hw_transfer"),
            out_w,
            out_h,
        )?)
    } else {
        None
    };

    log::info!(
        "Opened video encoder: {encoder_name} (hw_decode={hw_decode}, hw_encode={}, vt_p3={vt_link:?})",
        is_hardware_encoder(&encoder_name),
    );

    Ok(VideoTranscoder {
        ost_index: ost_idx,
        decoder,
        encoder,
        scaler: None,
        scaler_src_w: 0,
        scaler_src_h: 0,
        enc_pixel,
        out_w,
        out_h,
        scale_needed,
        hw_transfer,
        input_time_base: ist.time_base(),
        frame_count: 0,
        encoder_name: encoder_name.to_string(),
        is_hardware: is_hardware_encoder(&encoder_name),
        hw_decode,
        vt_link,
        #[cfg(any(target_os = "ios", target_os = "macos"))]
        vt_scaler,
        max_fps,
        last_encoded_ms: None,
        clip_end_ms,
        stop_encoding: false,
        burn_in,
        burn_submit_scaler,
        burn_submit_frame,
    })
}

/// Overlay burn runs on YUV420P; MediaCodec encoders on Android expect NV12.
fn setup_burn_in_submit_buffer(
    burn_in: Option<&OverlayCompositor>,
    encoder: &ffmpeg_next::encoder::Video,
    out_w: u32,
    out_h: u32,
) -> Result<(Option<ScalerContext>, Video)> {
    if burn_in.is_none() {
        return Ok((None, Video::empty()));
    }
    let encoder_pix = encoder.format();
    if encoder_pix == Pixel::YUV420P {
        return Ok((None, Video::empty()));
    }
    log::info!(
        "burn-in submit: converting YUV420P → {:?} for encoder ({out_w}x{out_h})",
        encoder_pix
    );
    let mut submit = Video::empty();
    unsafe {
        submit.alloc(encoder_pix, out_w, out_h);
    }
    let scaler = ScalerContext::get(
        Pixel::YUV420P,
        out_w,
        out_h,
        encoder_pix,
        out_w,
        out_h,
        Flags::FAST_BILINEAR,
    )
    .map_err(map_ffmpeg_error)?;
    Ok((Some(scaler), submit))
}

fn align_even_16(v: u32) -> u32 {
    ((v + 15) / 16) * 16
}

fn decoder_frame_rate(decoder: &ffmpeg_next::decoder::Video) -> Rational {
    decoder.frame_rate().unwrap_or(Rational(30, 1))
}

fn try_open_video_encoder(
    ist: &format::stream::Stream,
    octx: &mut format::context::Output,
    decoder: &mut ffmpeg_next::decoder::Video,
    encoder_name: &str,
    out_w: u32,
    out_h: u32,
    global_header: bool,
    crf: u8,
    target_bitrate: u64,
    is_hw: bool,
    mut hw: Option<&mut HwFrameTransfer>,
    disable_vt_pipeline: bool,
) -> Result<(ffmpeg_next::encoder::Video, usize, VtLinkMode)> {
    let codec = ffmpeg_next::encoder::find_by_name(encoder_name)
        .ok_or_else(|| VideoForgeError::UnsupportedCodec(encoder_name.into()))?;

    let mut enc_ctx = CodecContext::new_with_codec(codec);

    let src_w = decoder.width();
    let src_h = decoder.height();

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    let vt_mode = if disable_vt_pipeline {
        VtLinkMode::None
    } else if is_hw
        && vt_pipeline::encoder_supports_vt_pipeline(encoder_name)
        && hw.is_some()
    {
        let hw = hw.as_mut().expect("hw");
        vt_pipeline::prepare_vt_link(hw, decoder, &mut enc_ctx, src_w, src_h, out_w, out_h)?
    } else {
        VtLinkMode::None
    };

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    let vt_mode = VtLinkMode::None;

    let mut encoder = enc_ctx.encoder().video().map_err(map_ffmpeg_error)?;

    if global_header {
        encoder.set_flags(codec::Flags::GLOBAL_HEADER);
    }

    let (out_w, out_h, enc_pixel) = if vt_mode != VtLinkMode::None {
        (out_w, out_h, Pixel::VIDEOTOOLBOX)
    } else if encoder_name.contains("mediacodec") {
        (
            align_even_16(out_w),
            align_even_16(out_h),
            Pixel::NV12,
        )
    } else {
        let needs_yuv = out_w != decoder.width()
            || out_h != decoder.height()
            || decoder.format() != Pixel::YUV420P;
        (
            out_w,
            out_h,
            if needs_yuv {
                Pixel::YUV420P
            } else {
                decoder.format()
            },
        )
    };

    encoder.set_width(out_w);
    encoder.set_height(out_h);
    encoder.set_aspect_ratio(decoder.aspect_ratio());
    encoder.set_format(enc_pixel);

    let frame_rate = decoder_frame_rate(decoder);
    encoder.set_frame_rate(Some(frame_rate));
    encoder.set_time_base(ist.time_base());
    encoder.set_bit_rate(target_bitrate as usize);
    if is_hw {
        // VideoToolbox uses rc_max_rate for DataRateLimits; keep cap aligned with target.
        encoder.set_max_bit_rate(target_bitrate as usize);
    }
    encoder.set_max_b_frames(0);

    let fps = frame_rate
        .numerator()
        .max(1) as u32
        / frame_rate.denominator().max(1) as u32;
    encoder.set_gop((fps * 2).max(12));

    let mut dict = Dictionary::new();
    if is_hw {
        dict.set("b", &target_bitrate.to_string());
        if encoder_name.contains("videotoolbox") {
            dict.set("realtime", "1");
            dict.set("allow_sw", "0");
        }
        if encoder_name.contains("mediacodec") {
            dict.set("bitrate", &target_bitrate.to_string());
            dict.set("bitrate_mode", "cbr");
        }
    } else if encoder_name == "libx264" || encoder_name == "libx265" {
        dict.set("crf", &crf.to_string());
        dict.set("preset", "medium");
        if target_bitrate > 0 {
            dict.set("maxrate", &target_bitrate.to_string());
            dict.set("bufsize", &(target_bitrate * 2).to_string());
        }
    } else {
        dict.set("b", &target_bitrate.to_string());
    }

    // Open before add_stream so failed HW attempts do not leave orphan output streams.
    let mut opened = encoder.open_with(dict).map_err(map_ffmpeg_error)?;

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    if vt_mode != VtLinkMode::None {
        if let Some(hw) = hw {
            vt_pipeline::finish_vt_encoder(&mut opened, hw, vt_mode, out_w, out_h)?;
        }
    }

    let mut ost = octx.add_stream(codec).map_err(map_ffmpeg_error)?;
    ost.set_parameters(&opened);

    Ok((opened, ost.index(), vt_mode))
}

pub fn resolve_output_path(input: &str, explicit: Option<&str>) -> Result<PathBuf> {
    if let Some(out) = explicit {
        return Ok(PathBuf::from(out));
    }
    if is_remote_input(input) {
        return Err(VideoForgeError::InvalidInput(
            "remote input requires an explicit output path".into(),
        ));
    }
    let path = Path::new(input);
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("output");
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    Ok(parent.join(format!("{stem}_compressed.mp4")))
}

/// True when the audio stream can be remuxed into MP4 (AAC, MP3, AC-3, etc.).
fn audio_stream_is_copyable(ist: &format::stream::Stream) -> bool {
    let id = ist.parameters().id();
    matches!(
        id,
        Id::AAC
            | Id::MP3
            | Id::AC3
            | Id::EAC3
            | Id::OPUS
            | Id::FLAC
            | Id::VORBIS
            | Id::PCM_S16LE
            | Id::PCM_S24LE
    )
}

fn codec_parameters_bit_rate(params: &ffmpeg_next::codec::Parameters) -> u64 {
    unsafe {
        let bps = (*params.as_ptr()).bit_rate;
        if bps > 0 {
            bps as u64
        } else {
            0
        }
    }
}

fn estimate_container_bitrate_bps(
    ictx: &format::context::Input,
    file_size: u64,
    duration_us: i64,
) -> u64 {
    let from_ctx = ictx.bit_rate();
    if from_ctx > 0 {
        return from_ctx as u64;
    }
    if file_size == 0 || duration_us <= 0 {
        return 0;
    }
    let duration_sec = duration_us as f64 / ffmpeg_next::ffi::AV_TIME_BASE as f64;
    if duration_sec <= 0.0 {
        return 0;
    }
    ((file_size as f64 * 8.0) / duration_sec).round() as u64
}

/// Target video bitrate for compression: never above preset/user caps, and never above
/// a fraction of measured source bitrate (fixes HW encoders bloating already-small files).
fn estimate_video_target_bitrate_bps(
    video_stream_bitrate: u64,
    container_bitrate: u64,
    audio_stream_bitrate: u64,
    preset_max_bitrate: u64,
    user_max_bitrate: Option<u64>,
    src_w: u32,
    src_h: u32,
    out_w: u32,
    out_h: u32,
) -> u64 {
    let mut ceiling = preset_max_bitrate;
    if let Some(user_bps) = user_max_bitrate {
        ceiling = ceiling.min(user_bps);
    }

    let source_video = if video_stream_bitrate > 0 {
        video_stream_bitrate
    } else if container_bitrate > 0 {
        container_bitrate.saturating_sub(audio_stream_bitrate.max(64_000))
    } else {
        0
    };

    let pixel_ratio =
        (out_w as f64 * out_h as f64) / (src_w as f64 * src_h as f64).max(1.0);
    let scaled_from_video =
        (source_video as f64 * pixel_ratio * SOURCE_BITRATE_SHRINK).round() as u64;

    let cap_from_container = if container_bitrate > 0 {
        (container_bitrate as f64 * SOURCE_BITRATE_SHRINK).round() as u64
    } else {
        u64::MAX
    };

    let mut target = ceiling;
    if source_video > 0 {
        target = target.min(scaled_from_video.max(MIN_TARGET_BITRATE_BPS));
    }
    target = target.min(cap_from_container);
    target.max(MIN_TARGET_BITRATE_BPS)
}

fn resolve_video_target_bitrate(
    ictx: &format::context::Input,
    video_ist: &format::stream::Stream,
    file_size: u64,
    preset_max_bitrate: u64,
    user_max_bitrate: Option<u64>,
    max_w: u32,
    max_h: u32,
    audio_stream_index: Option<usize>,
) -> Result<u64> {
    let mut dec_ctx =
        CodecContext::from_parameters(video_ist.parameters()).map_err(map_ffmpeg_error)?;
    apply_video_decoder_threading(&mut dec_ctx);
    let decoder = dec_ctx.decoder().video().map_err(map_ffmpeg_error)?;

    let src_w = decoder.width();
    let src_h = decoder.height();
    let (out_w, out_h) = scale_dimensions(src_w, src_h, max_w, max_h);

    let stream_br = codec_parameters_bit_rate(&video_ist.parameters());
    let ctx_br = decoder.bit_rate() as u64;
    let video_stream_br = stream_br.max(ctx_br);

    let mut audio_br = 0u64;
    if let Some(idx) = audio_stream_index {
        if let Some(ast) = ictx.stream(idx) {
            audio_br = codec_parameters_bit_rate(&ast.parameters());
        }
    }

    let container_br =
        estimate_container_bitrate_bps(ictx, file_size, ictx.duration());

    let target = estimate_video_target_bitrate_bps(
        video_stream_br,
        container_br,
        audio_br,
        preset_max_bitrate,
        user_max_bitrate,
        src_w,
        src_h,
        out_w,
        out_h,
    );

    log::info!(
        "compress bitrate: source_video={}bps container={}bps preset_max={}bps -> target={}bps ({}x{})",
        video_stream_br,
        container_br,
        preset_max_bitrate,
        target,
        out_w,
        out_h
    );

    Ok(target)
}

fn scale_dimensions(src_w: u32, src_h: u32, max_w: u32, max_h: u32) -> (u32, u32) {
    if src_w <= max_w && src_h <= max_h {
        return (src_w & !1, src_h & !1);
    }
    let wr = max_w as f64 / src_w as f64;
    let hr = max_h as f64 / src_h as f64;
    let r = wr.min(hr);
    let w = ((src_w as f64 * r) as u32) & !1;
    let h = ((src_h as f64 * r) as u32) & !1;
    (w.max(2), h.max(2))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scale_dimensions_keeps_aspect() {
        let (w, h) = scale_dimensions(1920, 1080, 1280, 1280);
        assert_eq!(w, 1280);
        assert_eq!(h, 720);
    }

    #[test]
    fn compress_target_bitrate_caps_above_source() {
        // ~40 MB / ~107 s ≈ 3.0 Mbps container; video ~2.5 Mbps — Medium preset must not force 3 Mbps.
        let target = estimate_video_target_bitrate_bps(
            2_500_000,
            3_000_000,
            128_000,
            3_000_000,
            None,
            1920,
            1080,
            1920,
            1080,
        );
        assert!(target < 3_000_000);
        assert!(target >= MIN_TARGET_BITRATE_BPS);
    }

    #[test]
    fn compress_target_bitrate_scales_with_resolution() {
        let full = estimate_video_target_bitrate_bps(
            2_000_000,
            2_200_000,
            128_000,
            6_000_000,
            None,
            1920,
            1080,
            1920,
            1080,
        );
        let half = estimate_video_target_bitrate_bps(
            2_000_000,
            2_200_000,
            128_000,
            6_000_000,
            None,
            1920,
            1080,
            960,
            540,
        );
        assert!(half < full);
    }
}

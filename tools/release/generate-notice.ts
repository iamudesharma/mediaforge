#!/usr/bin/env bun
/**
 * Generates LGPL NOTICE file for pub.dev release.
 */
import { writeFileSync } from "fs";
import { join } from "path";

const notice = `flutter_video_processor
Copyright (c) flutter_video_processor contributors

This package links against FFmpeg (https://ffmpeg.org/) under LGPL 2.1 or later.

FFmpeg configure flags (minimal mobile build):
  --disable-everything --enable-avcodec --enable-avformat --enable-avutil
  --enable-swscale --enable-swresample --enable-zlib
  --enable-mediacodec (Android) / --enable-videotoolbox (Apple)
  --enable-decoder=h264,hevc,aac --enable-muxer=mp4

NO GPL components (x264/x265) are included in official builds.

To obtain FFmpeg source corresponding to linked binaries, see:
  https://github.com/your-org/flutter_video_processor/releases

For LGPL compliance, your app must provide:
  1. A copy of the LGPL license
  2. Instructions to relink against modified FFmpeg
  3. FFmpeg source code offer for the version used in prebuilt artifacts
`;

writeFileSync(
  join(import.meta.dir, "../../packages/flutter_video_processor/NOTICE"),
  notice,
);
console.log("NOTICE file generated");

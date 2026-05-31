import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_forge/media_forge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize the FFI generated Rust library
  await RustLib.init();
  runApp(const RustMediaRuntimeDemoApp());
}

class RustMediaRuntimeDemoApp extends StatelessWidget {
  const RustMediaRuntimeDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rust Media Runtime Dashboard',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Indigo
          secondary: Color(0xFF06B6D4), // Cyan
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const int _maxQueueSize = 2000;
  static const int _videoFrameQueueCap = 32;
  static const int _audioFrameQueueCap = 32;
  static const int _textureHandle = 42;
  static const int _previewMaxEdge = 720;

  MediaPlaybackEngine? _engine;
  final MediaPlaybackPresenter _videoPresenter = MediaPlaybackPresenter(
    textureHandle: _textureHandle,
    mode: MediaPresentationMode.auto,
  );
  MediaPlaybackDrive? _drive;
  int _lastPresentedPtsMs = -1;
  bool _isPlaying = false;
  PlaybackState _state = PlaybackState.idle;
  int _mediaTimeMs = 0;
  int _audioClockMs = 0;
  int _wallClockMs = 0;
  int _latestDecodedPtsMs = 0;
  int _presentedPtsMs = 0;
  int _avDriftMs = 0;
  bool _videoStarved = false;
  double _playbackRate = 1.0;
  int _videoPacketsInQueue = 0;
  int _audioPacketsInQueue = 0;
  int _videoFramesInQueue = 0;
  int _audioFramesInQueue = 0;

  bool get _useGpuTexture => _videoPresenter.usesGpuTexture;

  bool _isCustomVideo = false;
  int _durationMs = 30000;
  String? _videoFileName;
  DecodeCapabilities? _decodeCaps;
  bool _phase0Healthy = false;

  final List<String> _logs = [];
  Timer? _pollingTimer;
  Timer? _diagnosticsTimer;
  Timer? _packetFeederTimer;
  int _packetIndex = 0;
  List<double> _audioWaveform = List.filled(20, 0.0);
  DateTime? _lastStarvationLogAt;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  void _addLog(String msg) {
    debugPrint('[ExampleApp] $msg');
    setState(() {
      _logs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  Future<void> _initEngine() async {
    _addLog('[Engine] Initializing MediaPlaybackEngine (texture=42, max_queue=$_maxQueueSize)');
    
    // Create the playback engine facade
    final engine = await MediaPlaybackEngine.newInstance(
      textureId: _textureHandle,
      maxQueueSize: BigInt.from(_maxQueueSize),
      previewMaxEdge: _previewMaxEdge,
    );
    
    _engine = engine;
    _drive = MediaPlaybackDrive(engine: engine, presenter: _videoPresenter);

    final caps = await engine.getDecodeCapabilities();
    _decodeCaps = caps;
    _phase0Healthy = caps.readyForHevcHw;
    _addLog(
      '[Phase0] FFmpeg ${caps.ffmpegVersion} '
      'hevc_vt=${caps.hevcVideotoolbox} h264_vt=${caps.h264Videotoolbox} '
      'ready=${caps.readyForHevcHw}',
    );
    _addLog('[Phase0] ${caps.hint}');
    if (!caps.readyForHevcHw) {
      _addLog(
        '[Phase0] WARN: 4K iPhone HEVC will use software decode — expect drift and catch-up. '
        'Run: bash scripts/run-rust-media-macos.sh',
      );
    }

    // Phase 4: presentation tick (~33ms) — GPU upload only, no setState per frame
    _pollingTimer = Timer.periodic(
      const Duration(milliseconds: MediaPlaybackAcceptance.presenterIntervalMs),
      (_) => _presentationTick(),
    );
    _diagnosticsTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _updateDiagnostics(),
    );
    
    // Auto-feed packets when playing to simulate demuxing
    _packetFeederTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_isPlaying && !_isCustomVideo) {
        _feedNextPackets();
      }
    });

    _addLog('[Engine] MediaPlaybackEngine ready');
  }

  Future<void> _updateDiagnostics() async {
    if (_engine == null || _drive == null || !mounted) return;
    try {
      final d = await _drive!.diagnosticsTick();

      if (_isCustomVideo) {
        final waveform = await _engine!.getAudioWaveform();
        if (mounted) {
          setState(() => _audioWaveform = waveform);
        }
      } else {
        bool hasAudio = false;
        while (true) {
          final audioFrame = await _engine!.takeAudioFrame();
          if (audioFrame == null) break;
          hasAudio = true;
        }
        if (hasAudio && mounted) {
          final rng = math.Random();
          setState(() {
            _audioWaveform = List.generate(20, (_) => rng.nextDouble() * 40.0 + 5.0);
          });
        }
      }

      if (mounted) {
        setState(() {
          _state = d.state;
          _mediaTimeMs = d.mediaTimeMs;
          _videoPacketsInQueue = d.videoPacketsInQueue;
          _audioPacketsInQueue = d.audioPacketsInQueue;
          _videoFramesInQueue = d.videoFramesInQueue;
          _audioFramesInQueue = d.audioFramesInQueue;
          _audioClockMs = d.audioClockMs;
          _wallClockMs = d.wallClockMs;
          _latestDecodedPtsMs = d.latestDecodedPtsMs;
          _presentedPtsMs = d.presentedPtsMs;
          _avDriftMs = d.avDriftMs;
          if (_isPlaying && _isCustomVideo) {
            _videoStarved = d.videoStarved && d.avDriftMs > MediaPlaybackAcceptance.catchupSkipNonKeyframeMs;
          }
        });
      }

      if (_isPlaying && _isCustomVideo && _mediaTimeMs % 2000 < MediaPlaybackAcceptance.presenterIntervalMs) {
        _addLog('[Sync] Master clock: ${_mediaTimeMs}ms (audio sample clock active)');
      }
      if (_isPlaying && _mediaTimeMs % 2000 < MediaPlaybackAcceptance.presenterIntervalMs) {
        final healthy = _drive!.isHealthyPlayback(d, isPlaying: _isPlaying);
        _addLog(
          '[Status] audio=${d.audioClockMs}ms wall=${d.wallClockMs}ms presented=${d.presentedPtsMs}ms '
          'decoded=${d.latestDecodedPtsMs}ms drift=${d.avDriftMs}ms healthy=$healthy '
          'VQ: ${d.videoFramesInQueue}/$_videoFrameQueueCap AQ: ${d.audioFramesInQueue}/$_audioFrameQueueCap',
        );
      }

      if (_isPlaying && d.mediaTimeMs >= _durationMs) {
        await _engine!.pause();
        _addLog('[Engine] Playback reached end of video. Pausing.');
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _mediaTimeMs = _durationMs;
            _state = PlaybackState.paused;
          });
        }
      }
    } catch (_) {}
  }

  void _feedNextPackets() {
    if (_engine == null || _isCustomVideo) return;
    
    // Feed one video packet
    _engine!.pushVideoPacket(
      packet: MediaPacket(
        ptsMs: BigInt.from(_packetIndex * 33),
        dtsMs: BigInt.from(_packetIndex * 33),
        streamIndex: BigInt.zero,
        isKeyframe: _packetIndex % 30 == 0,
        data: Uint8List.fromList([1, 2, 3, 4]),
      ),
    );

    // Feed one audio packet
    _engine!.pushAudioPacket(
      packet: MediaPacket(
        ptsMs: BigInt.from(_packetIndex * 33),
        dtsMs: BigInt.from(_packetIndex * 33),
        streamIndex: BigInt.one,
        isKeyframe: true,
        data: Uint8List.fromList([5, 6, 7, 8]),
      ),
    );

    _packetIndex++;
  }

  /// Phase 4 hot path: paced frame → GPU texture (no [setState], no decodeImageFromPixels).
  Future<void> _presentationTick() async {
    if (_engine == null || _drive == null || !mounted) return;
    try {
      final result = await _drive!.presentationTick();
      if (result.hasFrame) {
        _lastPresentedPtsMs = result.presentedPtsMs;
      } else if (_isPlaying && _isCustomVideo) {
        final drift = _avDriftMs > 0 ? _avDriftMs : _mediaTimeMs - _presentedPtsMs;
        if (drift > MediaPlaybackAcceptance.catchupSkipNonKeyframeMs &&
            _mediaTimeMs % 2000 < MediaPlaybackAcceptance.presenterIntervalMs) {
          _addLog(
            '[A/V] video starved audio=${_audioClockMs}ms presented=${_presentedPtsMs}ms '
            'decoded_latest=${_latestDecodedPtsMs}ms VQ=$_videoFramesInQueue pkt=$_videoPacketsInQueue',
          );
        }
        if (_isPlaying &&
            _videoFramesInQueue == 0 &&
            _videoPacketsInQueue == 0) {
          final now = DateTime.now();
          if (_lastStarvationLogAt == null ||
              now.difference(_lastStarvationLogAt!) > const Duration(seconds: 2)) {
            _lastStarvationLogAt = now;
            _addLog('[Starvation] Video queue empty (waiting for decode after seek/catch-up)');
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _togglePlay() async {
    if (_engine == null) return;
    if (_isPlaying) {
      await _engine!.pause();
      _addLog('[Controls] Paused playback');
      setState(() => _isPlaying = false);
    } else {
      await _engine!.start();
      _addLog('[Controls] Started playback');
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _seek(double value) async {
    if (_engine == null) return;
    final targetMs = value.round();
    _addLog('[Controls] Seeked to ${targetMs}ms (playing=$_isPlaying)');
    await _engine!.seek(timeMs: BigInt.from(targetMs));
    _videoPresenter.onSeek();
    _packetIndex = (targetMs / 33).round();
    // If we were playing, the Rust clock resumes itself via seek_complete().
    // Re-start the Dart runtimes in case they were stopped by a previous stop().
    if (_isPlaying) {
      await _engine!.start();
    }
  }

  Future<void> _pickCustomVideo() async {
    if (_engine == null) return;
    try {
      _addLog('[FilePicker] Opening file picker...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;
        _addLog('[FilePicker] Selected file: $name');

        // Stop current playing/simulation
        await _engine!.stop();
        if (mounted) {
          setState(() => _isPlaying = false);
        }
        await _videoPresenter.reset();

        _addLog('[Engine] Loading custom video: $path');
        await _engine!.openFile(path: path);

        // Retrieve duration
        final durationBig = await _engine!.getDurationMs();
        final duration = durationBig.toInt();
        _addLog('[Engine] Custom video loaded. Duration: ${duration}ms');

        if (mounted) {
          setState(() {
            _isCustomVideo = true;
            _durationMs = duration > 0 ? duration : 30000;
            _videoFileName = name;
            _lastPresentedPtsMs = -1;
          });
        await _videoPresenter.reset();
        }

        // Start playback
        await _engine!.start();
        if (mounted) {
          setState(() {
            _isPlaying = true;
          });
        }
        _addLog('[Engine] Custom video playback started');
      } else {
        _addLog('[FilePicker] User cancelled file picking');
      }
    } catch (e) {
      _addLog('[Error] Failed to pick/play custom video: $e');
    }
  }

  Future<void> _resetToSimulation() async {
    if (_engine == null) return;
    try {
      _addLog('[Engine] Resetting to simulated playback mode');
      await _engine!.stop();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isCustomVideo = false;
          _durationMs = 30000;
          _videoFileName = null;
          _packetIndex = 0;
        });
      }
      
      // Clear queues by creating a new instance or seeking
      await _engine!.seek(timeMs: BigInt.zero);
      _addLog('[Engine] Switched back to simulated gradient/silent generator');
    } catch (e) {
      _addLog('[Error] Failed to reset simulation: $e');
    }
  }

  Future<void> _changeRate(double rate) async {
    if (_engine == null) return;
    await _engine!.setRate(rate: rate);
    setState(() => _playbackRate = rate);
    _addLog('[Controls] Changed playback speed to ${rate.toStringAsFixed(1)}x');
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _diagnosticsTimer?.cancel();
    _packetFeederTimer?.cancel();
    _videoPresenter.dispose();
    unawaited(_engine?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 16),
              
              // Main content dashboard area
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Panel: Video Screen and Controls
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          Expanded(
                            child: _buildVideoScreen(),
                          ),
                          const SizedBox(height: 16),
                          _buildControlsCard(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Right Panel: Queues Diagnostics & Waveform & Logs
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          _buildQueuesCard(),
                          const SizedBox(height: 16),
                          _buildAudioCard(),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildLogsCard(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.slow_motion_video, color: Color(0xFF06B6D4), size: 28),
              const SizedBox(width: 12),
              Text(
                'RUST MEDIA RUNTIME',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (_decodeCaps != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_phase0Healthy ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (_phase0Healthy ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    _phase0Healthy ? 'HW HEVC OK' : 'SW DECODE',
                    style: TextStyle(
                      color: _phase0Healthy ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _stateColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _stateColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _stateColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _state.name.toUpperCase(),
                      style: TextStyle(
                        color: _stateColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Color get _stateColor {
    switch (_state) {
      case PlaybackState.playing:
        return const Color(0xFF10B981); // Emerald
      case PlaybackState.seeking:
        return const Color(0xFFF59E0B); // Amber
      case PlaybackState.paused:
        return const Color(0xFF6366F1); // Indigo
      default:
        return Colors.grey;
    }
  }

  Widget _buildVideoScreen() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: const Color(0x266366F1), // 15% opacity Indigo
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MediaVideoSurface(
            presenter: _videoPresenter,
            fit: BoxFit.contain,
            overlay: Stack(
              fit: StackFit.expand,
              children: [
                if (_isCustomVideo && _videoFileName != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.movie, size: 16, color: Color(0xFF06B6D4)),
                          const SizedBox(width: 6),
                          Text(
                            _videoFileName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_videoStarved)
                  const Center(
                    child: Text(
                      'VIDEO CATCHING UP…',
                      style: TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.black54,
                    child: Text(
                      'audio: ${_audioClockMs}ms  shown: ${_presentedPtsMs}ms',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF06B6D4),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          // Timeline Slider
          Row(
            children: [
              Text(
                '${(_mediaTimeMs / 1000).toStringAsFixed(1)}s',
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white70),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF6366F1),
                    thumbColor: const Color(0xFF6366F1),
                    overlayColor: const Color(0x336366F1), // 20% opacity Indigo
                  ),
                  child: Slider(
                    min: 0,
                    max: _durationMs.toDouble(),
                    value: _mediaTimeMs.toDouble().clamp(0.0, _durationMs.toDouble()),
                    onChanged: (val) => _seek(val),
                  ),
                ),
              ),
              Text('${(_durationMs / 1000).toStringAsFixed(1)}s', style: const TextStyle(fontFamily: 'monospace', color: Colors.white70)),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Play/Pause button
              IconButton.filled(
                onPressed: _togglePlay,
                iconSize: 32,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                ),
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              
              // Seed Packets manually
              if (!_isCustomVideo)
                ElevatedButton.icon(
                  onPressed: _feedNextPackets,
                  icon: const Icon(Icons.add_box),
                  label: const Text('DEMUX PACKETS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                  ),
                ),
              
              // Speed Rate Control
              Row(
                children: [
                  const Icon(Icons.speed, size: 20, color: Color(0x80FFFFFF)),
                  const SizedBox(width: 8),
                  DropdownButton<double>(
                    value: _playbackRate,
                    dropdownColor: const Color(0xFF1E293B),
                    underline: const SizedBox(),
                    items: [0.5, 1.0, 1.5, 2.0].map((rate) {
                      return DropdownMenuItem<double>(
                        value: rate,
                        child: Text('${rate}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) _changeRate(val);
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Custom Video Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _pickCustomVideo,
                icon: const Icon(Icons.video_library),
                label: Text(_isCustomVideo ? 'PICK NEW VIDEO' : 'PICK & PLAY VIDEO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                ),
              ),
              if (_isCustomVideo)
                ElevatedButton.icon(
                  onPressed: _resetToSimulation,
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('RESET TO SIMULATION'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueuesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RUST QUEUES STATUS',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0x80FFFFFF)),
          ),
          const SizedBox(height: 16),
          
          // Video Packet Queue
          _buildQueueIndicator('Video Packet Queue', _videoPacketsInQueue, Colors.purpleAccent),
          const SizedBox(height: 12),
          
          // Audio Packet Queue
          _buildQueueIndicator('Audio Packet Queue', _audioPacketsInQueue, Colors.pinkAccent),
          const SizedBox(height: 12),
          
          // Video Frame Queue
          _buildQueueIndicator(
            'Video Frame Queue',
            _videoFramesInQueue,
            const Color(0xFF06B6D4),
            max: _videoFrameQueueCap,
          ),
          const SizedBox(height: 12),
          
          // Audio Frame Queue
          _buildQueueIndicator(
            'Audio Frame Queue',
            _audioFramesInQueue,
            const Color(0xFF10B981),
            max: _audioFrameQueueCap,
          ),
        ],
      ),
    );
  }

  Widget _buildQueueIndicator(String title, int count, Color color, {int? max}) {
    final cap = max ?? _maxQueueSize;
    final double pct = (count / cap).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              '$count/$cap',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AUDIO SPECTRUM (PCM F32)',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0x80FFFFFF)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _audioWaveform.map((val) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 33),
                  width: 6,
                  height: val,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SYSTEM LOGS',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0x80FFFFFF)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      _logs[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

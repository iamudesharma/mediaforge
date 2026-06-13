import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:video_forge_editor/video_forge_editor.dart';
import 'widgets/rust_status_player.dart';
import 'widgets/updates_strip.dart';
import 'video_editor_flow.dart';
import 'photo_editor_flow.dart';

class HomeHub extends StatefulWidget {
  const HomeHub({super.key});

  @override
  State<HomeHub> createState() => _HomeHubState();
}

class _HomeHubState extends State<HomeHub> {
  final List<MockStatus> _postedStatuses = [];
  bool _busy = false;
  String? _loadingMessage;

  @override
  void initState() {
    super.initState();
    // Insert some default mock contacts to make the Updates Strip look populated and alive!
    _postedStatuses.addAll([
      const MockStatus(
        id: 'mock-1',
        label: 'Aarav',
        isVideo: false,
      ),
      const MockStatus(
        id: 'mock-2',
        label: 'Work Team',
        isVideo: true,
      ),
    ]);
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB3261E) : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<Uint8List> _generateSamplePhotoBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1080, 1080));
    
    // Draw background gradient
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(1080, 1080),
        [const Color(0xFF6200EE), const Color(0xFF03DAC6)],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1080, 1080), paint);

    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    for (double i = 100; i < 1080; i += 150) {
      canvas.drawLine(Offset(i, 0), Offset(i, 1080), gridPaint);
      canvas.drawLine(Offset(0, i), Offset(1080, i), gridPaint);
    }

    // Draw typography
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Media Studio\nSample Still',
        style: TextStyle(
          color: Colors.white,
          fontSize: 84,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: 900);
    textPainter.paint(canvas, const Offset(90, 420));

    final picture = recorder.endRecording();
    final img = await picture.toImage(1080, 1080);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _launchPhotoEditor(Uint8List bytes, {String? title}) async {
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoEditorFlow(
          initialBytes: bytes,
          title: title ?? 'Photo Editor',
        ),
      ),
    );

    if (result != null) {
      _addPostStatus(
        label: title ?? 'Photo Update',
        mediaPath: result,
        thumbPath: result,
        isVideo: false,
      );
      _showSnack('Photo exported and posted!');
    }
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _busy = true;
      _loadingMessage = 'Opening gallery…';
    });

    try {
      final pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (pickerResult != null && pickerResult.files.isNotEmpty) {
        final path = pickerResult.files.first.path;
        if (path != null) {
          final bytes = await File(path).readAsBytes();
          if (mounted) {
            await _launchPhotoEditor(bytes, title: pickerResult.files.first.name);
          }
        }
      }
    } catch (e) {
      _showSnack('Failed to pick photo: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _trySamplePhoto() async {
    setState(() {
      _busy = true;
      _loadingMessage = 'Generating sample photo…';
    });

    try {
      final bytes = await _generateSamplePhotoBytes();
      if (mounted) {
        await _launchPhotoEditor(bytes, title: 'Sample Photo');
      }
    } catch (e) {
      _showSnack('Failed to generate sample: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _launchVideoCreator(String path, {String? displayName}) async {
    final result = await Navigator.push<VideoExportResult?>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoEditorFlow(
          initialPath: path,
          displayName: displayName,
        ),
      ),
    );

    if (result != null) {
      _addPostStatus(
        label: displayName ?? 'Video Update',
        mediaPath: result.outputPath,
        thumbPath: result.thumbPath,
        isVideo: true,
      );
      _showSnack('Video exported and posted!');
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _busy = true;
      _loadingMessage = 'Opening gallery…';
    });

    try {
      final result = await pickVideoWithPlatformPicker(context: context);
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null && mounted) {
          await _launchVideoCreator(path, displayName: result.files.first.name);
        }
      }
    } catch (e) {
      _showSnack('Failed to pick video: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _tryNetworkSampleVideo() async {
    setState(() {
      _busy = true;
      _loadingMessage = 'Loading remote sample…';
    });

    const sampleUrl = 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4';
    try {
      // Ingest the remote URL directly or locally cache it
      final ingestResult = await MediaIngest.ingestLocalVideo(
        sampleUrl,
        cacheRemoteLocally: true,
        onStatus: (status) {
          if (mounted) {
            setState(() {
              _loadingMessage = status;
            });
          }
        },
      );

      if (ingestResult.phase == MediaIngestPhase.ready && ingestResult.stablePath != null) {
        if (mounted) {
          await _launchVideoCreator(ingestResult.stablePath!, displayName: 'Big Buck Bunny');
        }
      } else {
        _showSnack(ingestResult.error ?? 'Ingest failed', error: true);
      }
    } catch (e) {
      _showSnack('Failed to load network sample: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingMessage = null;
        });
      }
    }
  }

  void _addPostStatus({
    required String label,
    required String mediaPath,
    required String? thumbPath,
    required bool isVideo,
  }) {
    setState(() {
      _postedStatuses.insert(
        2, // Add after mock statuses
        MockStatus(
          id: 'status-${DateTime.now().millisecondsSinceEpoch}',
          label: label,
          imagePath: thumbPath,
          mediaPath: mediaPath,
          isVideo: isVideo,
          ringColor: Colors.deepPurpleAccent,
        ),
      );
    });
  }

  void _viewStatus(MockStatus status) {
    if (status.mediaPath == null || !File(status.mediaPath!).existsSync()) {
      _showSnack('Update preview is mock only: "${status.label}"');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                title: Text(status.label, style: const TextStyle(color: Colors.white)),
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: status.isVideo
                      ? RustStatusPlayer(path: status.mediaPath!)
                      : Image.file(
                          File(status.mediaPath!),
                          fit: BoxFit.contain,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar.large(
                expandedHeight: 180,
                floating: false,
                pinned: true,
                backgroundColor: theme.colorScheme.surface,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'Media Studio',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.15),
                          theme.colorScheme.secondary.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      _showSnack('Media Studio Unified Demo · Sprint V1.5');
                    },
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'Create New Project',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                  children: [
                    _CreateCard(
                      title: 'Video Studio',
                      description: 'Import, trim, live preview, overlays, preset export',
                      icon: Icons.movie_creation_outlined,
                      gradient: const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                      onTap: _busy ? null : _pickVideo,
                    ),
                    _CreateCard(
                      title: 'Photo Studio',
                      description: 'Crop, apply filters, rotate, adjustments, beauty ops',
                      icon: Icons.photo_library_outlined,
                      gradient: const [Color(0xFF00C9FF), Color(0xFF92FE9D)],
                      onTap: _busy ? null : _pickPhoto,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'Quick Try Sample Media',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                        child: const Icon(Icons.cloud_download, color: Colors.white),
                      ),
                      title: const Text('Try Network Video Sample'),
                      subtitle: const Text('Download & edit Big Buck Bunny'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _tryNetworkSampleVideo,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.2),
                        child: const Icon(Icons.palette_outlined, color: Colors.white),
                      ),
                      title: const Text('Try Sample Photo'),
                      subtitle: const Text('Generate a gradient graphic still'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy ? null : _trySamplePhoto,
                    ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
                  child: Text(
                    'Recent Updates',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: UpdatesStrip(
                    contacts: _postedStatuses,
                    onTapStatus: _viewStatus,
                  ),
                ),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    color: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            _loadingMessage ?? 'Working…',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.gradient,
    this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 36, color: Colors.white),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



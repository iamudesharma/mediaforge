import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import 'models/edit_graph.dart';
import 'models/layer_stack.dart';
import 'models/layer_transform.dart';
import 'models/overlay_layer.dart';
import 'models/operation_profile.dart';
import 'services/layer_bake.dart';
import 'rust_image_editor_config.dart';
import 'services/filter_descriptor.dart';
import 'services/image_buffer_utils.dart';
import 'services/image_export_saver.dart';
import 'services/rust_worker.dart';
import 'widgets/paint_stroke_painter.dart';

/// Holds source/working image bytes, RGBA pipeline, undo stack, and GPU prefs.
class EditorSession extends ChangeNotifier {
  static const previewQuality = EditorPipelineDefaults.previewQuality;

  int liveEditMaxEdge = EditorPipelineDefaults.liveEditMaxEdge;
  int previewMaxEdge = EditorPipelineDefaults.previewMaxEdge;
  bool showPerformanceInStatus = true;

  /// Sprint 4 — preview canvas uses RGBA pixels (no JPEG round-trip).
  bool useRgbaPreview = true;

  /// Sprint 3 — committed filter ops replayed on preview / export.
  EditGraph editGraph = EditGraph();

  /// Sprint 6/7 — non-destructive overlay layers (emoji, sticker, text, paint).
  LayerStack layerStack = LayerStack();

  PaintBrushKind paintBrush = PaintBrushKind.pen;
  Color paintColor = const Color(0xFF4EDEA3);
  double paintStrokeWidth = 8;
  double paintStrokeOpacity = 1;
  List<Offset> activePaintStroke = [];

  /// Live in-progress stroke; does not trigger full [notifyListeners].
  final ValueNotifier<List<Offset>> activePaintStrokeListenable =
      ValueNotifier<List<Offset>>([]);

  final ValueNotifier<int> layerListenable = ValueNotifier<int>(0);
  final ValueNotifier<int> previewListenable = ValueNotifier<int>(0);
  final ValueNotifier<bool> processingListenable = ValueNotifier<bool>(false);
  final ValueNotifier<bool> blockingListenable = ValueNotifier<bool>(false);
  final ValueNotifier<int> statusListenable = ValueNotifier<int>(0);
  final ValueNotifier<int> chromeListenable = ValueNotifier<int>(0);

  Listenable get editorChromeListenable => Listenable.merge([
        layerListenable,
        previewListenable,
        processingListenable,
        blockingListenable,
        statusListenable,
        chromeListenable,
      ]);

  Uint8List? sourceBytes;
  Uint8List? displayBytes;
  RgbaImageBuffer? rgbaBuffer;
  RgbaImageBuffer? rgbaBase;

  /// Downscaled unfiltered copy of [rgbaBase] for live adjust previews (Phase 1).
  RgbaImageBuffer? rgbaEditBase;

  /// Current preview pixels for [RgbaPreviewImage] (Sprint 4).
  RgbaImageBuffer? previewRgba;

  bool rgbaPipeline = false;
  OperationProfile? lastProfile;

  ImageInfo? imageInfo;
  GpuComputeInfo? gpuInfo;
  String status = 'Pick a photo to start editing';

  /// Light indicator (corner) — filter/adjust in progress.
  bool processing = false;

  /// Full-screen overlay — initial load / decode only.
  bool blocking = false;

  Duration? lastDuration;

  ProcessingBackend backend = ProcessingBackend.auto;
  OutputFormat outputFormat = OutputFormat.jpeg;
  int quality = 88;

  final List<Uint8List> _undo = [];
  final List<Uint8List> _redo = [];
  final List<EditGraphState> _undoGraph = [];
  final List<EditGraphState> _redoGraph = [];
  final List<LayerStack> _undoLayers = [];
  final List<LayerStack> _redoLayers = [];
  static const _maxUndo = 24;

  int _opGeneration = 0;
  Timer? _debounceTimer;
  Timer? _overlayDebounceTimer;

  /// Overlay sticker picked in the Overlay tab (used for live preview).
  Uint8List? overlayStickerBytes;
  BlendMode overlayBlendMode = BlendMode.normal;

  bool get busy => processing || blocking;
  bool get hasImage => sourceBytes != null;

  /// True when we can run filters (RGBA pipeline or legacy JPEG bytes).
  bool get hasWorkingImage => rgbaBase != null || displayBytes != null;
  bool get canUndo =>
      _undoLayers.isNotEmpty ||
      (rgbaPipeline ? _undoGraph.isNotEmpty : _undo.isNotEmpty);
  bool get canRedo =>
      _redoLayers.isNotEmpty ||
      (rgbaPipeline ? _redoGraph.isNotEmpty : _redo.isNotEmpty);

  int get editOpCount => editGraph.length;

  int get layerCount => layerStack.length;

  void notifyLayerChanged() {
    layerListenable.value++;
  }

  void notifyPreviewChanged() {
    previewListenable.value++;
    notifyListeners();
  }

  void _setProcessing(bool value) {
    if (processing == value) return;
    processing = value;
    processingListenable.value = value;
    notifyListeners();
  }

  void _setBlocking(bool value) {
    if (blocking == value) return;
    blocking = value;
    blockingListenable.value = value;
    notifyListeners();
  }

  void _bumpStatus() {
    statusListenable.value++;
    notifyListeners();
  }

  void setActivePaintStroke(List<Offset> points) {
    activePaintStroke = points;
    activePaintStrokeListenable.value = points;
  }

  void pushLayerUndo() {
    _undoLayers.add(layerStack.copy());
    if (_undoLayers.length > _maxUndo) _undoLayers.removeAt(0);
    _redoLayers.clear();
  }

  void addPaintStroke(
    List<Offset> points, {
    int imageWidth = 0,
    int imageHeight = 0,
    Size childSize = Size.zero,
  }) {
    if (points.length < 2) return;
    pushLayerUndo();
    final layer = PaintStrokeLayer(
      id: newLayerId(),
      transform: const LayerTransform(),
      points: points,
      color: paintColor,
      width: paintStrokeWidth,
      opacity: paintStrokeOpacity,
      brush: paintBrush,
    );
    if (imageWidth > 0 && imageHeight > 0 && childSize != Size.zero) {
      layer.displayPath = buildPaintStrokePath(
        points: points,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        childSize: childSize,
      );
    }
    layerStack.add(layer);
    setActivePaintStroke(const []);
    notifyLayerChanged();
    notifyListeners();
  }

  String get dimensionsLabel {
    final i = imageInfo;
    if (i == null) return '—';
    final fmt = i.format ?? 'image';
    final exif = i.exifOrientation;
    final exifStr = exif != null ? ' · EXIF $exif' : '';
    return '${i.width}×${i.height} · $fmt$exifStr';
  }

  String get sizeLabel {
    final b = displayBytes;
    if (b == null) return '—';
    final kb = b.length / 1024;
    return kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '${kb.toStringAsFixed(0)} KB';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _overlayDebounceTimer?.cancel();
    activePaintStrokeListenable.dispose();
    layerListenable.dispose();
    previewListenable.dispose();
    processingListenable.dispose();
    blockingListenable.dispose();
    statusListenable.dispose();
    chromeListenable.dispose();
    RustWorker.shutdown();
    super.dispose();
  }

  Future<void> refreshGpuInfo() async {
    await RustImageEditor.ensureInitialized();
    gpuInfo = RustImageEditor.gpuInfo();
    notifyListeners();
  }

  void setOutputFormat(OutputFormat format) {
    outputFormat = format;
    notifyListeners();
  }

  void setQuality(int value) {
    quality = value;
    notifyListeners();
  }

  void setBackend(ProcessingBackend value) {
    backend = value;
    status = 'Backend: ${RustImageEditor.backendName(value)}';
    notifyListeners();
  }

  void reprobe() {
    final b = displayBytes;
    if (b == null) return;
    imageInfo = RustImageEditor.probe(b);
    status = 'Metadata updated';
    notifyListeners();
  }

  Future<void> showProgressivePreview() async {
    final src = sourceBytes;
    if (src == null) return;

    final gen = ++_opGeneration;
    status = 'Progressive decode…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    try {
      await RustWorker.ensureStarted();
      final prog = await RustWorker.decodeProgressive(
        bytes: src,
        previewMaxEdge: 200,
      );
      if (gen != _opGeneration) return;

      rgbaBuffer = prog.buffer;
      rgbaBase = _cloneRgba(prog.buffer);
      rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
      previewRgba = prog.previewRgba;
      if (!useRgbaPreview) {
        displayBytes = await RustWorker.encodePreview(
          buffer: prog.previewRgba,
          previewMaxEdge: 200,
          quality: previewQuality,
        );
      }
      rgbaPipeline = true;
      imageInfo = prog.info;
      status =
          'Progressive preview (${prog.info.width}×${prog.info.height}) — full RGBA loaded';
    } catch (e) {
      status = 'Progressive failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        _bumpStatus();
      }
    }
  }

  Future<String?> encodeBlurHash() async {
    final b = displayBytes;
    if (b == null) return null;

    final gen = ++_opGeneration;
    status = 'Encoding BlurHash…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    try {
      await RustWorker.ensureStarted();
      final hash = await RustWorker.blurHashEncode(b);
      if (gen != _opGeneration) return null;
      status = 'BlurHash: ${hash.substring(0, hash.length.clamp(0, 24))}…';
      return hash;
    } catch (e) {
      status = 'BlurHash failed: $e';
      return null;
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        _bumpStatus();
      }
    }
  }

  Future<void> runBatchResizeDemo() async {
    final b = displayBytes;
    if (b == null) return;

    final gen = ++_opGeneration;
    status = 'Batch resize…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    try {
      _pushUndo();
      await RustWorker.ensureStarted();
      final out = await RustWorker.batchResizeDemo(bytes: b, backend: backend);
      if (gen != _opGeneration) return;

      displayBytes = out;
      imageInfo = RustImageEditor.probe(out);
      await _refreshRgbaFromDisplay();
      status = 'Batch done — showing 512×512 (2 variants)';
    } catch (e) {
      if (_undo.isNotEmpty) _undo.removeLast();
      status = 'Batch failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        _bumpStatus();
      }
    }
  }

  Future<void> loadSource(Uint8List bytes) async {
    _setBlocking(true);
    status = 'Loading…';
    notifyListeners();
    try {
      final info = RustImageEditor.probe(bytes);
      sourceBytes = bytes;
      displayBytes = bytes;
      rgbaBuffer = null;
      rgbaBase = null;
      rgbaPipeline = false;
      imageInfo = info;
      _undo.clear();
      _redo.clear();
      _undoGraph.clear();
      _redoGraph.clear();
      editGraph = EditGraph();
      layerStack = LayerStack();
      _undoLayers.clear();
      _redoLayers.clear();
      await refreshGpuInfo();
      status = 'Loaded ${info.width}×${info.height} — preparing fast pipeline…';
      notifyListeners();

      await _yieldToUi();
      await RustWorker.ensureStarted();
      final decoded = await RustWorker.decodeRgba(bytes);
      rgbaBase = _cloneRgba(decoded);
      rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
      rgbaBuffer = _cloneRgba(rgbaEditBase!);
      previewRgba = rgbaBuffer;
      rgbaPipeline = true;
      status =
          'Ready · RGBA ${decoded.width}×${decoded.height} · edit ≤$liveEditMaxEdge px · graph';
    } catch (e) {
      status = 'Load failed: $e';
    } finally {
      _setBlocking(false);
      notifyListeners();
    }
  }

  void resetToSource() {
    if (sourceBytes == null) return;
    _pushUndo();
    displayBytes = sourceBytes;
    rgbaBuffer = null;
    rgbaBase = null;
    rgbaPipeline = false;
    status = 'Reset to original';
    notifyListeners();
    unawaited(_refreshRgbaFromDisplay());
  }

  void _pushUndo() {
    final cur = displayBytes;
    if (cur == null) return;
    _undo.add(Uint8List.fromList(cur));
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_undoLayers.isNotEmpty) {
      _redoLayers.add(layerStack.copy());
      layerStack = _undoLayers.removeLast();
      status = 'Undo layer · ${layerStack.length} items';
      notifyListeners();
      return;
    }
    if (rgbaPipeline && _undoGraph.isNotEmpty) {
      _redoGraph.add(_captureGraphState());
      _restoreGraphState(_undoGraph.removeLast());
      status = 'Undo · ${editGraph.length} ops';
      notifyListeners();
      unawaited(_replayPreview());
      return;
    }
    if (_undo.isEmpty || displayBytes == null) return;
    _redo.add(Uint8List.fromList(displayBytes!));
    displayBytes = _undo.removeLast();
    rgbaBuffer = null;
    rgbaBase = null;
    previewRgba = null;
    rgbaPipeline = false;
    status = 'Undo';
    notifyListeners();
    unawaited(_refreshRgbaFromDisplay());
  }

  void redo() {
    if (_redoLayers.isNotEmpty) {
      _undoLayers.add(layerStack.copy());
      layerStack = _redoLayers.removeLast();
      status = 'Redo layer · ${layerStack.length} items';
      notifyListeners();
      return;
    }
    if (rgbaPipeline && _redoGraph.isNotEmpty) {
      _undoGraph.add(_captureGraphState());
      _restoreGraphState(_redoGraph.removeLast());
      status = 'Redo · ${editGraph.length} ops';
      notifyListeners();
      unawaited(_replayPreview());
      return;
    }
    if (_redo.isEmpty) return;
    _pushUndo();
    displayBytes = _redo.removeLast();
    rgbaBuffer = null;
    rgbaBase = null;
    previewRgba = null;
    rgbaPipeline = false;
    status = 'Redo';
    notifyListeners();
    unawaited(_refreshRgbaFromDisplay());
  }

  void cancelDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Apply a filter off the UI thread (RGBA when available). [livePreview] debounces.
  Future<void> applyFilter({
    required String label,
    required FilterDescriptor descriptor,
    bool saveUndo = true,
    bool livePreview = false,
    bool fromBase = false,
  }) async {
    if (!hasWorkingImage) return;

    if (livePreview) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 280), () {
        unawaited(
          _applyFilterInternal(
            label: label,
            descriptor: descriptor,
            saveUndo: false,
            fromBase: fromBase,
          ),
        );
      });
      return;
    }

    await _applyFilterInternal(
      label: label,
      descriptor: descriptor,
      saveUndo: saveUndo,
      fromBase: fromBase,
    );
  }

  Future<void> _applyFilterInternal({
    required String label,
    required FilterDescriptor descriptor,
    required bool saveUndo,
    required bool fromBase,
  }) async {
    final gen = ++_opGeneration;
    status = '$label…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      if (saveUndo) _pushUndo();
      await RustWorker.ensureStarted();

      if (rgbaBase != null) {
        if (saveUndo) {
          _pushGraphUndo();
          editGraph = editGraph.appendFilter(descriptor);
        }
        await _replayPreview(
          liveFilter: saveUndo || !fromBase ? null : descriptor,
          previewEdge: saveUndo
              ? previewMaxEdge
              : (fromBase ? liveEditMaxEdge : previewMaxEdge),
        );
        if (gen != _opGeneration) return;
      } else {
        final input = displayBytes!;
        final out = await RustWorker.filterBytes(
          bytes: input,
          filter: descriptor,
          format: outputFormat,
          quality: quality,
        );
        if (gen != _opGeneration) return;
        displayBytes = out;
        rgbaBuffer = null;
        rgbaBase = null;
        rgbaPipeline = false;
      }

      if (displayBytes != null) {
        imageInfo = RustImageEditor.probe(displayBytes!);
      } else if (previewRgba != null) {
        imageInfo = ImageInfo(
          width: previewRgba!.width,
          height: previewRgba!.height,
          format: imageInfo?.format,
        );
      }
      lastDuration = sw.elapsed;
      final graphHint =
          rgbaPipeline && editGraph.isNotEmpty ? ' · ${editGraph.length} ops' : '';
      status = '${_statusWithProfile(label, sw.elapsedMilliseconds)}$graphHint';
    } catch (e) {
      if (saveUndo) {
        if (rgbaPipeline && _undoGraph.isNotEmpty) {
          final prev = _undoGraph.removeLast();
          _restoreGraphState(prev);
        } else if (_undo.isNotEmpty) {
          _undo.removeLast();
        }
      }
      status = '$label failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  RgbaImageBuffer _editBaseUnfiltered() {
    if (rgbaEditBase != null) return rgbaEditBase!;
    if (rgbaBase == null) {
      throw StateError('No RGBA base');
    }
    rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
    return rgbaEditBase!;
  }

  EditGraphState _captureGraphState() => EditGraphState(
        graph: editGraph.copy(),
        bakedFull: rgbaBase != null ? _cloneRgba(rgbaBase!) : null,
        bakedEdit: rgbaEditBase != null ? _cloneRgba(rgbaEditBase!) : null,
      );

  void _restoreGraphState(EditGraphState state) {
    editGraph = state.graph.copy();
    if (state.bakedFull != null) {
      rgbaBase = _cloneRgba(state.bakedFull!);
    }
    if (state.bakedEdit != null) {
      rgbaEditBase = _cloneRgba(state.bakedEdit!);
    }
  }

  void _pushGraphUndo() {
    _undoGraph.add(_captureGraphState());
    if (_undoGraph.length > _maxUndo) {
      _undoGraph.removeAt(0);
    }
    _redoGraph.clear();
  }

  /// Replay [editGraph] (+ optional live filter) on the edit-scale base.
  Future<void> _replayPreview({
    FilterDescriptor? liveFilter,
    int? previewEdge,
  }) async {
    final base = _editBaseUnfiltered();
    final ops = <EditOp>[...editGraph.ops];
    if (liveFilter != null) {
      ops.add(EditOp.filter(filter: liveFilter.toImageFilter()));
    }
    final edge = previewEdge ?? previewMaxEdge;
    final result = await RustWorker.replayEditPipeline(
      base: base,
      ops: ops,
      backend: backend,
      previewMaxEdge: edge,
      previewQuality: previewQuality,
      encodePreviewJpeg: !useRgbaPreview,
    );
    lastProfile = result.profile;
    rgbaBuffer = result.buffer;
    previewRgba = result.buffer;
    if (result.preview != null) {
      displayBytes = result.preview;
    }
    notifyPreviewChanged();
  }

  /// Bake committed filters into full-res base before destructive pixel edits.
  Future<void> _bakeGraphIntoFullBase() async {
    final full = rgbaBase;
    if (full == null || editGraph.isEmpty) return;
    await RustWorker.ensureStarted();
    rgbaBase = await RustWorker.applyEditPipelineFull(
      base: full,
      ops: editGraph.ops,
      backend: backend,
    );
    editGraph = EditGraph();
    rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
  }

  String _statusWithProfile(String label, int totalMs) {
    if (!showPerformanceInStatus || lastProfile == null) {
      return '$label · ${totalMs}ms';
    }
    return '$label · ${totalMs}ms${lastProfile!.statusSuffix()}';
  }

  Future<void> runBytes(
    String label,
    Future<Uint8List> Function(Uint8List input) work, {
    bool saveUndo = true,
  }) async {
    final input = displayBytes;
    if (input == null) return;

    final gen = ++_opGeneration;
    status = '$label…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      if (saveUndo) _pushUndo();
      await RustWorker.ensureStarted();
      final out = await work(input);
      if (gen != _opGeneration) return;

      displayBytes = out;
      rgbaBuffer = null;
      rgbaBase = null;
      rgbaPipeline = false;
      imageInfo = RustImageEditor.probe(out);
      lastDuration = sw.elapsed;
      status = '$label · ${sw.elapsedMilliseconds} ms';
    } catch (e) {
      if (saveUndo && _undo.isNotEmpty) _undo.removeLast();
      status = '$label failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  /// Draw on the RGBA pipeline (fast — no PNG/oxipng round-trip).
  Future<void> runDraw({
    required String label,
    required Future<({RgbaImageBuffer buffer, Uint8List? preview})> Function(
      RgbaImageBuffer source,
    )
        work,
  }) async {
    if (rgbaBuffer == null && displayBytes != null) {
      await _ensureRgbaReady();
    }
    final source = rgbaBuffer;
    if (source == null) return;

    final gen = ++_opGeneration;
    status = '$label…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      _pushUndo();
      await RustWorker.ensureStarted();
      await _bakeGraphIntoFullBase();
      final result = await work(rgbaBuffer ?? source);
      if (gen != _opGeneration) return;

      rgbaBuffer = result.buffer;
      rgbaBase = _cloneRgba(result.buffer);
      rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
      previewRgba = result.buffer;
      rgbaPipeline = true;
      if (result.preview != null) {
        displayBytes = result.preview;
        imageInfo = RustImageEditor.probe(result.preview!);
      } else {
        imageInfo = ImageInfo(
          width: result.buffer.width,
          height: result.buffer.height,
          format: imageInfo?.format,
        );
      }
      notifyPreviewChanged();
      lastDuration = sw.elapsed;
      status = '$label · ${sw.elapsedMilliseconds} ms';
    } catch (e) {
      if (_undo.isNotEmpty) _undo.removeLast();
      status = '$label failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  /// Composite overlay on the RGBA pipeline (worker isolate + optional JPEG preview).
  Future<void> runOverlay({
    required String label,
    required Future<({RgbaImageBuffer buffer, Uint8List? preview})> Function(
      RgbaImageBuffer source,
    )
        work,
    bool saveUndo = true,
  }) async {
    if (rgbaBuffer == null && displayBytes != null) {
      await _ensureRgbaReady();
    }
    final source = rgbaBuffer;
    if (source == null) return;

    final gen = ++_opGeneration;
    status = '$label…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      if (saveUndo) _pushUndo();
      await RustWorker.ensureStarted();
      if (saveUndo) await _bakeGraphIntoFullBase();
      final result = await work(rgbaBuffer ?? source);
      if (gen != _opGeneration) return;

      rgbaBuffer = result.buffer;
      if (saveUndo) {
        rgbaBase = _cloneRgba(result.buffer);
        rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
      }
      previewRgba = result.buffer;
      rgbaPipeline = true;
      if (result.preview != null) {
        displayBytes = result.preview;
        imageInfo = RustImageEditor.probe(result.preview!);
      } else {
        imageInfo = ImageInfo(
          width: result.buffer.width,
          height: result.buffer.height,
          format: imageInfo?.format,
        );
      }
      notifyPreviewChanged();
      lastDuration = sw.elapsed;
      status = '$label · ${sw.elapsedMilliseconds} ms';
    } catch (e) {
      if (saveUndo && _undo.isNotEmpty) _undo.removeLast();
      status = '$label failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  /// Debounced overlay preview while dragging (no undo).
  void scheduleOverlayLivePreview({required int x, required int y}) {
    final sticker = overlayStickerBytes;
    if (sticker == null || !hasImage) return;

    _overlayDebounceTimer?.cancel();
    _overlayDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      runOverlay(
        label: 'Overlay preview',
        saveUndo: false,
        work: (_) {
          final base = rgbaBase ?? rgbaBuffer;
          if (base == null) {
            throw StateError('RGBA buffer not ready');
          }
          return RustWorker.overlayComposite(
            base: base,
            overlayBytes: sticker,
            x: x,
            y: y,
            blendMode: overlayBlendMode,
            previewMaxEdge: previewMaxEdge,
            previewQuality: previewQuality,
            encodePreviewJpeg: !useRgbaPreview,
          );
        },
      );
    });
  }

  Future<void> _ensureRgbaReady() async {
    final bytes = displayBytes;
    if (bytes == null) return;
    await RustWorker.ensureStarted();
    final decoded = await RustWorker.decodeRgba(bytes);
    rgbaBuffer = decoded;
    rgbaBase = _cloneRgba(decoded);
    rgbaPipeline = true;
  }

  Future<void> enableRgbaPipeline() async {
    if (displayBytes == null) return;

    final gen = ++_opGeneration;
    status = 'Preparing RGBA pipeline…';
    notifyListeners();
    await _yieldToUi();

    try {
      await _refreshRgbaFromDisplay();
      if (gen != _opGeneration) return;
      status = rgbaPipeline
          ? 'RGBA pipeline ready · ${rgbaBuffer?.width}×${rgbaBuffer?.height}'
          : 'RGBA pipeline unavailable';
    } catch (e) {
      status = 'RGBA pipeline failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  Future<void> runRgba(
    String label,
    Future<({RgbaImageBuffer buffer, Uint8List preview})> Function(
      RgbaImageBuffer buf,
    )
        work,
  ) async {
    if (rgbaBuffer == null && displayBytes != null) {
      await _ensureRgbaReady();
    }
    final buf = rgbaBuffer;
    if (buf == null) return;

    final gen = ++_opGeneration;
    status = '$label…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      _pushUndo();
      await RustWorker.ensureStarted();
      await _bakeGraphIntoFullBase();
      final result = await work(rgbaBuffer ?? buf);
      if (gen != _opGeneration) return;

      rgbaBuffer = result.buffer;
      rgbaBase = _cloneRgba(result.buffer);
      rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
      previewRgba = result.buffer;
      rgbaPipeline = true;
      displayBytes = result.preview;
      if (displayBytes != null) {
        imageInfo = RustImageEditor.probe(displayBytes!);
      }
      lastDuration = sw.elapsed;
      status = '$label · ${sw.elapsedMilliseconds} ms';
    } catch (e) {
      if (_undo.isNotEmpty) _undo.removeLast();
      status = '$label failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  /// RGBA resize on the worker isolate (Advanced tab).
  Future<void> runRgbaResize({
    required String label,
    required int width,
    required int height,
    ProcessingBackend? resizeBackend,
  }) {
    return runRgba(
      label,
      (buf) => RustWorker.resizeRgba(
        buffer: buf,
        width: width,
        height: height,
        backend: resizeBackend ?? backend,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
      ),
    );
  }

  /// Encode at full resolution when RGBA is available, then save via [save] or [ImageExportSaver].
  Future<String> exportAndSave({
    void Function(Uint8List bytes, ImageInfo info)? customSave,
    OutputFormat? format,
    int? quality,
  }) async {
    final exportFormat = format ?? outputFormat;
    final exportQuality = quality ?? this.quality;

    final gen = ++_opGeneration;
    status = 'Preparing export…';
    notifyListeners();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      await RustWorker.ensureStarted();
      final bytes = await _encodeForExport(exportFormat, exportQuality);
      if (gen != _opGeneration) return 'Cancelled';

      final info = RustImageEditor.probe(bytes);
      if (customSave != null) {
        customSave(bytes, info);
        status = 'Exported · ${sw.elapsedMilliseconds} ms';
        return status;
      }
      final saved = await ImageExportSaver.save(
        bytes: bytes,
        format: exportFormat,
      );
      status = '$saved · ${sw.elapsedMilliseconds} ms';
      return status;
    } catch (e) {
      status = 'Export failed: $e';
      return status;
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  Future<Uint8List> _encodeForExport(OutputFormat format, int exportQuality) async {
    final base = rgbaBase;
    if (base != null) {
      await RustWorker.ensureStarted();
      var exportBuf = base;
      if (editGraph.isNotEmpty) {
        exportBuf = await RustWorker.applyEditPipelineFull(
          base: base,
          ops: editGraph.ops,
          backend: backend,
        );
      }
      if (layerStack.isNotEmpty) {
        exportBuf = await LayerBake.bakeOnto(exportBuf, layerStack);
      }
      return RustWorker.encodeFullRgba(
        buffer: exportBuf,
        format: format,
        quality: exportQuality,
      );
    }
    final display = displayBytes;
    if (display == null) {
      throw StateError('No image to export');
    }
    if (format == outputFormat) {
      return Uint8List.fromList(display);
    }
    return RustWorker.bytesTransform(
      bytes: display,
      op: 'compress',
      params: {
        'format': format.index,
        'quality': exportQuality,
      },
    );
  }

  Future<void> _refreshRgbaFromDisplay() async {
    final bytes = displayBytes;
    if (bytes == null) return;
    try {
      await RustWorker.ensureStarted();
      final decoded = await RustWorker.decodeRgba(bytes);
      rgbaBuffer = decoded;
      rgbaBase = _cloneRgba(decoded);
      rgbaPipeline = true;
    } catch (_) {
      rgbaPipeline = false;
    }
  }

  static RgbaImageBuffer _cloneRgba(RgbaImageBuffer b) => RgbaImageBuffer(
        width: b.width,
        height: b.height,
        pixels: Uint8List.fromList(b.pixels),
      );

  static Future<void> _yieldToUi() {
    final completer = Completer<void>();
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      completer.complete();
    });
    return completer.future;
  }
}

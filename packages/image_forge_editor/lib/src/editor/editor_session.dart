import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:image_forge_camera/image_forge_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:image_forge_editor/src/image_forge_editor.dart';

import 'crop_controller.dart';
import 'overlay_placement.dart';
import 'models/beauty_params.dart';
import 'models/edit_graph.dart';
import 'models/layer_stack.dart';
import 'models/layer_transform.dart';
import 'models/overlay_layer.dart';
import 'models/operation_profile.dart';
import 'services/layer_bake.dart';
import 'image_forge_editor_config.dart';
import 'services/beauty_exclude_mask.dart';
import 'services/beauty_look_names.dart';
import 'services/coalesce_tracker.dart';
import 'services/face_analysis_service.dart';
import 'services/filter_descriptor.dart';
import 'services/image_bytes_normalizer.dart';
import 'services/image_export_saver.dart';
import 'package:pixel_surface/pixel_surface.dart';
import 'services/rust_worker.dart';
import 'services/swipe_look_names.dart';
import 'widgets/paint_stroke_painter.dart';

/// Holds source/working image bytes, RGBA pipeline, undo stack, and GPU prefs.
class EditorSession extends ChangeNotifier {
  static const previewQuality = EditorPipelineDefaults.previewQuality;

  int liveEditMaxEdge = EditorPipelineDefaults.liveEditMaxEdge;
  int previewMaxEdge = EditorPipelineDefaults.previewMaxEdge;
  bool showPerformanceInStatus = true;

  /// Sprint 4 — preview canvas uses RGBA pixels (no JPEG round-trip).
  bool useRgbaPreview = true;

  /// Sprint 11b.2 — GPU surface + platform Texture (macOS); skips Dart ui.Image decode.
  bool useGpuTexturePreview = false;

  /// FRB GPU preview surface handle; null until first texture replay.
  PlatformInt64? gpuPreviewHandle;

  /// Flutter [Texture.textureId] from [GpuTextureRegistry].
  int? gpuTextureId;

  /// Whether the host platform supports the zero-copy beauty output path
  /// (Apple Metal with `Features::BGRA8UNORM_STORAGE`). Sticky after first
  /// successful probe; cached on the session so the slider path stays cheap.
  bool? _zeroCopyAvailable;

  /// Handle of the GPU surface that has a zero-copy output texture attached.
  /// The attachment is sticky for the surface lifetime — re-binding on each
  /// beauty dispatch would be wasteful and would invalidate the wgpu import.
  PlatformInt64? _zeroCopyAttachedFor;

  final gpuTextureListenable = ValueNotifier<int>(0);

  bool _isDisposed = false;

  /// Swipe mood filter shown during browse (Filters tab moods).
  MoodFilterPreset? previewMoodPreset;

  /// Committed swipe mood filter from [editGraph].
  MoodFilterPreset? get committedMoodPreset => editGraph.committedMoodPreset;

  /// Combo swipe look shown during browse (may differ from committed until release).
  SwipeLookPreset? previewSwipeLook;

  /// Committed combo swipe look from [editGraph].
  SwipeLookPreset? get committedSwipeLookPreset =>
      editGraph.committedSwipeLookPreset;

  Timer? _swipeLookDebounceTimer;

  /// Sprint 12 — native face analysis + feathered skin mask at edit resolution.
  FaceAnalysisResult? faceAnalysis;
  SegmentationMask? skinMask;
  bool faceAnalyzing = false;

  /// Committed regional beauty from [editGraph].
  BeautyParams? get committedBeautyParams => editGraph.committedBeautyParams;

  /// Committed skin smooth (0–1) from [editGraph].
  double? get committedSkinSmoothStrength =>
      editGraph.committedSkinSmoothStrength;

  BeautyParams? _previewBeautyParams;

  /// Look shown during swipe browse (may differ from committed until release).
  BeautyLookPreset? previewBeautyLook;

  /// Committed look inferred from [committedBeautyParams], if exact recipe match.
  BeautyLookPreset? get committedBeautyLook {
    final p = committedBeautyParams;
    if (p == null) return null;
    return beautyLookMatching(p);
  }

  /// Edit graph output before beauty — reused while dragging beauty sliders.
  RgbaImageBuffer? _beautyPipelineBase;

  /// Manual beauty eraser — subtracts from regional masks (mustache bleed, etc.).
  bool beautyEraserMode = false;
  double beautyEraserRadius = 28;
  SegmentationMask? beautyExcludeMask;

  /// Nexus A — front-camera live beauty mode.
  bool liveCameraActive = false;
  bool liveCameraTransitioning = false;
  bool enableLiveCameraBeauty = true;
  bool enableMediaPipeDownloadPrompt = true;
  bool showDebugFaceLandmarks = false;
  int liveCameraMaxEdge = 720;
  int liveCameraAnalyzeEveryNFrames = 3;
  /// Live camera viewport framing (Full = native sensor aspect).
  CropAspect livePreviewAspect = CropAspect.original;
  TemporalFaceSmoother? _temporalSmoother;
  int _liveFrameCount = 0;
  int _liveFramesPerSecond = 0;
  int _liveFpsWindowFrames = 0;
  DateTime? _liveFpsWindowStart;
  bool _liveFrameBusy = false;

  /// Pre-beauty frame for compare-hold on Beauty tool (Nexus E).
  RgbaImageBuffer? beautyCompareRgba;
  EditGraph editGraph = EditGraph();

  /// Sprint 6/7 — non-destructive overlay layers (emoji, sticker, text, paint).
  LayerStack layerStack = LayerStack();

  PaintBrushKind paintBrush = PaintBrushKind.pen;
  EraserMode eraserMode = EraserMode.partial;
  bool paintShapeFilled = false;
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

  /// Beauty panel status (analyzing / landmarks) without full editor rebuilds.
  final ValueNotifier<int> faceChromeListenable = ValueNotifier<int>(0);

  /// Swipe mood label — preset browse only (Sprint 14; not full session).
  final ValueNotifier<int> moodPreviewListenable = ValueNotifier<int>(0);

  /// Combo swipe look label chip.
  final ValueNotifier<int> swipeLookPreviewListenable = ValueNotifier<int>(0);

  /// Swipe beauty look label — look browse only (Sprint 14).
  final ValueNotifier<int> beautyPreviewListenable = ValueNotifier<int>(0);

  /// Stable merge — shell chrome only; preview uses [previewListenable] separately.
  late final Listenable editorChromeListenable = Listenable.merge([
    layerListenable,
    processingListenable,
    blockingListenable,
    statusListenable,
    chromeListenable,
  ]);

  DateTime? _statusThrottleNext;
  static const _liveStatusThrottleMs = 250;

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

  /// Beauty route for status (`gpu_beauty` / `cpu_beauty`). Sprint 22.
  String? lastBeautyPath;

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
  Timer? _moodDebounceTimer;
  Timer? _beautyDebounceTimer;
  Timer? _overlayDebounceTimer;

  /// Overlay sticker picked in the Overlay tab (used for live preview).
  Uint8List? overlayStickerBytes;
  BlendMode overlayBlendMode = BlendMode.normal;

  bool get busy => processing || blocking;
  bool get hasImage => sourceBytes != null;

  /// True when we can run filters (RGBA pipeline or legacy JPEG bytes).
  bool get hasWorkingImage =>
      rgbaBase != null || displayBytes != null || liveCameraActive;

  /// GPU texture path active for live beauty (no Dart RGBA widget).
  bool liveBeautyGpuActive = false;

  /// Processed preview replaces [CameraPreview] once beauty has been applied.
  bool get liveBeautyRgbaActive =>
      liveCameraActive && (previewRgba != null || liveBeautyGpuActive);

  /// Active beauty params during live (preview or committed).
  BeautyParams? get liveActiveBeautyParams =>
      liveCameraActive
          ? (_previewBeautyParams ?? committedBeautyParams)
          : null;

  bool get liveBeautyPending {
    if (!liveCameraActive) return false;
    final p = liveActiveBeautyParams;
    if (p == null || !p.hasEffect) return false;
    return skinMask == null ||
        !FaceAnalysisService.isAnalysisValid(faceAnalysis);
  }

  void setLivePreviewAspect(CropAspect aspect) {
    if (livePreviewAspect == aspect) return;
    livePreviewAspect = aspect;
    notifyListeners();
  }

  bool get canUndo =>
      _undoLayers.isNotEmpty ||
      (rgbaPipeline ? _undoGraph.isNotEmpty : _undo.isNotEmpty);
  bool get canRedo =>
      _redoLayers.isNotEmpty ||
      (rgbaPipeline ? _redoGraph.isNotEmpty : _redo.isNotEmpty);

  int get editOpCount => editGraph.length;

  int get layerCount => layerStack.length;

  void notifyLayerChanged() {
    if (_isDisposed) return;
    layerListenable.value++;
    _bumpPreviewOnly();
  }

  bool get hasUncommittedLayers => layerStack.isNotEmpty;

  void notifyPreviewChanged() {
    if (_isDisposed) return;
    previewListenable.value++;
    notifyListeners();
  }

  void _bumpPreviewOnly() {
    if (_isDisposed) return;
    previewListenable.value++;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  void _setProcessing(bool value) {
    if (_isDisposed) return;
    if (processing == value) return;
    processing = value;
    processingListenable.value = value;
    notifyListeners();
  }

  void _setBlocking(bool value) {
    if (_isDisposed) return;
    if (blocking == value) return;
    blocking = value;
    blockingListenable.value = value;
    notifyListeners();
  }

  void _bumpStatus() {
    if (_isDisposed) return;
    statusListenable.value++;
    notifyListeners();
  }

  /// Live camera FPS / status — throttle shell rebuilds (Sprint 14, scenario H).
  void _bumpStatusThrottled() {
    if (_isDisposed) return;
    final now = DateTime.now();
    final next = _statusThrottleNext;
    if (next != null && now.isBefore(next)) return;
    _statusThrottleNext = now.add(const Duration(milliseconds: _liveStatusThrottleMs));
    _bumpStatus();
  }

  void _bumpMoodPreview() {
    if (_isDisposed) return;
    moodPreviewListenable.value++;
  }

  void _bumpSwipeLookPreview() {
    if (_isDisposed) return;
    swipeLookPreviewListenable.value++;
  }

  void _bumpBeautyPreview() {
    if (_isDisposed) return;
    beautyPreviewListenable.value++;
  }

  /// Tool panel / export settings (format, quality, backend) — not preview pixels.
  void _bumpChrome() {
    if (_isDisposed) return;
    chromeListenable.value++;
    notifyListeners();
  }

  void setActivePaintStroke(List<Offset> points) {
    activePaintStroke = points;
    if (_isDisposed) return;
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
      filled: paintShapeFilled,
    );
    if (imageWidth > 0 && imageHeight > 0 && childSize != Size.zero) {
      layer.displayPath = buildPaintStrokePath(
        points: points,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        childSize: childSize,
        brush: paintBrush,
      );
    }
    layerStack.add(layer);
    setActivePaintStroke(const []);
    notifyLayerChanged();
    notifyListeners();
  }

  /// Duplicate all selected top-level layers with a small offset (Sprint 17).
  void duplicateSelection() {
    if (layerStack.selectedIds.isEmpty) return;
    pushLayerUndo();
    final newIds = <String>[];
    for (final id in layerStack.selectedIds.toList()) {
      for (final layer in layerStack.layers) {
        if (layer.id != id) continue;
        final dup = cloneLayerWithNewId(layer);
        layerStack.add(dup, select: false);
        newIds.add(dup.id);
        break;
      }
    }
    if (newIds.isNotEmpty) layerStack.selectMany(newIds);
    notifyLayerChanged();
    notifyListeners();
  }

  /// Group selected layers; returns error message for UI snackbar.
  String? groupSelection() {
    pushLayerUndo();
    final err = layerStack.groupSelected();
    if (err != null) {
      if (_undoLayers.isNotEmpty) _undoLayers.removeLast();
      return err;
    }
    notifyLayerChanged();
    notifyListeners();
    return null;
  }

  void ungroupSelection() {
    final id = layerStack.selectedId;
    if (id == null) return;
    final layer = layerStack.findById(id);
    if (layer is! GroupLayer) return;
    pushLayerUndo();
    layerStack.ungroup(id);
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
    _isDisposed = true;
    _debounceTimer?.cancel();
    _moodDebounceTimer?.cancel();
    _swipeLookDebounceTimer?.cancel();
    _beautyDebounceTimer?.cancel();
    _overlayDebounceTimer?.cancel();
    _disposeGpuSurface();
    activePaintStrokeListenable.dispose();
    layerListenable.dispose();
    previewListenable.dispose();
    processingListenable.dispose();
    blockingListenable.dispose();
    statusListenable.dispose();
    chromeListenable.dispose();
    faceChromeListenable.dispose();
    moodPreviewListenable.dispose();
    swipeLookPreviewListenable.dispose();
    beautyPreviewListenable.dispose();
    gpuTextureListenable.dispose();
    _temporalSmoother?.dispose();
    _temporalSmoother = null;
    if (liveCameraActive || LiveCameraService.isActive) {
      liveCameraActive = false;
      unawaited(LiveCameraService.stop());
    }
    unawaited(RustWorker.shutdown());
    super.dispose();
  }

  Future<void> refreshGpuInfo() async {
    await RustImageEditor.ensureInitialized();
    gpuInfo = RustImageEditor.gpuInfo();
    notifyListeners();
  }

  void setOutputFormat(OutputFormat format) {
    if (outputFormat == format) return;
    outputFormat = format;
    _bumpChrome();
  }

  void setQuality(int value) {
    if (quality == value) return;
    quality = value;
    _bumpChrome();
  }

  void setBackend(ProcessingBackend value) {
    if (backend == value) return;
    backend = value;
    status = 'Backend: ${RustImageEditor.backendName(value)}';
    _bumpStatus();
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
        liveEditMaxEdge: liveEditMaxEdge,
      );
      if (gen != _opGeneration) return;

      rgbaBase = prog.base;
      rgbaEditBase = prog.edit;
      rgbaBuffer = prog.edit;
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
      if (ImageBytesNormalizer.isHeicOrHeif(bytes)) {
        status = 'Converting HEIC…';
        notifyListeners();
        await RustWorker.ensureStarted();
        bytes = await RustWorker.transcribeHeicToPng(bytes);
      }
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
      previewMoodPreset = null;
      previewSwipeLook = null;
      faceAnalysis = null;
      skinMask = null;
      faceAnalyzing = false;
      _previewBeautyParams = null;
      previewBeautyLook = null;
      _beautyPipelineBase = null;
      beautyEraserMode = false;
      beautyExcludeMask = null;
      _disposeGpuSurface();
      layerStack = LayerStack();
      _undoLayers.clear();
      _redoLayers.clear();
      status = 'Loaded ${info.width}×${info.height} — preparing fast pipeline…';
      notifyListeners();

      await _yieldToUi();
      await RustWorker.ensureStarted();
      final results = await Future.wait([
        RustWorker.decodeAndPrepareEditBase(
          bytes: bytes,
          liveEditMaxEdge: liveEditMaxEdge,
        ),
        refreshGpuInfo(),
      ]);
      final prepared = results[0] as ({RgbaImageBuffer base, RgbaImageBuffer edit});
      rgbaBase = prepared.base;
      rgbaEditBase = prepared.edit;
      rgbaBuffer = prepared.edit;
      previewRgba = prepared.edit;
      rgbaPipeline = true;
      status =
          'Ready · RGBA ${prepared.base.width}×${prepared.base.height} · edit ≤$liveEditMaxEdge px · graph';
      if (FaceAnalysisService.isSupported) {
        unawaited(analyzeFaceForBeauty());
      }
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

  Future<void> undo() async {
    if (busy) return;
    cancelDebounced();

    if (_undoLayers.isNotEmpty) {
      _redoLayers.add(layerStack.copy());
      layerStack = _undoLayers.removeLast();
      status = 'Undo layer · ${layerStack.length} items';
      notifyLayerChanged();
      _bumpStatus();
      return;
    }

    if (rgbaPipeline && _undoGraph.isNotEmpty) {
      await _applyGraphHistoryStep(
        label: 'Undo',
        popUndo: true,
      );
      return;
    }

    if (_undo.isEmpty || displayBytes == null) return;
    final gen = ++_opGeneration;
    status = 'Undo…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();
    if (gen != _opGeneration) {
      _endHistoryOp(gen);
      return;
    }
    try {
      _redo.add(Uint8List.fromList(displayBytes!));
      displayBytes = _undo.removeLast();
      rgbaBuffer = null;
      rgbaBase = null;
      previewRgba = null;
      rgbaPipeline = false;
      await _refreshRgbaFromDisplay();
      if (gen == _opGeneration) {
        status = 'Undo';
      }
    } catch (e) {
      if (gen == _opGeneration) {
        status = 'Undo failed: $e';
      }
    } finally {
      _endHistoryOp(gen);
    }
  }

  Future<void> redo() async {
    if (busy) return;
    cancelDebounced();

    if (_redoLayers.isNotEmpty) {
      _undoLayers.add(layerStack.copy());
      layerStack = _redoLayers.removeLast();
      status = 'Redo layer · ${layerStack.length} items';
      notifyLayerChanged();
      _bumpStatus();
      return;
    }

    if (rgbaPipeline && _redoGraph.isNotEmpty) {
      await _applyGraphHistoryStep(
        label: 'Redo',
        popUndo: false,
      );
      return;
    }

    if (_redo.isEmpty) return;
    final gen = ++_opGeneration;
    status = 'Redo…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();
    if (gen != _opGeneration) {
      _endHistoryOp(gen);
      return;
    }
    try {
      _pushUndo();
      displayBytes = _redo.removeLast();
      rgbaBuffer = null;
      rgbaBase = null;
      previewRgba = null;
      rgbaPipeline = false;
      await _refreshRgbaFromDisplay();
      if (gen == _opGeneration) {
        status = 'Redo';
      }
    } catch (e) {
      if (gen == _opGeneration) {
        status = 'Redo failed: $e';
      }
    } finally {
      _endHistoryOp(gen);
    }
  }

  void _endHistoryOp(int gen) {
    if (gen != _opGeneration) return;
    _setProcessing(false);
    _bumpStatus();
  }

  Future<void> _applyGraphHistoryStep({
    required String label,
    required bool popUndo,
  }) async {
    final gen = ++_opGeneration;
    status = '$label…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();
    if (gen != _opGeneration) {
      _endHistoryOp(gen);
      return;
    }
    try {
      if (popUndo) {
        _redoGraph.add(_detachGraphState());
        _applyGraphState(_undoGraph.removeLast());
      } else {
        _undoGraph.add(_detachGraphState());
        _applyGraphState(_redoGraph.removeLast());
      }
      await _replayPreview(gen: gen);
      if (gen == _opGeneration) {
        status = '$label · ${editGraph.length} ops';
      }
    } catch (e) {
      if (gen == _opGeneration) {
        status = '$label failed: $e';
      }
    } finally {
      _endHistoryOp(gen);
    }
  }

  void cancelDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _moodDebounceTimer?.cancel();
    _moodDebounceTimer = null;
    _beautyDebounceTimer?.cancel();
    _beautyDebounceTimer = null;
  }

  void _bumpFaceChrome() {
    if (_isDisposed) return;
    faceChromeListenable.value++;
  }

  /// Run native face analysis at edit resolution (Vision on Apple; MediaPipe optional).
  Future<void> analyzeFaceForBeauty({bool force = false}) async {
    if (!FaceAnalysisService.isSupported) return;
    if (!hasWorkingImage || rgbaEditBase == null) return;
    if (!force && faceAnalysis != null) return;

    if (force) {
      faceAnalysis = null;
      skinMask = null;
      _beautyPipelineBase = null;
      beautyExcludeMask = null;
    }

    faceAnalyzing = true;
    _bumpFaceChrome();
    await _yieldToUi();
    try {
      final base = rgbaEditBase!;
      // Analyze the same EXIF-corrected edit-scale pixels we beautify (not raw sourceBytes).
      await RustWorker.ensureStarted();
      final analysisBytes = base.pixels;
      final result = await FaceAnalysisService.analyzeImage(
        bytes: analysisBytes,
        targetWidth: base.width,
        targetHeight: base.height,
        maxEdge: liveEditMaxEdge,
        pixelFormat: 'rgba',
      );
      faceAnalysis = result;
      if (result != null && FaceAnalysisService.isAnalysisValid(result)) {
        // Drop cached mask so a re-analyze picks up improved region logic.
        skinMask = null;
        await RustWorker.ensureStarted();
        skinMask = await RustWorker.buildSkinMaskFromAnalysis(
          analysis: result,
          width: base.width,
          height: base.height,
        );
      } else {
        skinMask = null;
      }
    } catch (e) {
      status = 'Face analysis failed: $e';
      _bumpStatus();
    } finally {
      faceAnalyzing = false;
      _bumpFaceChrome();
      if (skinMask != null &&
          (committedBeautyParams?.hasEffect ?? false) &&
          hasWorkingImage) {
        await _replayPreview();
      }
    }
  }

  /// Nexus A — start front-camera live beauty preview (mobile).
  Future<void> startLiveCameraBeauty() async {
    if (!LiveCameraService.isSupported ||
        liveCameraActive ||
        liveCameraTransitioning) {
      return;
    }
    liveCameraTransitioning = true;
    _bumpFaceChrome();
    cancelDebounced();
    _temporalSmoother = TemporalFaceSmoother(alpha: 0.25);
    _liveFrameCount = 0;
    faceAnalysis = null;
    skinMask = null;
    beautyCompareRgba = null;
    _beautyPipelineBase = null;
    rgbaPipeline = true;
    useRgbaPreview = true;
    try {
      await LiveCameraService.warmup();
      await LiveCameraService.start(
        onFrame: _onLiveCameraFrame,
        maxWidth: liveCameraMaxEdge,
        beforeInitialize: (_) async {
          liveCameraActive = true;
          _bumpFaceChrome();
          notifyListeners();
          await _yieldToUi();
          await _yieldToUi();
          if (defaultTargetPlatform == TargetPlatform.android) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        },
      );
      final previewSize = LiveCameraService.controller?.value.previewSize;
      if (previewSize != null) {
        imageInfo = ImageInfo(
          width: previewSize.width.round(),
          height: previewSize.height.round(),
          format: null,
        );
      }
      status = 'Live camera · front';
      _bumpStatus();
    } catch (e) {
      liveCameraActive = false;
      _temporalSmoother?.dispose();
      _temporalSmoother = null;
      status = 'Live camera failed: $e';
      _bumpStatus();
    } finally {
      liveCameraTransitioning = false;
      _bumpFaceChrome();
      notifyListeners();
    }
  }

  /// Stop live camera and release the stream.
  Future<void> stopLiveCameraBeauty() async {
    if (!liveCameraActive &&
        !LiveCameraService.isActive &&
        !liveCameraTransitioning) {
      return;
    }
    liveCameraTransitioning = true;
    _bumpFaceChrome();
    liveCameraActive = false;
    liveBeautyGpuActive = false;
    notifyListeners();
    try {
      await _yieldToUi();
      await _waitForLiveFrameIdle();
      _disposeGpuSurface();
      await LiveCameraService.stop();
    } finally {
      _temporalSmoother?.dispose();
      _temporalSmoother = null;
      liveCameraTransitioning = false;
      status = 'Live camera stopped';
      _bumpStatus();
      _bumpFaceChrome();
      notifyListeners();
    }
  }

  Future<void> _waitForLiveFrameIdle({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_liveFrameBusy && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  void _onLiveCameraFrame(CameraImage image) {
    if (!liveCameraActive || _liveFrameBusy) return;
    _liveFrameBusy = true;
    unawaited(_processLiveCameraFrame(image));
  }

  Future<void> _processLiveCameraFrame(CameraImage image) async {
    try {
      if (!liveCameraActive) return;
      final planesData = image.planes.map((p) => TransferableTypedData.fromList([p.bytes])).toList();
      final planesBytesPerRow = image.planes.map((p) => p.bytesPerRow).toList();
      final planesBytesPerPixel = image.planes.map((p) => p.bytesPerPixel).toList();

      final raw = await RustWorker.convertCameraImage(
        width: image.width,
        height: image.height,
        planesData: planesData,
        planesBytesPerRow: planesBytesPerRow,
        planesBytesPerPixel: planesBytesPerPixel,
        liveCameraMaxEdge: liveCameraMaxEdge,
        isAndroid: defaultTargetPlatform == TargetPlatform.android,
      );
      if (!liveCameraActive) return;

      final base = RgbaImageBuffer(
        width: raw['width']! as int,
        height: raw['height']! as int,
        pixels: (raw['pixels']! as TransferableTypedData).materialize().asUint8List(),
      );

      _liveFrameCount++;
      if (_liveFrameCount % liveCameraAnalyzeEveryNFrames == 0 &&
          FaceAnalysisService.isSupported) {
        await RustWorker.ensureStarted();
        var result = await FaceAnalysisService.analyzeImage(
          bytes: base.pixels,
          targetWidth: base.width,
          targetHeight: base.height,
          maxEdge: liveCameraMaxEdge,
          pixelFormat: 'rgba',
        );
        final smoother = _temporalSmoother;
        if (result != null && smoother != null) {
          result = smoother.smooth(result);
        }
        faceAnalysis = result;
        if (result != null && FaceAnalysisService.isAnalysisValid(result)) {
          skinMask = await RustWorker.buildSkinMaskFromAnalysisCamera(
            analysis: result,
            width: base.width,
            height: base.height,
          );
        } else {
          skinMask = null;
        }
        _bumpFaceChrome();
      }

      _recordLiveFps();

      beautyCompareRgba = base;
      rgbaEditBase = base;
      rgbaBase = base;
      imageInfo = ImageInfo(
        width: base.width,
        height: base.height,
        format: null,
      );

      final params = _activeBeautyParams() ?? committedBeautyParams;
      final analysis = faceAnalysis;
      final mask = skinMask;
      if (params != null &&
          params.hasEffect &&
          mask != null &&
          analysis != null &&
          FaceAnalysisService.isAnalysisValid(analysis)) {
        if (_gpuBeautyComputeAvailable()) {
          try {
            await _ensureGpuSurface(base);
            final handle = gpuPreviewHandle;
            if (handle != null) {
              await uploadGpuPreviewSurface(id: handle, buffer: base);
              await _applyGpuBeautyPipeline(
                handle: handle,
                buffer: base,
                skinMask: mask,
                analysis: analysis,
                params: params,
              );
              lastBeautyPath = 'gpu_beauty';
              if (_gpuBeautyDisplayViaTexture() &&
                  gpuTextureId != null &&
                  gpuTextureId! > 0) {
                final displayRb = await readbackGpuPreviewSurface(id: handle);
                rgbaBuffer = displayRb;
                previewRgba = null;
                liveBeautyGpuActive = true;
                _beautyPipelineBase = base;
                await GpuTextureRegistry.updateTexture(
                  handle: handle.toInt(),
                  pixels: displayRb.pixels,
                );
                if (!_isDisposed) {
                  gpuTextureListenable.value = gpuTextureId!;
                }
              } else {
                final displayRb = await readbackGpuPreviewSurface(id: handle);
                rgbaBuffer = displayRb;
                previewRgba = displayRb;
                liveBeautyGpuActive = false;
                _beautyPipelineBase = base;
              }
              final look = previewBeautyLook ?? committedBeautyLook;
              final fps = _liveFramesPerSecond > 0 ? ' · ${_liveFramesPerSecond}fps' : '';
              final pathTag = showPerformanceInStatus ? ' · gpu_beauty' : '';
              status = look != null
                  ? 'Live · ${beautyLookLabel(look)}$fps$pathTag'
                  : 'Live · beauty$fps$pathTag';
              _bumpStatusThrottled();
              displayBytes = null;
              _bumpPreviewOnly();
              return;
            }
          } catch (_) {
            liveBeautyGpuActive = false;
          }
        }
        final display = await RustWorker.applyBeautyCamera(
          buffer: base,
          analysis: analysis,
          skinMask: mask,
          params: params,
          excludeMask: _beautyExcludeForBuffer(base),
        );
        lastBeautyPath = 'cpu_beauty';
        liveBeautyGpuActive = false;
        rgbaBuffer = display;
        previewRgba = display;
        _beautyPipelineBase = base;
        final look = previewBeautyLook ?? committedBeautyLook;
        status = look != null
            ? 'Live · ${beautyLookLabel(look)}'
            : 'Live · beauty';
        _bumpStatusThrottled();
      } else {
        previewRgba = null;
        rgbaBuffer = null;
        liveBeautyGpuActive = false;
        _beautyPipelineBase = null;
        final pending = params?.hasEffect ?? false;
        if (pending) {
          status = 'Live · detecting face…';
          _bumpStatusThrottled();
        }
      }
      displayBytes = null;
      _bumpPreviewOnly();
    } catch (_) {
      // Drop frame on error — keep stream alive.
    } finally {
      _liveFrameBusy = false;
    }
  }

  void _recordLiveFps() {
    final now = DateTime.now();
    _liveFpsWindowFrames++;
    final start = _liveFpsWindowStart;
    if (start == null) {
      _liveFpsWindowStart = now;
      return;
    }
    final elapsed = now.difference(start).inMilliseconds;
    if (elapsed >= 1000) {
      _liveFramesPerSecond =
          (_liveFpsWindowFrames * 1000 / elapsed).round().clamp(0, 120);
      _liveFpsWindowFrames = 0;
      _liveFpsWindowStart = now;
    }
  }

  /// Toggle canvas eraser for removing beauty from stray areas (mustache, etc.).
  void setBeautyEraserMode(bool enabled) {
    if (beautyEraserMode == enabled) return;
    beautyEraserMode = enabled;
    _bumpFaceChrome();
  }

  void setBeautyEraserRadius(double radius) {
    beautyEraserRadius = radius.clamp(4.0, 96.0);
    _bumpFaceChrome();
  }

  void clearBeautyExclude() {
    if (beautyExcludeMask == null) return;
    beautyExcludeMask = null;
    _bumpFaceChrome();
    unawaited(_replayBeautyOnly());
  }

  /// Paint stroke in image pixel space — builds exclusion mask at edit resolution.
  void addBeautyEraserStroke(
    List<Offset> points, {
    required int imageWidth,
    required int imageHeight,
  }) {
    if (points.length < 2 || imageWidth <= 0 || imageHeight <= 0) return;
    final base = rgbaEditBase ?? previewRgba ?? rgbaBuffer;
    if (base == null) return;
    final w = base.width;
    final h = base.height;
    var mask = beautyExcludeMask;
    if (mask == null || mask.width != w || mask.height != h) {
      mask = BeautyExcludeMask.empty(width: w, height: h);
      beautyExcludeMask = mask;
    }
    final scaleX = w / imageWidth;
    final scaleY = h / imageHeight;
    final scaled = points
        .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
        .toList(growable: false);
    BeautyExcludeMask.stampStroke(
      mask: mask,
      points: scaled,
      radiusPx: beautyEraserRadius * scaleX,
    );
    _bumpFaceChrome();
    unawaited(_replayBeautyOnly());
  }

  SegmentationMask? _beautyExcludeForBuffer(RgbaImageBuffer buffer) {
    final ex = beautyExcludeMask;
    if (ex == null || !BeautyExcludeMask.hasEffect(ex)) return null;
    if (ex.width == buffer.width && ex.height == buffer.height) return ex;
    return BeautyExcludeMask.scaledTo(
      source: ex,
      width: buffer.width,
      height: buffer.height,
    );
  }

  /// Regional beauty sliders (Nexus B). Mask must exist from [analyzeFaceForBeauty].
  Future<void> setBeautyParams(
    BeautyParams params, {
    bool livePreview = false,
    bool commit = false,
  }) async {
    if (!hasWorkingImage) return;
    final p = params.clamped();

    if (liveCameraActive) {
      if (livePreview && !commit) {
        _previewBeautyParams = p;
        previewBeautyLook = beautyLookMatching(p);
        _beautyDebounceTimer?.cancel();
        _bumpBeautyPreview();
        return;
      }
      if (commit) {
        _beautyDebounceTimer?.cancel();
        _previewBeautyParams = null;
        previewBeautyLook = beautyLookMatching(p);
        editGraph = editGraph.replaceBeautyParams(p.hasEffect ? p : null);
        final look = previewBeautyLook;
        status = p.hasEffect
            ? 'Live · ${look != null ? beautyLookLabel(look) : 'beauty on'}'
            : 'Live camera · front';
        _bumpStatus();
        notifyListeners();
      }
      return;
    }

    if (skinMask == null) return;

    if (livePreview && !commit) {
      _previewBeautyParams = p;
      previewBeautyLook = beautyLookMatching(p);
      _bumpBeautyPreview();
      _beautyDebounceTimer?.cancel();
      _beautyDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        unawaited(_replayBeautyOnly());
      });
      return;
    }

    if (!commit) return;

    _beautyDebounceTimer?.cancel();
    _previewBeautyParams = null;
    previewBeautyLook = beautyLookMatching(p);
    final next = editGraph.replaceBeautyParams(p.hasEffect ? p : null);
    if (next == editGraph) {
      notifyListeners();
      return;
    }

    cancelDebounced();
    final gen = ++_opGeneration;
    status = p.hasEffect ? 'Beauty…' : 'Beauty off';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();
    if (gen != _opGeneration) {
      _endHistoryOp(gen);
      return;
    }

    try {
      if (rgbaBase != null) {
        _pushGraphUndo();
        editGraph = next;
        await _replayPreview(gen: gen);
        if (gen == _opGeneration) {
          final path = showPerformanceInStatus && lastBeautyPath != null
              ? ' · $lastBeautyPath'
              : '';
          status = p.hasEffect
              ? 'Beauty applied${_gpuBeautyPathSuffix(p)}$path'
              : 'Beauty off';
        }
      }
    } catch (e) {
      if (gen == _opGeneration) {
        status = 'Beauty failed: $e';
      }
    } finally {
      _endHistoryOp(gen);
    }
    notifyListeners();
  }

  /// One-tap beauty look (Nexus C). Null = Original (clear beauty).
  Future<void> setBeautyLook(
    BeautyLookPreset? look, {
    bool livePreview = false,
    bool commit = false,
  }) async {
    previewBeautyLook = look;
    _bumpBeautyPreview();
    final params = look == null
        ? BeautyParamsX.zero
        : beautyParamsForLookPreset(look);
    await setBeautyParams(
      params,
      livePreview: livePreview,
      commit: commit,
    );
    if (commit || livePreview) {
      _bumpFaceChrome();
    }
  }

  /// Revert live look swipe to committed beauty state.
  Future<void> cancelBeautyLookPreview() async {
    previewBeautyLook = committedBeautyLook;
    _previewBeautyParams = null;
    _bumpBeautyPreview();
    if (!hasWorkingImage || rgbaBase == null) return;
    await _replayPreview(previewEdge: liveEditMaxEdge);
  }

  /// Skin smooth only — convenience wrapper for [setBeautyParams].
  Future<void> setSkinSmoothStrength(
    double strength, {
    bool livePreview = false,
    bool commit = false,
  }) {
    final current = _previewBeautyParams ??
        committedBeautyParams ??
        BeautyParamsX.zero;
    return setBeautyParams(
      current.copyWith(skinSmooth: strength.clamp(0.0, 1.0)),
      livePreview: livePreview,
      commit: commit,
    );
  }

  BeautyParams? _activeBeautyParams() {
    final preview = _previewBeautyParams;
    if (preview != null) return preview;
    return committedBeautyParams;
  }

  /// wgpu beauty available (Sprint 22 — independent of Flutter Texture).
  bool _gpuBeautyComputeAvailable() {
    if (backend == ProcessingBackend.cpu) return false;
    return isGpuTexturePreviewAvailable();
  }

  /// Flutter [Texture] display (macOS/iOS); optional when compute is GPU.
  bool _gpuBeautyDisplayViaTexture() =>
      useGpuTexturePreview && gpuTexturePreviewSupported();

  bool _beautyNeedsCpuPipeline(BeautyParams? params) {
    if (params == null || !params.hasEffect) return false;
    if (_gpuBeautyComputeAvailable()) return false;
    return true;
  }

  /// Status suffix when beauty runs on GPU WGSL (Nexus D acceptance).
  String _gpuBeautyPathSuffix(BeautyParams p) {
    if (!_gpuBeautyComputeAvailable() || !p.hasEffect) return '';
    final parts = <String>[];
    if (p.skinSmooth > 0.001) parts.add('gpu_skin');
    if (p.eyeBrighten > 0.001) parts.add('gpu_eye');
    if (p.lipTint != LipTintPreset.none && p.lipTintStrength > 0.001) {
      parts.add('gpu_lip');
    }
    if (p.blush > 0.001) parts.add('gpu_blush');
    if (p.teethWhiten > 0.001) parts.add('gpu_teeth');
    if (p.underEye > 0.001) parts.add('gpu_under_eye');
    if (p.lipPlump > 0.001) parts.add('gpu_plump');
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }

  Future<void> _applyGpuBeautyPipeline({
    required PlatformInt64 handle,
    required RgbaImageBuffer buffer,
    required SegmentationMask skinMask,
    required FaceAnalysisResult analysis,
    required BeautyParams params,
  }) async {
    // Zero-copy path: write beauty output directly into the Flutter
    // display's IOSurface-backed Metal texture, skipping the CPU readback.
    if (await _ensureZeroCopyOutputTexture(handle)) {
      await applyGpuBeautyPipelineZeroCopy(
        id: handle,
        analysis: analysis,
        skinMask: skinMask,
        params: params,
        excludeMask: _beautyExcludeForBuffer(buffer),
      );
      return;
    }
    await applyGpuBeautyPipeline(
      id: handle,
      analysis: analysis,
      skinMask: skinMask,
      params: params,
      excludeMask: _beautyExcludeForBuffer(buffer),
    );
  }

  /// Lazily attach a zero-copy output texture for [handle]. Returns true if
  /// the output texture is now attached and zero-copy dispatches will land
  /// directly in the Flutter display IOSurface. The result is sticky for
  /// the lifetime of [gpuPreviewHandle].
  Future<bool> _ensureZeroCopyOutputTexture(PlatformInt64 handle) async {
    if (!_gpuBeautyDisplayViaTexture() || gpuTextureId == null) return false;
    if (_zeroCopyAvailable != true) {
      _zeroCopyAvailable = isZeroCopyBeautyAvailable();
    }
    if (_zeroCopyAvailable != true) return false;
    if (_zeroCopyAttachedFor == handle) return true;
    final ptrs = await GpuTextureRegistry.getMetalTexturePtrForBeauty(
      handle: handle.toInt(),
    );
    if (ptrs == null) {
      _zeroCopyAvailable = false;
      return false;
    }
    try {
      await attachZeroCopyOutputTexture(
        id: handle,
        mtlTexturePtr: BigInt.from(ptrs.metalTexturePtr),
        pixelBufferPtr: BigInt.from(ptrs.pixelBufferPtr),
      );
      _zeroCopyAttachedFor = handle;
      return true;
    } catch (_) {
      _zeroCopyAvailable = false;
      return false;
    }
  }

  /// Skin mask at [buffer] resolution (rebuilds from landmarks when sizes differ).
  Future<SegmentationMask?> _maskForBuffer(RgbaImageBuffer buffer) async {
    final cached = skinMask;
    if (cached != null &&
        cached.width == buffer.width &&
        cached.height == buffer.height) {
      return cached;
    }
    final analysis = faceAnalysis;
    if (analysis == null || !FaceAnalysisService.isAnalysisValid(analysis)) {
      return cached;
    }
    await RustWorker.ensureStarted();
    return RustWorker.buildSkinMaskFromAnalysis(
      analysis: analysis,
      width: buffer.width,
      height: buffer.height,
    );
  }

  Future<RgbaImageBuffer> _applyBeautyAsync(RgbaImageBuffer buffer) async {
    final params = _activeBeautyParams();
    if (params == null || !params.hasEffect) {
      return buffer;
    }
    final mask = await _maskForBuffer(buffer);
    final analysis = faceAnalysis;
    if (mask == null ||
        analysis == null ||
        !FaceAnalysisService.isAnalysisValid(analysis)) {
      return buffer;
    }
    await RustWorker.ensureStarted();
    return RustWorker.applyBeauty(
      buffer: buffer,
      analysis: analysis,
      skinMask: mask,
      params: params,
      excludeMask: _beautyExcludeForBuffer(buffer),
    );
  }

  /// Live beauty slider — re-smooth cached pipeline output only (no full graph replay).
  Future<void> _replayBeautyOnly({int? gen}) async {
    try {
      await _replayBeautyOnlyImpl(gen: gen);
    } on CoalesceCancelledException {
      return;
    }
  }

  Future<void> _replayBeautyOnlyImpl({int? gen}) async {
    final g = gen ?? _opGeneration;
    var base = _beautyPipelineBase ?? rgbaEditBase;
    if (base == null) {
      await _replayPreview(gen: g);
      return;
    }
    beautyCompareRgba = base;

    if (_gpuBeautyComputeAvailable() &&
        !_beautyNeedsCpuPipeline(_activeBeautyParams())) {
      await _yieldToUi();
      if (g != _opGeneration) return;
      try {
        await _ensureGpuSurface(base);
        final handle = gpuPreviewHandle;
        if (handle != null) {
          await uploadGpuPreviewSurface(id: handle, buffer: base);
          if (g != _opGeneration) return;
          await applyGpuPreviewOps(
            id: handle,
            ops: editGraph.ops,
            backend: backend,
          );
          if (g != _opGeneration) return;
          final params = _activeBeautyParams();
          final mask = await _maskForBuffer(base);
          if (g != _opGeneration) return;
          final analysis = faceAnalysis;
          if (params != null &&
              params.hasEffect &&
              mask != null &&
              analysis != null &&
              FaceAnalysisService.isAnalysisValid(analysis)) {
            await _applyGpuBeautyPipeline(
              handle: handle,
              buffer: base,
              skinMask: mask,
              analysis: analysis,
              params: params,
            );
            if (g != _opGeneration) return;
          }
          await _syncGpuPreviewAfterBeauty(
            handle: handle,
            params: params,
            gen: g,
          );
          return;
        }
      } catch (_) {
        // Fall through to CPU beauty path.
      }
    }

    final params = _activeBeautyParams();
    if (params == null || !params.hasEffect) {
      if (g != _opGeneration) return;
      rgbaBuffer = base;
      previewRgba = base;
      notifyPreviewChanged();
      return;
    }

    await _yieldToUi();
    if (g != _opGeneration) return;

    final mask = await _maskForBuffer(base);
    if (mask == null) {
      if (g != _opGeneration) return;
      rgbaBuffer = base;
      previewRgba = base;
      notifyPreviewChanged();
      return;
    }

    final analysis = faceAnalysis;
    if (analysis == null || !FaceAnalysisService.isAnalysisValid(analysis)) {
      if (g != _opGeneration) return;
      rgbaBuffer = base;
      previewRgba = base;
      notifyPreviewChanged();
      return;
    }

    final beautified = await RustWorker.applyBeauty(
      buffer: base,
      analysis: analysis,
      skinMask: mask,
      params: params,
      excludeMask: _beautyExcludeForBuffer(base),
    );
    if (g != _opGeneration) return;
    lastBeautyPath = 'cpu_beauty';
    rgbaBuffer = beautified;
    previewRgba = beautified;
    if (g == _opGeneration && params.hasEffect) {
      status = showPerformanceInStatus
          ? 'Beauty · cpu_beauty'
          : 'Beauty';
      _bumpStatus();
    }
    notifyPreviewChanged();
  }

  /// Readback GPU surface and publish to Texture and/or [previewRgba] (Sprint 22.2).
  ///
  /// Zero-copy path: when an output texture is attached, the beauty
  /// compute already wrote the result into the Flutter display IOSurface
  /// during `_applyGpuBeautyPipeline`. We just call `notifyFrameAvailable`
  /// and skip the CPU readback entirely.
  Future<void> _syncGpuPreviewAfterBeauty({
    required PlatformInt64 handle,
    BeautyParams? params,
    int? gen,
  }) async {
    final g = gen ?? _opGeneration;
    final zeroCopy = _zeroCopyAttachedFor == handle &&
        _gpuBeautyDisplayViaTexture() &&
        gpuTextureId != null;

    if (zeroCopy) {
      // The beauty result is already in the Flutter display texture; no
      // readback needed. Just notify the platform to redraw.
      if (g != _opGeneration) return;
      previewRgba = null;
      // Lazy copy: the cached display buffer would normally be populated
      // from readback. We don't have it, so we leave rgbaBuffer as-is —
      // compare / export paths that need RGBA pixels will go through
      // readback explicitly.
      await GpuTextureRegistry.notifyFrameAvailable(handle.toInt());
      if (!_isDisposed) {
        gpuTextureListenable.value = gpuTextureId!;
      }
      lastBeautyPath = 'gpu_beauty_zero_copy';
      if (g == _opGeneration && params != null && params.hasEffect) {
        final path = showPerformanceInStatus ? ' · zero_copy_beauty' : '';
        status = 'Beauty${_gpuBeautyPathSuffix(params)}$path';
        _bumpStatus();
      }
      notifyPreviewChanged();
      return;
    }

    final displayRb = await readbackGpuPreviewSurface(id: handle);
    if (g != _opGeneration) return;

    rgbaBuffer = displayRb;
    final textureDisplay = _gpuBeautyDisplayViaTexture() &&
        gpuTextureId != null &&
        gpuTextureId! > 0;

    if (textureDisplay) {
      // Phase 2: Flutter Texture is authoritative — skip RgbaPreviewImage hot path.
      previewRgba = null;
      await GpuTextureRegistry.updateTexture(
        handle: handle.toInt(),
        pixels: displayRb.pixels,
      );
      if (!_isDisposed) {
        gpuTextureListenable.value = gpuTextureId!;
      }
    } else {
      previewRgba = displayRb;
    }

    lastBeautyPath = 'gpu_beauty';
    if (g == _opGeneration && params != null && params.hasEffect) {
      final path = showPerformanceInStatus ? ' · gpu_beauty' : '';
      status = 'Beauty${_gpuBeautyPathSuffix(params)}$path';
      _bumpStatus();
    }
    notifyPreviewChanged();
  }

  /// Swipe mood filter on preview (Instagram-style). Live while dragging; commit on release.
  Future<void> setMoodFilter({
    MoodFilterPreset? preset,
    double strength = 1.0,
    bool livePreview = false,
    bool commit = false,
  }) async {
    if (!hasWorkingImage) return;

    if (livePreview && !commit) {
      previewMoodPreset = preset;
      _bumpMoodPreview();
      _moodDebounceTimer?.cancel();
      _moodDebounceTimer = Timer(const Duration(milliseconds: 60), () {
        unawaited(_previewMoodFilter(preset, strength));
      });
      return;
    }

    if (!commit) return;

    _moodDebounceTimer?.cancel();
    previewMoodPreset = preset;
    await _commitMoodFilter(preset, strength);
  }

  /// Revert live swipe preview to the committed mood filter (drag cancelled).
  Future<void> cancelMoodPreview() async {
    previewMoodPreset = committedMoodPreset;
    _bumpMoodPreview();
    if (!hasWorkingImage || rgbaBase == null) return;
    await _replayPreview(previewEdge: liveEditMaxEdge);
  }

  Future<void> _previewMoodFilter(
    MoodFilterPreset? preset,
    double strength,
  ) async {
    if (!hasWorkingImage || rgbaBase == null) return;
    final liveFilter = preset != null
        ? FilterDescriptor.mood(preset, strength: strength)
        : null;
    await _replayPreview(
      liveFilter: liveFilter,
      previewEdge: liveEditMaxEdge,
      excludeCommittedMood: true,
    );
  }

  Future<void> _commitMoodFilter(
    MoodFilterPreset? preset,
    double strength,
  ) async {
    final descriptor = preset != null
        ? FilterDescriptor.mood(preset, strength: strength)
        : null;
    final next = editGraph.replaceMoodFilter(descriptor);
    if (next == editGraph) {
      notifyListeners();
      return;
    }

    cancelDebounced();
    final gen = ++_opGeneration;
    status = preset != null ? 'Mood…' : 'Original…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();
    if (gen != _opGeneration) {
      _endHistoryOp(gen);
      return;
    }

    try {
      if (rgbaBase != null) {
        _pushGraphUndo();
        editGraph = next;
        await _replayPreview(gen: gen);
        if (gen == _opGeneration) {
          status = preset != null ? 'Mood filter' : 'Original';
        }
      }
    } catch (e) {
      if (gen == _opGeneration) {
        status = 'Mood failed: $e';
      }
    } finally {
      _endHistoryOp(gen);
    }
    notifyListeners();
  }

  /// Combo swipe look (global grade + beauty). Live while dragging; commit on release.
  Future<void> setSwipeLook({
    SwipeLookPreset? look,
    double strength = 1.0,
    bool livePreview = false,
    bool commit = false,
  }) async {
    if (!hasWorkingImage) return;

    if (livePreview && !commit) {
      previewSwipeLook = look;
      _bumpSwipeLookPreview();
      _previewBeautyParams =
          look == null ? null : swipeLookBeautyParamsFor(look);
      _swipeLookDebounceTimer?.cancel();
      _swipeLookDebounceTimer = Timer(const Duration(milliseconds: 60), () {
        unawaited(_previewSwipeLook(look, strength));
      });
      return;
    }

    if (!commit) return;

    _swipeLookDebounceTimer?.cancel();
    previewSwipeLook = look;
    _previewBeautyParams = null;
    await _commitSwipeLook(look, strength);
  }

  /// Revert live swipe look preview to committed state (drag cancelled).
  Future<void> cancelSwipeLookPreview() async {
    previewSwipeLook = committedSwipeLookPreset;
    _previewBeautyParams = null;
    _bumpSwipeLookPreview();
    if (!hasWorkingImage || rgbaBase == null) return;
    await _replayPreview(previewEdge: liveEditMaxEdge);
  }

  Future<void> _previewSwipeLook(
    SwipeLookPreset? look,
    double strength,
  ) async {
    if (!hasWorkingImage || rgbaBase == null) return;
    if (look != null &&
        FaceAnalysisService.isSupported &&
        !FaceAnalysisService.isAnalysisValid(faceAnalysis)) {
      await analyzeFaceForBeauty();
    }
    final liveFilter = look != null
        ? FilterDescriptor.swipeLook(look, strength: strength)
        : null;
    _previewBeautyParams =
        look == null ? null : swipeLookBeautyParamsFor(look);
    await _replayPreview(
      liveFilter: liveFilter,
      previewEdge: liveEditMaxEdge,
      excludeCommittedSwipeLook: true,
      excludeCommittedBeauty: true,
    );
  }

  Future<void> _commitSwipeLook(
    SwipeLookPreset? look,
    double strength,
  ) async {
    final swipeDescriptor = look != null
        ? FilterDescriptor.swipeLook(look, strength: strength)
        : null;
    final beauty = look == null ? null : swipeLookBeautyParamsFor(look);
    final nextSwipe = editGraph.replaceSwipeLookFilter(swipeDescriptor);
    final next = nextSwipe.replaceBeautyParams(
      beauty != null && beauty.hasEffect ? beauty : null,
    );
    if (next == editGraph) {
      notifyListeners();
      return;
    }

    cancelDebounced();
    final gen = ++_opGeneration;
    status = look != null
        ? swipeLookDisplayNameFor(look)
        : 'Original…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();
    if (gen != _opGeneration) {
      _endHistoryOp(gen);
      return;
    }

    try {
      if (rgbaBase != null) {
        if (look != null &&
            FaceAnalysisService.isSupported &&
            !FaceAnalysisService.isAnalysisValid(faceAnalysis)) {
          await analyzeFaceForBeauty();
        }
        _pushGraphUndo();
        editGraph = next;
        await _replayPreview(gen: gen);
        if (gen == _opGeneration) {
          if (look != null) {
            final faceOk = FaceAnalysisService.isAnalysisValid(faceAnalysis) &&
                skinMask != null;
            status = faceOk
                ? swipeLookDisplayNameFor(look)
                : '${swipeLookDisplayNameFor(look)} · no face';
          } else {
            status = 'Original';
          }
        }
      }
    } catch (e) {
      if (gen == _opGeneration) {
        status = 'Look failed: $e';
      }
    } finally {
      _endHistoryOp(gen);
    }
    notifyListeners();
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
          await _yieldToUi();
          if (gen != _opGeneration) return;
          _pushGraphUndo();
          editGraph = editGraph.appendFilter(descriptor);
        }
        await _replayPreview(
          gen: gen,
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
          _applyGraphState(prev);
        } else if (_undo.isNotEmpty) {
          _undo.removeLast();
        }
      }
      status = '$label failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        _bumpStatus();
      }
    }
  }

  RgbaImageBuffer _editBaseUnfiltered() {
    if (rgbaEditBase != null) return rgbaEditBase!;
    if (rgbaBase == null) {
      throw StateError('No RGBA base');
    }
    throw StateError('Edit base not prepared');
  }

  EditGraphState _captureGraphState() => EditGraphState(
        graph: editGraph.copy(),
        bakedFull: rgbaBase != null ? _cloneRgba(rgbaBase!) : null,
        bakedEdit: rgbaEditBase != null ? _cloneRgba(rgbaEditBase!) : null,
      );

  /// Snapshot current graph + pixel bases (moves buffers — no copy).
  EditGraphState _detachGraphState() => EditGraphState(
        graph: editGraph.copy(),
        bakedFull: rgbaBase,
        bakedEdit: rgbaEditBase,
      );

  /// Restore graph snapshot; takes ownership of stacked buffers.
  void _applyGraphState(EditGraphState state) {
    editGraph = state.graph.copy();
    rgbaBase = state.bakedFull;
    rgbaEditBase = state.bakedEdit;
    rgbaBuffer = null;
    previewRgba = null;
    previewMoodPreset = editGraph.committedMoodPreset;
    previewSwipeLook = editGraph.committedSwipeLookPreset;
    _beautyPipelineBase = null;
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
    int? gen,
    bool excludeCommittedMood = false,
    bool excludeCommittedSwipeLook = false,
    bool excludeCommittedBeauty = false,
  }) async {
    final g = gen ?? _opGeneration;
    final base = _editBaseUnfiltered();
    if (g != _opGeneration) return;
    var graph = editGraph;
    if (excludeCommittedMood) graph = graph.withoutMoodFilter();
    if (excludeCommittedSwipeLook) graph = graph.withoutSwipeLookFilter();
    if (excludeCommittedBeauty) graph = graph.withoutBeautyFilter();
    final graphOps = graph.ops;
    final ops = <EditOp>[...graphOps];
    if (liveFilter != null) {
      ops.add(EditOp.filter(filter: liveFilter.toImageFilter()));
    }
    if (_gpuBeautyComputeAvailable() &&
        !_beautyNeedsCpuPipeline(_activeBeautyParams())) {
      try {
        await _ensureGpuSurface(base);
        final handle = gpuPreviewHandle;
        if (handle != null) {
          if (g != _opGeneration) return;
          await uploadGpuPreviewSurface(id: handle, buffer: base);
          if (g != _opGeneration) return;
          await applyGpuPreviewOps(id: handle, ops: ops, backend: backend);
          if (g != _opGeneration) return;
          final params = _activeBeautyParams();
          final mask = await _maskForBuffer(base);
          if (g != _opGeneration) return;
          final analysis = faceAnalysis;
          final needsBeauty = params != null &&
              params.hasEffect &&
              mask != null &&
              analysis != null &&
              FaceAnalysisService.isAnalysisValid(analysis);
          if (needsBeauty) {
            await _applyGpuBeautyPipeline(
              handle: handle,
              buffer: base,
              skinMask: mask,
              analysis: analysis,
              params: params,
            );
            if (g != _opGeneration) return;
          }
          final displayRb = await readbackGpuPreviewSurface(id: handle);
          if (g != _opGeneration) return;
          if (ops.isNotEmpty || needsBeauty) {
            _beautyPipelineBase = needsBeauty ? null : displayRb;
          }
          lastBeautyPath = 'gpu_beauty';
          rgbaBuffer = displayRb;
          final textureDisplay = _gpuBeautyDisplayViaTexture() &&
              gpuTextureId != null &&
              gpuTextureId! > 0;
          if (textureDisplay) {
            previewRgba = null;
            await GpuTextureRegistry.updateTexture(
              handle: handle.toInt(),
              pixels: displayRb.pixels,
            );
            if (!_isDisposed) {
              gpuTextureListenable.value = gpuTextureId!;
            }
          } else {
            previewRgba = displayRb;
          }
          notifyPreviewChanged();
          return;
        }
      } catch (e) {
        status = 'GPU preview failed — RGBA fallback: $e';
        _bumpStatus();
        _disposeGpuSurface();
      }
    }
    final edge = previewEdge ?? previewMaxEdge;
    try {
      final result = await RustWorker.replayEditPipeline(
        base: base,
        ops: ops,
        backend: backend,
        previewMaxEdge: edge,
        previewQuality: previewQuality,
        encodePreviewJpeg: !useRgbaPreview,
      );
      if (g != _opGeneration) return;
      lastProfile = result.profile;
      _beautyPipelineBase = result.buffer;
      final smoothed = await _applyBeautyAsync(result.buffer);
      if (g != _opGeneration) return;
      if (_beautyNeedsCpuPipeline(_activeBeautyParams())) {
        lastBeautyPath = 'cpu_beauty';
      }
      rgbaBuffer = smoothed;
      previewRgba = smoothed;
      if (result.preview != null) {
        displayBytes = result.preview;
      }
      notifyPreviewChanged();
    } on CoalesceCancelledException {
      return;
    }
  }

  void _disposeGpuSurface() {
    final handle = gpuPreviewHandle;
    if (handle != null) {
      // Detach the zero-copy output texture before destroying the surface.
      if (_zeroCopyAttachedFor != null) {
        detachZeroCopyOutputTexture(id: handle).catchError((e) {
          debugPrint('[EditorSession] Ignored detach error: $e');
        });
        _zeroCopyAttachedFor = null;
      }
      destroyGpuPreviewSurface(id: handle);
      GpuTextureRegistry.disposeTexture(handle.toInt()).catchError((e) {
        debugPrint('[EditorSession] Ignored dispose texture error: $e');
      });
      gpuPreviewHandle = null;
      gpuTextureId = null;
      if (!_isDisposed) {
        gpuTextureListenable.value = 0;
      }
    }
  }

  Future<void> _ensureGpuSurface(RgbaImageBuffer base) async {
    if (gpuPreviewHandle != null) return;
    final handle = createGpuPreviewSurface(
      width: base.width,
      height: base.height,
    );
    gpuPreviewHandle = handle;
    if (_gpuBeautyDisplayViaTexture()) {
      final texId = await GpuTextureRegistry.createTexture(
        handle: handle.toInt(),
        width: base.width,
        height: base.height,
      );
      gpuTextureId = texId;
      if (!_isDisposed) {
        gpuTextureListenable.value = texId ?? 0;
      }
    }
  }

  /// Bake stickers, text, and paint into image pixels so filters/beauty apply to
  /// the whole canvas. Clears layer undo; layer strokes can no longer be undone.
  Future<void> commitLayersToCanvas() async {
    if (!hasImage || layerStack.isEmpty || busy) return;

    final gen = ++_opGeneration;
    status = 'Applying layers…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      await _ensureRgbaReady();
      await RustWorker.ensureStarted();
      final full = rgbaBase;
      if (full == null) return;

      await _bakeGraphIntoFullBase();

      rgbaBase = await LayerBake.bakeOnto(rgbaBase!, layerStack);

      layerStack = LayerStack();
      _undoLayers.clear();
      _redoLayers.clear();

      final prepared = await RustWorker.prepareEditBaseFromRgba(
        buffer: rgbaBase!,
        liveEditMaxEdge: liveEditMaxEdge,
      );
      rgbaEditBase = prepared.edit;
      rgbaBuffer = prepared.edit;
      previewRgba = prepared.edit;
      rgbaPipeline = true;

      if (!useRgbaPreview) {
        displayBytes = await RustWorker.encodePreview(
          buffer: prepared.edit,
          previewMaxEdge: previewMaxEdge,
          quality: quality,
        );
      }
      imageInfo = ImageInfo(
        width: rgbaBase!.width,
        height: rgbaBase!.height,
        format: imageInfo?.format,
      );

      _beautyPipelineBase = null;
      _disposeGpuSurface();
      if (gen != _opGeneration) return;
      await _replayPreview(gen: gen);

      notifyPreviewChanged();
      notifyLayerChanged();
      lastDuration = sw.elapsed;
      status =
          'Layers applied · ${sw.elapsedMilliseconds} ms · filters affect whole image';
    } catch (e) {
      status = 'Apply layers failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        _bumpStatus();
        notifyListeners();
      }
    }
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
    final prepared = await RustWorker.prepareEditBaseFromRgba(
      buffer: rgbaBase!,
      liveEditMaxEdge: liveEditMaxEdge,
    );
    rgbaEditBase = prepared.edit;
    rgbaBuffer = prepared.edit;
  }

  /// Map [CropController] rect from preview/edit space into [buffer] pixel coordinates.
  static ({int x, int y, int width, int height}) cropRectForBuffer({
    required CropController crop,
    required RgbaImageBuffer buffer,
  }) {
    final spaceW = crop.imageWidth;
    final spaceH = crop.imageHeight;
    if (spaceW <= 0 || spaceH <= 0) {
      return (x: 0, y: 0, width: buffer.width, height: buffer.height);
    }
    final sx = buffer.width / spaceW;
    final sy = buffer.height / spaceH;
    final x = (crop.cropX * sx).round().clamp(0, buffer.width - 1);
    final y = (crop.cropY * sy).round().clamp(0, buffer.height - 1);
    final w = (crop.cropW * sx).round().clamp(1, buffer.width - x);
    final h = (crop.cropH * sy).round().clamp(1, buffer.height - y);
    return (x: x, y: y, width: w, height: h);
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
      previewRgba = null;
      rgbaBuffer = null;
      rgbaBase = null;
      rgbaEditBase = null;
      rgbaPipeline = false;
      editGraph = EditGraph();
      _undoGraph.clear();
      _redoGraph.clear();
      imageInfo = RustImageEditor.probe(out);
      await _rebuildRgbaPipelineFromDisplay();
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
      final prepared = await RustWorker.prepareEditBaseFromRgba(
        buffer: result.buffer,
        liveEditMaxEdge: liveEditMaxEdge,
      );
      rgbaBase = prepared.base;
      rgbaEditBase = prepared.edit;
      previewRgba = prepared.edit;
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
        final prepared = await RustWorker.prepareEditBaseFromRgba(
          buffer: result.buffer,
          liveEditMaxEdge: liveEditMaxEdge,
        );
        rgbaBase = prepared.base;
        rgbaEditBase = prepared.edit;
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
  void scheduleOverlayLivePreview(OverlayPlacementController placement) {
    final sticker = overlayStickerBytes;
    if (sticker == null || !hasImage) return;

    placement.normalize();
    final x = placement.x;
    final y = placement.y;
    final ow = placement.overlayWidth;
    final oh = placement.overlayHeight;

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
            overlayWidth: ow,
            overlayHeight: oh,
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
    final prepared = await RustWorker.decodeAndPrepareEditBase(
      bytes: bytes,
      liveEditMaxEdge: liveEditMaxEdge,
    );
    rgbaBase = prepared.base;
    rgbaEditBase = prepared.edit;
    rgbaBuffer = prepared.edit;
    previewRgba = prepared.edit;
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
      final prepared = await RustWorker.prepareEditBaseFromRgba(
        buffer: result.buffer,
        liveEditMaxEdge: liveEditMaxEdge,
      );
      rgbaBase = prepared.base;
      rgbaEditBase = prepared.edit;
      previewRgba = prepared.edit;
      rgbaPipeline = true;
      displayBytes = result.preview;
      if (displayBytes != null) {
        imageInfo = RustImageEditor.probe(displayBytes!);
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

  /// Commit crop box (and pending straighten) into pixels; resets filters/layers for new canvas.
  Future<void> applyCrop({required CropController crop}) async {
    if (!hasImage) return;
    cancelDebounced();

    final aspect = crop.aspect;
    final straighten = crop.straightenDegrees;
    final spaceW = crop.imageWidth;
    final spaceH = crop.imageHeight;

    final noPixelChange = straighten.abs() < 0.05 &&
        crop.cropX == 0 &&
        crop.cropY == 0 &&
        crop.cropW == spaceW &&
        crop.cropH == spaceH;
    if (noPixelChange || spaceW <= 0 || spaceH <= 0) return;

    if (rgbaBase == null && rgbaBuffer == null && displayBytes != null) {
      await _ensureRgbaReady();
    }
    if (rgbaBase == null && rgbaBuffer == null) return;

    final gen = ++_opGeneration;
    status = 'Crop…';
    _setProcessing(true);
    _bumpStatus();
    await _yieldToUi();

    final sw = Stopwatch()..start();
    try {
      if (rgbaPipeline) {
        _pushGraphUndo();
      } else {
        _pushUndo();
      }
      _undoLayers.add(layerStack.copy());
      if (_undoLayers.length > _maxUndo) {
        _undoLayers.removeAt(0);
      }

      await RustWorker.ensureStarted();
      await _bakeGraphIntoFullBase();

      // Crop edit-scale pixels (matches overlay); avoid full-res [rgbaBase] on UI thread.
      final working = rgbaBuffer ?? rgbaEditBase ?? rgbaBase;
      if (working == null) return;

      final rect = cropRectForBuffer(crop: crop, buffer: working);
      final result = await RustWorker.applyCropRgba(
        buffer: working,
        straightenDegrees: straighten,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        liveEditMaxEdge: liveEditMaxEdge,
        previewMaxEdge: previewMaxEdge,
        previewQuality: previewQuality,
      );
      if (gen != _opGeneration) return;

      rgbaBase = result.base;
      rgbaEditBase = result.edit;
      rgbaBuffer = result.edit;
      previewRgba = rgbaBuffer;
      rgbaPipeline = true;
      displayBytes = result.preview;
      imageInfo = ImageInfo(
        width: result.base.width,
        height: result.base.height,
        format: imageInfo?.format,
      );
      notifyPreviewChanged();

      editGraph = EditGraph();
      _undoGraph.clear();
      _redoGraph.clear();
      layerStack = LayerStack();
      notifyLayerChanged();

      crop.resetStraighten();
      crop.syncImageSize(rgbaBuffer!.width, rgbaBuffer!.height);
      crop.setAspect(aspect);

      lastDuration = sw.elapsed;
      status = 'Crop · ${sw.elapsedMilliseconds} ms';
    } catch (e) {
      if (_undo.isNotEmpty) _undo.removeLast();
      status = 'Crop failed: $e';
    } finally {
      if (gen == _opGeneration) {
        _setProcessing(false);
        notifyListeners();
      }
    }
  }

  /// Bake straighten rotation into pixels, crop, and re-fit crop rect (Sprint 10).
  Future<void> applyStraighten({required CropController crop}) async {
    if (crop.straightenDegrees.abs() < 0.05) return;
    await applyCrop(crop: crop);
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
      
      final beautyParams = editGraph.committedBeautyParams;
      final analysis = faceAnalysis;
      final needsBeauty = beautyParams != null &&
          beautyParams.hasEffect &&
          analysis != null &&
          FaceAnalysisService.isAnalysisValid(analysis);

      final (finalW, finalH) = _calculateOutputSize(base.width, base.height, editGraph.ops);

      final Future<RgbaImageBuffer> pipelineFuture = editGraph.isNotEmpty
          ? RustWorker.applyEditPipelineFull(
              base: base,
              ops: editGraph.ops,
              backend: backend,
            )
          : Future.value(base);

      final Future<SegmentationMask?> maskFuture = needsBeauty
          ? RustWorker.buildSkinMaskFromAnalysis(
              analysis: analysis,
              width: finalW,
              height: finalH,
            )
          : Future.value(null);

      final layerInputsFuture = layerStack.isNotEmpty
          ? LayerBake.prepareInputs(layerStack)
          : Future.value((
              rasterLayers: <RasterLayerInput>[],
              paintStrokes: <PaintStrokeInput>[],
            ));

      final results = await Future.wait([
        pipelineFuture,
        maskFuture,
        layerInputsFuture,
      ]);
      var exportBuf = results[0] as RgbaImageBuffer;
      final exportMask = results[1] as SegmentationMask?;
      final layerInputs = results[2] as ({
        List<RasterLayerInput> rasterLayers,
        List<PaintStrokeInput> paintStrokes,
      });

      if (layerInputs.rasterLayers.isNotEmpty ||
          layerInputs.paintStrokes.isNotEmpty) {
        exportBuf = await RustWorker.bakeLayersRgba(
          buffer: exportBuf,
          rasterLayers: layerInputs.rasterLayers,
          paintStrokes: layerInputs.paintStrokes,
        );
      }

      if (needsBeauty && exportMask != null) {
        exportBuf = await RustWorker.applyBeauty(
          buffer: exportBuf,
          analysis: analysis,
          skinMask: exportMask,
          params: beautyParams,
          excludeMask: _beautyExcludeForBuffer(exportBuf),
        );
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

  Future<void> _rebuildRgbaPipelineFromDisplay() async {
    final bytes = displayBytes;
    if (bytes == null) return;
    try {
      await RustWorker.ensureStarted();
      final prepared = await RustWorker.decodeAndPrepareEditBase(
        bytes: bytes,
        liveEditMaxEdge: liveEditMaxEdge,
      );
      rgbaBase = prepared.base;
      rgbaEditBase = prepared.edit;
      rgbaBuffer = prepared.edit;
      previewRgba = prepared.edit;
      rgbaPipeline = true;
      notifyPreviewChanged();
    } catch (_) {
      rgbaPipeline = false;
      previewRgba = null;
    }
  }

  Future<void> _refreshRgbaFromDisplay() => _rebuildRgbaPipelineFromDisplay();

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

  static (int, int) _calculateOutputSize(int inputWidth, int inputHeight, List<EditOp> ops) {
    var w = inputWidth;
    var h = inputHeight;
    for (final op in ops) {
      if (op is EditOp_Resize) {
        w = op.width;
        h = op.height;
      } else if (op is EditOp_Crop) {
        w = op.width;
        h = op.height;
      } else if (op is EditOp_Rotate) {
        if (op.rotation == Rotation.rotate90 || op.rotation == Rotation.rotate270) {
          final tmp = w;
          w = h;
          h = tmp;
        }
      }
    }
    return (w, h);
  }
}

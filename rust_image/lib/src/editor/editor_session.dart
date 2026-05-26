import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:rust_image/src/rust/api/advanced.dart';
import 'package:rust_image/src/rust/api/face.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import 'crop_controller.dart';
import 'overlay_placement.dart';
import 'models/beauty_params.dart';
import 'models/edit_graph.dart';
import 'models/layer_stack.dart';
import 'models/layer_transform.dart';
import 'models/overlay_layer.dart';
import 'models/operation_profile.dart';
import 'services/layer_bake.dart';
import 'rust_image_editor_config.dart';
import 'services/beauty_exclude_mask.dart';
import 'services/beauty_look_names.dart';
import 'services/camera_rgba_converter.dart';
import 'services/face_analysis_service.dart';
import 'services/live_camera_service.dart';
import 'services/temporal_face_smoother.dart';
import 'services/filter_descriptor.dart';
import 'services/image_buffer_utils.dart';
import 'services/image_bytes_normalizer.dart';
import 'services/image_export_saver.dart';
import 'services/gpu_texture_registry.dart';
import 'services/rust_worker.dart';
import 'widgets/gpu_texture_preview.dart';
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

  final gpuTextureListenable = ValueNotifier<int>(0);

  /// Swipe mood filter shown during browse (may differ from committed until release).
  MoodFilterPreset? previewMoodPreset;

  /// Committed swipe mood filter from [editGraph].
  MoodFilterPreset? get committedMoodPreset => editGraph.committedMoodPreset;

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

  /// Stable merge instance — do not allocate a new [Listenable.merge] per build
  /// (that churns [ListenableBuilder] subscriptions and can destabilize rebuilds).
  late final Listenable editorChromeListenable = Listenable.merge([
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
    layerListenable.value++;
  }

  void notifyPreviewChanged() {
    previewListenable.value++;
    notifyListeners();
  }

  void _bumpPreviewOnly() {
    previewListenable.value++;
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

  /// Tool panel / export settings (format, quality, backend) — not preview pixels.
  void _bumpChrome() {
    chromeListenable.value++;
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
    _moodDebounceTimer?.cancel();
    _beautyDebounceTimer?.cancel();
    _overlayDebounceTimer?.cancel();
    activePaintStrokeListenable.dispose();
    layerListenable.dispose();
    previewListenable.dispose();
    processingListenable.dispose();
    blockingListenable.dispose();
    statusListenable.dispose();
    chromeListenable.dispose();
    faceChromeListenable.dispose();
    gpuTextureListenable.dispose();
    _disposeGpuSurface();
    _temporalSmoother?.dispose();
    _temporalSmoother = null;
    if (liveCameraActive) {
      unawaited(LiveCameraService.stop());
    }
    RustWorker.shutdown();
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
      if (ImageBytesNormalizer.isHeicOrHeif(bytes)) {
        status = 'Converting HEIC…';
        notifyListeners();
        bytes = await ImageBytesNormalizer.prepareForEditor(bytes);
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
      await LiveCameraService.start(
        onFrame: _onLiveCameraFrame,
        maxWidth: liveCameraMaxEdge,
      );
      liveCameraActive = true;
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

  void _onLiveCameraFrame(CameraImage image) {
    if (!liveCameraActive || _liveFrameBusy) return;
    _liveFrameBusy = true;
    unawaited(_processLiveCameraFrame(image));
  }

  Future<void> _processLiveCameraFrame(CameraImage image) async {
    try {
      final raw = CameraRgbaConverter.toRgba(image);
      if (raw == null || !liveCameraActive) return;
      var base = CameraRgbaConverter.downscaleMaxEdge(raw, liveCameraMaxEdge);
      base = CameraRgbaConverter.mirrorHorizontal(base);

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
          skinMask = await RustWorker.buildSkinMaskFromAnalysis(
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
        if (_gpuBeautyActive()) {
          try {
            await _ensureGpuSurface(base);
            final handle = gpuPreviewHandle;
            if (handle != null) {
              uploadGpuPreviewSurface(id: handle, buffer: base);
              _applyGpuBeautyPipelineSync(
                handle: handle,
                buffer: base,
                skinMask: mask,
                analysis: analysis,
                params: params,
              );
              final displayRb = readbackGpuPreviewSurface(id: handle);
              rgbaBuffer = displayRb;
              previewRgba = null;
              liveBeautyGpuActive = true;
              _beautyPipelineBase = base;
              await GpuTextureRegistry.updateTexture(
                handle: handle.toInt(),
                pixels: displayRb.pixels,
              );
              gpuTextureListenable.value = gpuTextureId ?? 0;
              final look = previewBeautyLook ?? committedBeautyLook;
              final fps = _liveFramesPerSecond > 0 ? ' · ${_liveFramesPerSecond}fps' : '';
              status = look != null
                  ? 'Live · ${beautyLookLabel(look)}$fps'
                  : 'Live · beauty$fps';
              _bumpStatus();
              displayBytes = null;
              _bumpPreviewOnly();
              return;
            }
          } catch (_) {
            liveBeautyGpuActive = false;
          }
        }
        final display = await RustWorker.applyBeauty(
          buffer: base,
          analysis: analysis,
          skinMask: mask,
          params: params,
          excludeMask: _beautyExcludeForBuffer(base),
        );
        liveBeautyGpuActive = false;
        rgbaBuffer = display;
        previewRgba = display;
        _beautyPipelineBase = base;
        final look = previewBeautyLook ?? committedBeautyLook;
        status = look != null
            ? 'Live · ${beautyLookLabel(look)}'
            : 'Live · beauty';
        _bumpStatus();
      } else {
        previewRgba = null;
        rgbaBuffer = null;
        liveBeautyGpuActive = false;
        _beautyPipelineBase = null;
        final pending = params?.hasEffect ?? false;
        if (pending) {
          status = 'Live · detecting face…';
          _bumpStatus();
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
        notifyListeners();
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
          status = p.hasEffect
              ? 'Beauty applied${_gpuBeautyPathSuffix(p)}'
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
    notifyListeners();
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

  bool _gpuBeautyActive() =>
      useGpuTexturePreview &&
      isGpuTexturePreviewAvailable() &&
      gpuTexturePreviewSupported();

  bool _beautyNeedsCpuPipeline(BeautyParams? params) {
    if (params == null || !params.hasEffect) return false;
    // Nexus D: regional beauty runs on GPU when texture preview is active.
    if (_gpuBeautyActive()) return false;
    return true;
  }

  /// Status suffix when beauty runs on GPU WGSL (Nexus D acceptance).
  String _gpuBeautyPathSuffix(BeautyParams p) {
    if (!_gpuBeautyActive() || !p.hasEffect) return '';
    final parts = <String>[];
    if (p.skinSmooth > 0.001) parts.add('gpu_skin');
    if (p.eyeBrighten > 0.001) parts.add('gpu_eye');
    if (p.lipTint != LipTintPreset.none && p.lipTintStrength > 0.001) {
      parts.add('gpu_lip');
    }
    if (p.blush > 0.001) parts.add('gpu_blush');
    if (p.teethWhiten > 0.001) parts.add('gpu_teeth');
    if (p.underEye > 0.001) parts.add('cpu_under_eye');
    if (p.lipPlump > 0.001) parts.add('cpu_plump');
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }

  void _applyGpuBeautyPipelineSync({
    required PlatformInt64 handle,
    required RgbaImageBuffer buffer,
    required SegmentationMask skinMask,
    required FaceAnalysisResult analysis,
    required BeautyParams params,
  }) {
    applyGpuBeautyPipeline(
      id: handle,
      analysis: analysis,
      skinMask: skinMask,
      params: params,
      excludeMask: _beautyExcludeForBuffer(buffer),
    );
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
    final g = gen ?? _opGeneration;
    var base = _beautyPipelineBase;
    if (base == null) {
      await _replayPreview(gen: g);
      return;
    }
    beautyCompareRgba = base;

    if (useGpuTexturePreview &&
        isGpuTexturePreviewAvailable() &&
        gpuTexturePreviewSupported() &&
        !_beautyNeedsCpuPipeline(_activeBeautyParams())) {
      final handle = gpuPreviewHandle;
      if (handle != null) {
        await _yieldToUi();
        if (g != _opGeneration) return;
        try {
          uploadGpuPreviewSurface(id: handle, buffer: base);
          final params = _activeBeautyParams();
          final mask = await _maskForBuffer(base);
          final analysis = faceAnalysis;
          if (params != null &&
              params.hasEffect &&
              mask != null &&
              analysis != null &&
              FaceAnalysisService.isAnalysisValid(analysis)) {
            _applyGpuBeautyPipelineSync(
              handle: handle,
              buffer: base,
              skinMask: mask,
              analysis: analysis,
              params: params,
            );
          }
          final displayRb = readbackGpuPreviewSurface(id: handle);
          if (g != _opGeneration) return;
          rgbaBuffer = displayRb;
          previewRgba = null;
          await GpuTextureRegistry.updateTexture(
            handle: handle.toInt(),
            pixels: displayRb.pixels,
          );
          gpuTextureListenable.value = gpuTextureId ?? 0;
          if (g == _opGeneration && params != null && params.hasEffect) {
            status = 'Beauty${_gpuBeautyPathSuffix(params)}';
            _bumpStatus();
          }
          notifyPreviewChanged();
          return;
        } catch (_) {
          // Fall through to CPU beauty path.
        }
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
    rgbaBuffer = beautified;
    previewRgba = beautified;
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
      notifyListeners();
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
    notifyListeners();
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
    rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
    return rgbaEditBase!;
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
  }) async {
    final g = gen ?? _opGeneration;
    final base = _editBaseUnfiltered();
    if (g != _opGeneration) return;
    final graphOps = excludeCommittedMood
        ? editGraph.withoutMoodFilter().ops
        : editGraph.ops;
    final ops = <EditOp>[...graphOps];
    if (liveFilter != null) {
      ops.add(EditOp.filter(filter: liveFilter.toImageFilter()));
    }
    if (useGpuTexturePreview &&
        isGpuTexturePreviewAvailable() &&
        gpuTexturePreviewSupported() &&
        !_beautyNeedsCpuPipeline(_activeBeautyParams())) {
      try {
        await _ensureGpuSurface(base);
        final handle = gpuPreviewHandle;
        if (handle != null) {
          uploadGpuPreviewSurface(id: handle, buffer: base);
          applyGpuPreviewOps(id: handle, ops: ops, backend: backend);
          final pipelineRb = readbackGpuPreviewSurface(id: handle);
          _beautyPipelineBase = pipelineRb;
          final params = _activeBeautyParams();
          final mask = await _maskForBuffer(pipelineRb);
          final analysis = faceAnalysis;
          if (params != null &&
              params.hasEffect &&
              mask != null &&
              analysis != null &&
              FaceAnalysisService.isAnalysisValid(analysis)) {
            _applyGpuBeautyPipelineSync(
              handle: handle,
              buffer: pipelineRb,
              skinMask: mask,
              analysis: analysis,
              params: params,
            );
          }
          final displayRb = readbackGpuPreviewSurface(id: handle);
          rgbaBuffer = displayRb;
          previewRgba = null;
          await GpuTextureRegistry.updateTexture(
            handle: handle.toInt(),
            pixels: displayRb.pixels,
          );
          gpuTextureListenable.value = gpuTextureId ?? 0;
          notifyPreviewChanged();
          return;
        }
      } catch (e) {
        status = 'GPU texture preview failed — RGBA fallback: $e';
        _bumpStatus();
      }
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
    if (g != _opGeneration) return;
    lastProfile = result.profile;
    _beautyPipelineBase = result.buffer;
    final smoothed = await _applyBeautyAsync(result.buffer);
    if (g != _opGeneration) return;
    rgbaBuffer = smoothed;
    previewRgba = smoothed;
    if (result.preview != null) {
      displayBytes = result.preview;
    }
    notifyPreviewChanged();
  }

  void _disposeGpuSurface() {
    final handle = gpuPreviewHandle;
    if (handle != null) {
      destroyGpuPreviewSurface(id: handle);
      unawaited(GpuTextureRegistry.disposeTexture(handle.toInt()));
      gpuPreviewHandle = null;
      gpuTextureId = null;
      gpuTextureListenable.value = 0;
    }
  }

  Future<void> _ensureGpuSurface(RgbaImageBuffer base) async {
    if (gpuPreviewHandle != null && gpuTextureId != null) return;
    final handle = createGpuPreviewSurface(
      width: base.width,
      height: base.height,
    );
    gpuPreviewHandle = handle;
    final texId = await GpuTextureRegistry.createTexture(
      handle: handle.toInt(),
      width: base.width,
      height: base.height,
    );
    gpuTextureId = texId;
    gpuTextureListenable.value = texId ?? 0;
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
    rgbaBuffer = _cloneRgba(rgbaEditBase!);
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
    final decoded = await RustWorker.decodeRgba(bytes);
    rgbaBase = _cloneRgba(decoded);
    rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
    rgbaBuffer = _cloneRgba(rgbaEditBase!);
    previewRgba = rgbaBuffer;
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
      previewRgba = rgbaBuffer;
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
      final beautyParams = editGraph.committedBeautyParams;
      final analysis = faceAnalysis;
      if (beautyParams != null &&
          beautyParams.hasEffect &&
          analysis != null &&
          FaceAnalysisService.isAnalysisValid(analysis)) {
        final exportMask = FaceAnalysisService.buildSkinMask(
          analysis: analysis,
          width: exportBuf.width,
          height: exportBuf.height,
        );
        exportBuf = applyBeautyCpu(
          buffer: exportBuf,
          landmarks: analysis.landmarks,
          faceContourCount: analysis.faceContourCount,
          regionCounts: regionCountsForAnalysis(analysis),
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
      final decoded = await RustWorker.decodeRgba(bytes);
      rgbaBase = _cloneRgba(decoded);
      rgbaEditBase = ImageBufferUtils.fitMaxEdge(rgbaBase!, liveEditMaxEdge);
      rgbaBuffer = _cloneRgba(rgbaEditBase!);
      previewRgba = rgbaBuffer;
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
}

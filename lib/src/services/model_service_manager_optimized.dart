import 'dart:async';

import 'package:flutter/services.dart';

import 'license_plate_detector.dart';

/// Snapshot of the current loading state for a detector.
class OptimizedLoadingStatus {
  final OptimizedLoadingState state;
  final String? errorMessage;

  /// Progress from 0.0 to 1.0.
  final double progress;

  /// Human-readable status message.
  final String message;

  const OptimizedLoadingStatus({
    required this.state,
    this.errorMessage,
    this.progress = 0.0,
    this.message = '',
  });

  bool get isLoaded => state == OptimizedLoadingState.loaded;
  bool get isLoading => state == OptimizedLoadingState.loading;
  bool get hasError => state == OptimizedLoadingState.error;
}

enum OptimizedLoadingState { notLoaded, loading, loaded, error }

/// Singleton that lazy-loads and caches [LicensePlateDetector] instances.
///
/// Detectors are keyed by the `(detModelPath, ocrModelPath)` pair, so the
/// same model pair is only initialised once regardless of how many callers
/// request it.
///
/// Loading strategy:
/// 1. Reads model asset bytes asynchronously via [rootBundle].
/// 2. Creates TFLite interpreters from pre-loaded buffers (faster than
///    loading from asset path directly).
/// 3. Yields to the event loop between heavy steps so the UI thread can
///    render loading animations smoothly.
///
/// ```dart
/// final detector = await ModelServiceManagerOptimized().getOrLoadDetector(
///   'assets/models/detection.tflite',
///   'assets/models/ocr.tflite',
///   onStatusChange: (s) => setState(() {
///     progress = s.progress;
///     message = s.message;
///   }),
/// );
/// ```
class ModelServiceManagerOptimized {
  static final ModelServiceManagerOptimized _instance =
      ModelServiceManagerOptimized._internal();
  factory ModelServiceManagerOptimized() => _instance;
  ModelServiceManagerOptimized._internal();

  final Map<String, LicensePlateDetector> _cache = {};
  final Map<String, OptimizedLoadingStatus> _status = {};
  final Map<String, StreamController<OptimizedLoadingStatus>> _controllers = {};

  // ── Queries ──────────────────────────────────────────────────────────────

  bool isDetectorCached(String detModelPath, String ocrModelPath) {
    final key = _key(detModelPath, ocrModelPath);
    return _cache.containsKey(key) && (_cache[key]?.isInitialized ?? false);
  }

  LicensePlateDetector? getCachedDetector(
    String detModelPath,
    String ocrModelPath,
  ) {
    if (isDetectorCached(detModelPath, ocrModelPath)) {
      return _cache[_key(detModelPath, ocrModelPath)];
    }
    return null;
  }

  OptimizedLoadingStatus getLoadingStatus(
    String detModelPath,
    String ocrModelPath,
  ) {
    return _status[_key(detModelPath, ocrModelPath)] ??
        const OptimizedLoadingStatus(state: OptimizedLoadingState.notLoaded);
  }

  Stream<OptimizedLoadingStatus> getLoadingStatusStream(
    String detModelPath,
    String ocrModelPath,
  ) {
    final key = _key(detModelPath, ocrModelPath);
    _controllers[key] ??= StreamController<OptimizedLoadingStatus>.broadcast();
    return _controllers[key]!.stream;
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  /// Returns a ready [LicensePlateDetector], loading it if necessary.
  ///
  /// Asset bytes are loaded asynchronously via [rootBundle], then
  /// interpreters are created from those buffers with yield points between
  /// each heavy step so the loading overlay animates smoothly.
  Future<LicensePlateDetector> getOrLoadDetector(
    String detModelPath,
    String ocrModelPath, {
    DelegateType delegateType = DelegateType.gpu,
    void Function(OptimizedLoadingStatus)? onStatusChange,
  }) async {
    final key = _key(detModelPath, ocrModelPath);

    // Return cached detector immediately.
    if (isDetectorCached(detModelPath, ocrModelPath)) {
      return _cache[key]!;
    }

    // If another caller is already loading this pair, wait for it.
    if (_status[key]?.isLoading == true) {
      return _waitForDetector(detModelPath, ocrModelPath);
    }

    _updateStatus(
      key,
      const OptimizedLoadingStatus(
        state: OptimizedLoadingState.loading,
        progress: 0.0,
        message: 'Initializing...',
      ),
      onStatusChange,
    );

    try {
      // ── Step 1: Load asset bytes (async I/O, non-blocking) ───────────
      _updateStatus(
        key,
        const OptimizedLoadingStatus(
          state: OptimizedLoadingState.loading,
          progress: 0.05,
          message: 'Loading detection model data...',
        ),
        onStatusChange,
      );

      final detData = await rootBundle.load(detModelPath);
      final detBytes = detData.buffer.asUint8List();
      await Future<void>.delayed(Duration.zero); // yield

      _updateStatus(
        key,
        const OptimizedLoadingStatus(
          state: OptimizedLoadingState.loading,
          progress: 0.15,
          message: 'Loading OCR model data...',
        ),
        onStatusChange,
      );

      final ocrData = await rootBundle.load(ocrModelPath);
      final ocrBytes = ocrData.buffer.asUint8List();
      await Future<void>.delayed(Duration.zero); // yield

      // ── Step 2: Create interpreters from buffers with yield points ────
      _updateStatus(
        key,
        const OptimizedLoadingStatus(
          state: OptimizedLoadingState.loading,
          progress: 0.25,
          message: 'Preparing models...',
        ),
        onStatusChange,
      );

      final detector = LicensePlateDetector();
      await detector.initializeFromBuffers(
        detModelBytes: detBytes,
        ocrModelBytes: ocrBytes,
        delegateType: delegateType,
        onProgress: (progress, message) {
          _updateStatus(
            key,
            OptimizedLoadingStatus(
              state: OptimizedLoadingState.loading,
              progress: progress,
              message: message,
            ),
            onStatusChange,
          );
        },
      );

      _cache[key] = detector;

      _updateStatus(
        key,
        const OptimizedLoadingStatus(
          state: OptimizedLoadingState.loaded,
          progress: 1.0,
          message: 'Ready',
        ),
        onStatusChange,
      );

      return detector;
    } catch (e) {
      _updateStatus(
        key,
        OptimizedLoadingStatus(
          state: OptimizedLoadingState.error,
          errorMessage: e.toString(),
          message: 'Load failed',
        ),
        onStatusChange,
      );
      rethrow;
    }
  }

  // ── Dispose ──────────────────────────────────────────────────────────────

  void disposeDetector(String detModelPath, String ocrModelPath) {
    final key = _key(detModelPath, ocrModelPath);
    _cache[key]?.dispose();
    _cache.remove(key);
    _status.remove(key);
    _controllers[key]?.close();
    _controllers.remove(key);
  }

  void disposeAll() {
    for (final d in _cache.values) {
      d.dispose();
    }
    _cache.clear();
    _status.clear();
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
  }

  // ── Debug ────────────────────────────────────────────────────────────────

  Map<String, dynamic> getDebugInfo() => {
        'cachedModels': _cache.keys.toList(),
        'loadingStates': _status.map((k, v) => MapEntry(k, v.state.name)),
      };

  // ── Internal ─────────────────────────────────────────────────────────────

  String _key(String detPath, String ocrPath) => '$detPath|$ocrPath';

  Future<LicensePlateDetector> _waitForDetector(
    String detModelPath,
    String ocrModelPath,
  ) async {
    final completer = Completer<LicensePlateDetector>();
    late StreamSubscription<OptimizedLoadingStatus> sub;

    sub = getLoadingStatusStream(detModelPath, ocrModelPath).listen((status) {
      if (status.isLoaded && isDetectorCached(detModelPath, ocrModelPath)) {
        sub.cancel();
        completer.complete(_cache[_key(detModelPath, ocrModelPath)]);
      } else if (status.hasError) {
        sub.cancel();
        completer.completeError(Exception(status.errorMessage));
      }
    });

    return completer.future;
  }

  void _updateStatus(
    String key,
    OptimizedLoadingStatus status,
    void Function(OptimizedLoadingStatus)? callback,
  ) {
    _status[key] = status;
    _controllers[key]?.add(status);
    callback?.call(status);
  }
}

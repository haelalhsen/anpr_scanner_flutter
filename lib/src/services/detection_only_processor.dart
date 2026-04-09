import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../config/realtime_config.dart';
import '../models/captured_frame.dart';
import '../models/detection_box.dart';
import '../utils/camera_image_converter_optimized.dart';
import 'license_plate_detector.dart';

// ══════════════════════════════════════════════════════════════
//  STABILITY TRACKER
// ══════════════════════════════════════════════════════════════

class _StabilityTracker {
  final CaptureQualityConfig cfg;

  int _stableCount = 0;
  DetectionBox? _prevBox;

  img.Image? _bestImage;
  DetectionBox? _bestBox;
  double _bestConf = 0;

  _StabilityTracker(this.cfg);

  int get stableCount => _stableCount;
  int get requiredFrames => cfg.requiredStableFrames;

  /// Feed one processed frame.
  ///
  /// Returns a [CapturedFrame] (the highest-confidence frame from the stable
  /// run) when all quality gates have been satisfied for
  /// [CaptureQualityConfig.requiredStableFrames] consecutive frames.
  /// Returns null on every other frame.
  CapturedFrame? feed({
    required DetectionBox? box,
    required img.Image image,
    required double imgW,
    required double imgH,
  }) {
    // Gate 1 — detection present + minimum confidence
    if (box == null || box.confidence < cfg.minConfidence) {
      _softReset();
      return null;
    }

    // Gate 2 — plate not too small
    if (imgW > 0 && imgH > 0) {
      final plateFrac = (box.width * box.height) / (imgW * imgH);
      if (plateFrac < cfg.minPlateAreaFraction) {
        _softReset();
        return null;
      }
    }

    // Gate 3 — box stable vs previous frame
    if (_prevBox != null && imgW > 0) {
      final dx = (box.centerX - _prevBox!.centerX).abs() / imgW;
      final dy = (box.centerY - _prevBox!.centerY).abs() / imgW;
      if (dx + dy > cfg.maxCentreMoveFraction) {
        _prevBox = box;
        _clearRun();
        return null;
      }

      if (imgH > 0) {
        final imgArea = imgW * imgH;
        final areaDelta =
            (box.width * box.height - _prevBox!.width * _prevBox!.height).abs();
        if (areaDelta / imgArea > cfg.maxAreaChangeFraction) {
          _prevBox = box;
          _clearRun();
          return null;
        }
      }
    }

    // ── All gates passed ─────────────────────────────────────────────────
    _prevBox = box;
    _stableCount++;

    if (box.confidence > _bestConf) {
      _bestConf = box.confidence;
      _bestImage = image;
      _bestBox = box;
    }

    if (_stableCount >= cfg.requiredStableFrames) {
      final frame = CapturedFrame(
        fullImage: _bestImage!,
        plateBox: _bestBox!,
      );
      _hardReset();
      return frame;
    }

    return null;
  }

  void reset() => _hardReset();

  void dispose() {
    _bestImage = null;
    _bestBox = null;
    _prevBox = null;
  }

  void _hardReset() {
    _stableCount = 0;
    _prevBox = null;
    _clearRun();
  }

  void _softReset() {
    _prevBox = null;
    _clearRun();
  }

  void _clearRun() {
    _stableCount = 0;
    _bestImage = null;
    _bestBox = null;
    _bestConf = 0;
  }
}

// ══════════════════════════════════════════════════════════════
//  DETECTION ONLY PROCESSOR
// ══════════════════════════════════════════════════════════════

/// Processes live camera frames through the detection model only (OCR skipped).
///
/// Fires [onReadyToCapture] exactly once per scan cycle, after the plate has
/// been detected with sufficient confidence AND the bounding box has been
/// stable for [CaptureQualityConfig.requiredStableFrames] consecutive frames.
/// The captured [CapturedFrame] holds the highest-confidence frame from the
/// stable run, giving OCR the best possible input.
///
/// Quality gates (all must pass on every frame in the stable run):
///   1. Detection present
///   2. Confidence ≥ minConfidence
///   3. Plate area ≥ minPlateAreaFraction of image
///   4. Box centre drift < maxCentreMoveFraction vs previous frame
///   5. Box area change < maxAreaChangeFraction vs previous frame
///   6. All of the above sustained for N consecutive frames
class DetectionOnlyProcessor {
  final LicensePlateDetector _detector;
  final int sensorOrientation;
  final int downsampleFactor;
  final int minIntervalMs;
  final CaptureQualityConfig qualityConfig;

  bool _isActive = false;
  bool _isProcessing = false;
  bool _isDisposed = false;
  bool _captureTriggered = false;
  int _lastEndTime = 0;

  late _StabilityTracker _tracker;

  // ── Callbacks ─────────────────────────────────────────────────────────────

  /// Fired exactly once per scan cycle when all quality gates pass.
  /// [frame] is safe to pass directly to [LicensePlateDetector.recognizePlate].
  void Function(CapturedFrame frame)? onReadyToCapture;

  /// Fired on every processed frame with the latest detection result and
  /// stability progress. Use to drive the live overlay and progress indicator.
  void Function(
    DetectionBox? box,
    double imgW,
    double imgH,
    int stableCount,
    int requiredCount,
  )? onFrameResult;

  void Function(String error)? onError;

  // ── Constructor ───────────────────────────────────────────────────────────

  DetectionOnlyProcessor({
    required LicensePlateDetector detector,
    this.sensorOrientation = 90,
    this.downsampleFactor = RealtimeConfig.downsampleFactor,
    this.minIntervalMs = RealtimeConfig.minFrameIntervalMs,
    CaptureQualityConfig? qualityConfig,
  })  : _detector = detector,
        qualityConfig = qualityConfig ?? const CaptureQualityConfig() {
    _tracker = _StabilityTracker(this.qualityConfig);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  bool get isActive => _isActive;

  void start() {
    if (_isDisposed) return;
    CameraImageConverterOptimized.warmUp();
    _tracker = _StabilityTracker(qualityConfig);
    _isActive = true;
    _isProcessing = false;
    _captureTriggered = false;
    _lastEndTime = 0;
  }

  void stop() => _isActive = false;

  /// Reset the stability tracker without restarting the camera stream.
  /// Call this after a failed OCR so the processor resumes scanning.
  void resetStability() {
    _tracker.reset();
    _captureTriggered = false;
  }

  /// Feed a raw camera frame. Non-blocking — skipped if the previous frame
  /// is still being processed, the min interval has not elapsed, or capture
  /// has already been triggered.
  void processFrame(CameraImage cameraImage) {
    if (!_isActive || _isProcessing || _isDisposed || _captureTriggered) return;

    if (minIntervalMs > 0 && _lastEndTime > 0) {
      final elapsed =
          (DateTime.now().microsecondsSinceEpoch - _lastEndTime) / 1000;
      if (elapsed < minIntervalMs) return;
    }

    _isProcessing = true;
    _runPipeline(cameraImage);
  }

  void dispose() {
    _isActive = false;
    _isDisposed = true;
    _tracker.dispose();
    onReadyToCapture = null;
    onFrameResult = null;
    onError = null;
  }

  // ── Internal pipeline ─────────────────────────────────────────────────────

  Future<void> _runPipeline(CameraImage raw) async {
    try {
      final img.Image? converted =
          RealtimeConfig.useIsolateConversion
              ? await CameraImageConverterOptimized.convertAsync(
                  raw,
                  sensorOrientation: sensorOrientation,
                  downsampleFactor: downsampleFactor,
                )
              : CameraImageConverterOptimized.convertSync(
                  raw,
                  sensorOrientation: sensorOrientation,
                  downsampleFactor: downsampleFactor,
                );

      if (converted == null || !_isActive || _isDisposed) {
        _finishFrame();
        return;
      }

      final result = await _detector.recognizePlate(converted);
      final box = result?.plateBox;

      final w = converted.width.toDouble();
      final h = converted.height.toDouble();

      final captured = _tracker.feed(
        box: box,
        image: converted,
        imgW: w,
        imgH: h,
      );

      _finishFrame();

      if (_isDisposed) return;

      onFrameResult?.call(box, w, h, _tracker.stableCount, _tracker.requiredFrames);

      if (captured != null && !_captureTriggered) {
        _captureTriggered = true;
        onReadyToCapture?.call(captured);
      }
    } catch (e) {
      _finishFrame();
      onError?.call('DetectionOnlyProcessor: $e');
    }
  }

  void _finishFrame() {
    _isProcessing = false;
    _lastEndTime = DateTime.now().microsecondsSinceEpoch;
  }
}

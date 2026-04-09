import 'package:image/image.dart' as img;

import 'detection_box.dart';

/// A camera frame that has passed all quality gates, ready for OCR.
///
/// [fullImage] is the highest-confidence frame from the stable run.
/// [plateBox] is the detection bounding box on that image.
class CapturedFrame {
  final img.Image fullImage;
  final DetectionBox plateBox;

  double get width => fullImage.width.toDouble();
  double get height => fullImage.height.toDouble();

  const CapturedFrame({
    required this.fullImage,
    required this.plateBox,
  });
}

/// Quality gate thresholds for the real-time stability tracker.
///
/// All gates must pass on every frame in a stable run before
/// [DetectionOnlyProcessor] fires [onReadyToCapture].
class CaptureQualityConfig {
  /// Minimum detection confidence per frame.
  final double minConfidence;

  /// Number of consecutive frames that must pass all gates before capture.
  final int requiredStableFrames;

  /// Max box-centre drift between frames as a fraction of image width.
  final double maxCentreMoveFraction;

  /// Max box-area change between frames as a fraction of total image area.
  final double maxAreaChangeFraction;

  /// Plate must cover at least this fraction of the image area.
  final double minPlateAreaFraction;

  const CaptureQualityConfig({
    this.minConfidence = 0.55,
    this.requiredStableFrames = 3,
    this.maxCentreMoveFraction = 0.08,
    this.maxAreaChangeFraction = 0.06,
    this.minPlateAreaFraction = 0.005,
  });
}

import 'package:image/image.dart' as img;

import 'detection_box.dart';

/// Per-stage timing breakdown for a single recognition run.
class InferenceMetrics {
  final double detectionMs;
  final double croppingMs;
  final double ocrMs;
  final double logicMs;
  final double totalMs;

  const InferenceMetrics({
    required this.detectionMs,
    required this.croppingMs,
    required this.ocrMs,
    required this.logicMs,
    required this.totalMs,
  });

  Map<String, double> toMap() => {
        'detection_inference_ms': detectionMs,
        'cropping_post_proc_ms': croppingMs,
        'ocr_inference_ms': ocrMs,
        'logic_and_split_ms': logicMs,
        'total_e2e_ms': totalMs,
      };

  void printMetrics() {
    // ignore: avoid_print
    print('--- Inference Metrics ---');
    // ignore: avoid_print
    print('Detection: ${detectionMs.toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print('Cropping : ${croppingMs.toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print('OCR      : ${ocrMs.toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print('Logic    : ${logicMs.toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print('Total    : ${totalMs.toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print('--------------------------');
  }
}

/// The final result of a license plate recognition run.
class LicensePlateResult {
  final String code;
  final String number;
  final String fullPlate;
  final DetectionBox? plateBox;
  final InferenceMetrics metrics;

  /// The cropped plate image region — may be null if cropping failed.
  final img.Image? croppedPlate;

  LicensePlateResult({
    required this.code,
    required this.number,
    required this.plateBox,
    required this.metrics,
    this.croppedPlate,
  }) : fullPlate = code.isNotEmpty ? '$code-$number' : number;
}

/// Internal helper for letterbox transform parameters.
class LetterboxResult {
  final img.Image image;
  final double ratio;
  final double padW;
  final double padH;

  const LetterboxResult({
    required this.image,
    required this.ratio,
    required this.padW,
    required this.padH,
  });
}

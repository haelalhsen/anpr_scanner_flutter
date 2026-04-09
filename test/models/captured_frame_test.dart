import 'package:flutter_test/flutter_test.dart';
import 'package:anpr_scanner_flutter/anpr_scanner_flutter.dart';

void main() {
  group('CaptureQualityConfig defaults', () {
    const cfg = CaptureQualityConfig();

    test('minConfidence defaults to 0.55', () {
      expect(cfg.minConfidence, 0.55);
    });

    test('requiredStableFrames defaults to 3', () {
      expect(cfg.requiredStableFrames, 3);
    });

    test('maxCentreMoveFraction defaults to 0.08', () {
      expect(cfg.maxCentreMoveFraction, 0.08);
    });

    test('maxAreaChangeFraction defaults to 0.06', () {
      expect(cfg.maxAreaChangeFraction, 0.06);
    });

    test('minPlateAreaFraction defaults to 0.005', () {
      expect(cfg.minPlateAreaFraction, 0.005);
    });

    test('custom values are respected', () {
      const custom = CaptureQualityConfig(
        minConfidence: 0.7,
        requiredStableFrames: 5,
        maxCentreMoveFraction: 0.05,
        maxAreaChangeFraction: 0.03,
        minPlateAreaFraction: 0.01,
      );
      expect(custom.minConfidence, 0.7);
      expect(custom.requiredStableFrames, 5);
      expect(custom.maxCentreMoveFraction, 0.05);
      expect(custom.maxAreaChangeFraction, 0.03);
      expect(custom.minPlateAreaFraction, 0.01);
    });
  });
}

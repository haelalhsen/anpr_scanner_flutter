import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anpr_scanner_flutter/anpr_scanner_flutter.dart';

void main() {
  group('PreviewCoordinateMapper.mapBoxToDisplay', () {
    // Image 100×100, displayed in a 200×100 widget (wider display).
    // BoxFit.cover: image is scaled to fill width (scale=2), then cropped
    // top/bottom. Scaled size = 200×200, offset = (0, -50).
    test('wider display — image cropped top/bottom', () {
      const box = DetectionBox(
        x1: 0, y1: 0, x2: 100, y2: 100,
        confidence: 1.0, classId: 0,
      );

      final rect = PreviewCoordinateMapper.mapBoxToDisplay(
        box: box,
        processedImageWidth: 100,
        processedImageHeight: 100,
        displaySize: const Size(200, 100),
      );

      // scaledW=200, scaledH=200, offsetX=0, offsetY=(100-200)/2=-50
      expect(rect.left, 0.0);
      expect(rect.top, -50.0);
      expect(rect.right, 200.0);
      expect(rect.bottom, 150.0);
    });

    // Image 100×100 displayed in 100×200 widget (taller display).
    // BoxFit.cover: image scaled to fill height (scale=2), cropped left/right.
    // Scaled size = 200×200, offset = (-50, 0).
    test('taller display — image cropped left/right', () {
      const box = DetectionBox(
        x1: 0, y1: 0, x2: 100, y2: 100,
        confidence: 1.0, classId: 0,
      );

      final rect = PreviewCoordinateMapper.mapBoxToDisplay(
        box: box,
        processedImageWidth: 100,
        processedImageHeight: 100,
        displaySize: const Size(100, 200),
      );

      // scaledW=200, scaledH=200, offsetX=(100-200)/2=-50, offsetY=0
      expect(rect.left, -50.0);
      expect(rect.top, 0.0);
      expect(rect.right, 150.0);
      expect(rect.bottom, 200.0);
    });

    // Square image in exactly matching square display — no offset, 1:1 scale.
    test('exact match — no offset no scale', () {
      const box = DetectionBox(
        x1: 10, y1: 20, x2: 50, y2: 60,
        confidence: 0.9, classId: 0,
      );

      final rect = PreviewCoordinateMapper.mapBoxToDisplay(
        box: box,
        processedImageWidth: 100,
        processedImageHeight: 100,
        displaySize: const Size(100, 100),
      );

      expect(rect.left, 10.0);
      expect(rect.top, 20.0);
      expect(rect.right, 50.0);
      expect(rect.bottom, 60.0);
    });

    test('returns Rect.zero when dimensions are zero', () {
      const box = DetectionBox(
        x1: 0, y1: 0, x2: 10, y2: 10,
        confidence: 0.5, classId: 0,
      );

      final rect = PreviewCoordinateMapper.mapBoxToDisplay(
        box: box,
        processedImageWidth: 0,
        processedImageHeight: 0,
        displaySize: const Size(100, 100),
      );

      expect(rect, Rect.zero);
    });
  });
}

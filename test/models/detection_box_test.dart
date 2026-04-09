import 'package:flutter_test/flutter_test.dart';
import 'package:anpr_scanner_flutter/anpr_scanner_flutter.dart';

void main() {
  group('DetectionBox', () {
    const box = DetectionBox(
      x1: 10, y1: 20, x2: 110, y2: 70,
      confidence: 0.9,
      classId: 0,
    );

    test('centerX is the midpoint of x1 and x2', () {
      expect(box.centerX, 60.0);
    });

    test('centerY is the midpoint of y1 and y2', () {
      expect(box.centerY, 45.0);
    });

    test('width is x2 - x1', () {
      expect(box.width, 100.0);
    });

    test('height is y2 - y1', () {
      expect(box.height, 50.0);
    });

    test('zero-size box', () {
      const zero = DetectionBox(x1: 5, y1: 5, x2: 5, y2: 5, confidence: 0.5, classId: 0);
      expect(zero.width, 0.0);
      expect(zero.height, 0.0);
      expect(zero.centerX, 5.0);
      expect(zero.centerY, 5.0);
    });
  });
}

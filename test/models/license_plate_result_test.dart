import 'package:flutter_test/flutter_test.dart';
import 'package:anpr_scanner_flutter/anpr_scanner_flutter.dart';

void main() {
  final dummyMetrics = InferenceMetrics(
    detectionMs: 10,
    croppingMs: 5,
    ocrMs: 20,
    logicMs: 1,
    totalMs: 36,
  );

  group('LicensePlateResult.fullPlate', () {
    test('combines code and number with dash when code is present', () {
      final result = LicensePlateResult(
        code: 'ABC',
        number: '1234',
        plateBox: null,
        metrics: dummyMetrics,
      );
      expect(result.fullPlate, 'ABC-1234');
    });

    test('returns only number when code is empty', () {
      final result = LicensePlateResult(
        code: '',
        number: '5678',
        plateBox: null,
        metrics: dummyMetrics,
      );
      expect(result.fullPlate, '5678');
    });
  });

  group('InferenceMetrics.toMap', () {
    test('returns all expected keys', () {
      final map = dummyMetrics.toMap();
      expect(map.containsKey('detection_inference_ms'), isTrue);
      expect(map.containsKey('cropping_post_proc_ms'), isTrue);
      expect(map.containsKey('ocr_inference_ms'), isTrue);
      expect(map.containsKey('logic_and_split_ms'), isTrue);
      expect(map.containsKey('total_e2e_ms'), isTrue);
    });

    test('values match constructor fields', () {
      final map = dummyMetrics.toMap();
      expect(map['detection_inference_ms'], 10.0);
      expect(map['ocr_inference_ms'], 20.0);
      expect(map['total_e2e_ms'], 36.0);
    });
  });
}

/// A detected bounding box from the detection model.
class DetectionBox {
  final double x1, y1, x2, y2;
  final double confidence;
  final int classId;

  const DetectionBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
  });

  double get centerX => (x1 + x2) / 2;
  double get centerY => (y1 + y2) / 2;
  double get width => x2 - x1;
  double get height => y2 - y1;
}

/// A single character detection from the OCR model.
class CharDetection {
  final double x;
  final double y;
  final String char;
  final double confidence;

  const CharDetection({
    required this.x,
    required this.y,
    required this.char,
    required this.confidence,
  });
}

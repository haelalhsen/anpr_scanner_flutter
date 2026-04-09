import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io' show Platform;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection_box.dart';
import '../models/license_plate_result.dart';

/// Hardware acceleration delegate for TFLite inference.
enum DelegateType { cpu, gpu, nnapi, auto }

/// Two-stage TFLite license plate recognition engine.
///
/// Stage 1 — Detection model: finds the plate bounding box in a full image.
/// Stage 2 — OCR model: reads characters from the cropped plate region.
///
/// Usage:
/// ```dart
/// final detector = LicensePlateDetector();
/// await detector.initialize(
///   detModelPath: 'assets/models/detection.tflite',
///   ocrModelPath:  'assets/models/ocr.tflite',
/// );
/// final result = await detector.recognizePlate(image);
/// detector.dispose();
/// ```
class LicensePlateDetector {
  Interpreter? _detInterpreter;
  Interpreter? _ocrInterpreter;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  int _detInputWidth = 640;
  int _detInputHeight = 640;
  int _ocrInputWidth = 160;
  int _ocrInputHeight = 160;

  late Float32List _detInputBuffer;
  late Float32List _ocrInputBuffer;
  late List<List<List<double>>> _detOutputBuffer;
  late List<List<List<double>>> _ocrOutputBuffer;

  // ── Inference constants ────────────────────────────────────
  static const double _detConfThreshold = 0.40;
  static const double _ocrConfThreshold = 0.15;
  static const double _iouThreshold = 0.45;
  static const double _gapRatio = 1.8;
  static const double _cropPadding = 0.05;

  static const Map<int, String> _ocrClasses = {
    0: '0', 1: '1', 2: '2', 3: '3', 4: '4',
    5: '5', 6: '6', 7: '7', 8: '8', 9: '9',
    10: 'A', 11: 'B', 12: 'C', 13: 'D', 14: 'E',
    15: 'F', 16: 'G', 17: 'H', 18: 'I', 19: 'J',
    20: 'K', 21: 'L', 22: 'M', 23: 'N', 24: 'O',
    25: 'P', 26: 'Q', 27: 'R', 28: 'S', 29: 'T',
    30: 'U', 31: 'V', 32: 'W', 33: 'X', 34: 'Y',
    35: 'Z',
  };

  // ══════════════════════════════════════════════════════════
  //  PUBLIC API
  // ══════════════════════════════════════════════════════════

  /// Load both TFLite models and prepare inference buffers.
  ///
  /// [detModelPath] and [ocrModelPath] are Flutter asset paths, e.g.
  /// `'assets/models/detection.tflite'`.
  Future<void> initialize({
    required String detModelPath,
    required String ocrModelPath,
    DelegateType delegateType = DelegateType.gpu,
    int numThreads = 4,
  }) async {
    if (_isInitialized) return;

    // Share a single GPU delegate across both interpreters to avoid
    // native driver crashes on devices that can't handle two delegates.
    final gpuDelegate = _createGpuDelegate(delegateType);

    final detOptions = _createInterpreterOptions(
      numThreads: numThreads,
      delegateType: delegateType,
      gpuDelegate: gpuDelegate,
    );
    _detInterpreter = await Interpreter.fromAsset(detModelPath, options: detOptions);

    // OCR model uses CPU — sharing a single GPU delegate between two
    // interpreters running concurrently is unreliable on many drivers.
    final ocrOptions = _createInterpreterOptions(
      numThreads: numThreads,
      delegateType: delegateType,
    );
    _ocrInterpreter = await Interpreter.fromAsset(ocrModelPath, options: ocrOptions);

    _extractInputShapes();
    _preallocateBuffers();

    _isInitialized = true;
  }

  /// Initialize from pre-loaded model bytes (avoids asset I/O on main thread).
  ///
  /// Use this when model bytes have already been loaded off the main isolate.
  /// Yields to the event loop between heavy steps so the UI stays responsive.
  /// Initialize from pre-loaded model bytes (avoids asset I/O on main thread).
  ///
  /// Use this when model bytes have already been loaded off the main isolate.
  /// Yields to the event loop between heavy steps so the UI stays responsive.
  Future<void> initializeFromBuffers({
    required Uint8List detModelBytes,
    required Uint8List ocrModelBytes,
    DelegateType delegateType = DelegateType.gpu,
    int numThreads = 4,
    void Function(double progress, String message)? onProgress,
  }) async {
    if (_isInitialized) return;

    // GPU delegate for the detection model (heavier, benefits most from GPU).
    onProgress?.call(0.3, 'Preparing detection model...');
    final gpuDelegate = _createGpuDelegate(delegateType);
    final detOptions = _createInterpreterOptions(
      numThreads: numThreads,
      delegateType: delegateType,
      gpuDelegate: gpuDelegate,
    );
    await Future<void>.delayed(Duration.zero); // yield to UI

    _detInterpreter = Interpreter.fromBuffer(detModelBytes, options: detOptions);
    onProgress?.call(0.55, 'Detection model ready');
    await Future<void>.delayed(Duration.zero); // yield to UI

    // OCR model uses CPU — two simultaneous GPU delegates crash on many
    // Adreno/Mali drivers. OCR is lightweight so CPU is fast enough.
    onProgress?.call(0.6, 'Preparing OCR model...');
    final ocrOptions = _createInterpreterOptions(
      numThreads: numThreads,
      delegateType: delegateType,
    );
    await Future<void>.delayed(Duration.zero); // yield to UI

    _ocrInterpreter = Interpreter.fromBuffer(ocrModelBytes, options: ocrOptions);
    onProgress?.call(0.85, 'OCR model ready');
    await Future<void>.delayed(Duration.zero); // yield to UI

    _extractInputShapes();
    _preallocateBuffers();

    _isInitialized = true;
    onProgress?.call(1.0, 'Ready');
  }

  /// Run the full detection → crop → OCR pipeline on [image].
  ///
  /// Returns null if no plate is detected.
  Future<LicensePlateResult?> recognizePlate(img.Image image) async {
    if (!_isInitialized) throw StateError('Detector not initialized');

    final overallStart = DateTime.now().microsecondsSinceEpoch;
    final timings = <String, double>{};

    // Stage 1: Detection
    final detStart = DateTime.now().microsecondsSinceEpoch;
    final (detections, _, _, _) = _runDetection(image);
    timings['detection'] =
        (DateTime.now().microsecondsSinceEpoch - detStart) / 1000;

    if (detections.isEmpty) return null;

    // Stage 2: Crop best detection
    final cropStart = DateTime.now().microsecondsSinceEpoch;
    final bestBox = _getBestDetection(detections);
    final croppedPlate = _cropPlate(image, bestBox);
    timings['cropping'] =
        (DateTime.now().microsecondsSinceEpoch - cropStart) / 1000;

    // Stage 3: OCR
    final ocrStart = DateTime.now().microsecondsSinceEpoch;
    final characters = _runOCR(croppedPlate);
    timings['ocr'] =
        (DateTime.now().microsecondsSinceEpoch - ocrStart) / 1000;

    // Stage 4: Character grouping
    final logicStart = DateTime.now().microsecondsSinceEpoch;
    final (code, number) =
        characters.isEmpty ? ('', '') : _processCharacters(characters);
    timings['logic'] =
        (DateTime.now().microsecondsSinceEpoch - logicStart) / 1000;

    final totalMs =
        (DateTime.now().microsecondsSinceEpoch - overallStart) / 1000;

    return LicensePlateResult(
      code: code,
      number: number,
      plateBox: bestBox,
      metrics: InferenceMetrics(
        detectionMs: timings['detection']!,
        croppingMs: timings['cropping']!,
        ocrMs: timings['ocr']!,
        logicMs: timings['logic']!,
        totalMs: totalMs,
      ),
      croppedPlate: croppedPlate,
    );
  }

  void dispose() {
    _detInterpreter?.close();
    _ocrInterpreter?.close();
    _isInitialized = false;
  }

  // ══════════════════════════════════════════════════════════
  //  INTERPRETER OPTIONS
  // ══════════════════════════════════════════════════════════

  /// Create a single GPU delegate that can be shared across interpreters.
  ///
  /// Returns null if GPU is unavailable or not requested.
  GpuDelegateV2? _createGpuDelegate(DelegateType type) {
    if (type == DelegateType.cpu) return null;
    if (type == DelegateType.nnapi && Platform.isAndroid) return null;
    try {
      return GpuDelegateV2(
        options: GpuDelegateOptionsV2(isPrecisionLossAllowed: true),
      );
    } catch (_) {
      return null; // GPU unavailable — will fall back to CPU
    }
  }

  InterpreterOptions _createInterpreterOptions({
    required int numThreads,
    required DelegateType delegateType,
    GpuDelegateV2? gpuDelegate,
  }) {
    final options = InterpreterOptions()..threads = numThreads;

    if (gpuDelegate != null) {
      options.addDelegate(gpuDelegate);
    } else if (delegateType == DelegateType.nnapi && Platform.isAndroid) {
      options.useNnApiForAndroid = true;
    }

    return options;
  }

  // ══════════════════════════════════════════════════════════
  //  BUFFER SETUP
  // ══════════════════════════════════════════════════════════

  void _extractInputShapes() {
    final detShape = _detInterpreter!.getInputTensor(0).shape;
    _detInputHeight = detShape[1];
    _detInputWidth = detShape[2];

    final ocrShape = _ocrInterpreter!.getInputTensor(0).shape;
    _ocrInputHeight = ocrShape[1];
    _ocrInputWidth = ocrShape[2];
  }

  void _preallocateBuffers() {
    _detInputBuffer = Float32List(_detInputWidth * _detInputHeight * 3);
    _ocrInputBuffer = Float32List(_ocrInputWidth * _ocrInputHeight * 3);

    final detOutShape = _detInterpreter!.getOutputTensor(0).shape;
    _detOutputBuffer = List.generate(
      detOutShape[0],
      (_) => List.generate(detOutShape[1], (_) => List.filled(detOutShape[2], 0.0)),
    );

    final ocrOutShape = _ocrInterpreter!.getOutputTensor(0).shape;
    _ocrOutputBuffer = List.generate(
      ocrOutShape[0],
      (_) => List.generate(ocrOutShape[1], (_) => List.filled(ocrOutShape[2], 0.0)),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  DETECTION
  // ══════════════════════════════════════════════════════════

  (List<DetectionBox>, double, double, double) _runDetection(img.Image image) {
    final origW = image.width.toDouble();
    final origH = image.height.toDouble();

    final (ratio, padW, padH) = _letterboxIntoBuffer(
      image,
      _detInputWidth,
      _detInputHeight,
      _detInputBuffer,
    );

    _resetBuffer(_detOutputBuffer);
    _detInterpreter!.run(
      _detInputBuffer.buffer.asUint8List(),
      _detOutputBuffer,
    );

    final detections = _parseDetections(
      _detOutputBuffer,
      ratio, padW, padH,
      origW, origH,
      _detConfThreshold,
      _detInputWidth, _detInputHeight,
    );

    return (detections, ratio, padW, padH);
  }

  List<DetectionBox> _parseDetections(
    List<List<List<double>>> output,
    double ratio,
    double padW,
    double padH,
    double origW,
    double origH,
    double confThreshold,
    int inputW,
    int inputH,
  ) {
    final boxes = <DetectionBox>[];
    final scores = <double>[];
    final rawBoxes = <List<double>>[];

    final data = output[0];
    final numOutputs = data.length;
    final numDetections = data[0].length;
    final isNormalized = data[0][0] <= 2.0;

    for (int i = 0; i < numDetections; i++) {
      double x = data[0][i];
      double y = data[1][i];
      double w = data[2][i];
      double h = data[3][i];

      double maxScore = 0;
      int maxClassId = 0;
      for (int c = 4; c < numOutputs; c++) {
        final score = data[c][i];
        if (score > maxScore) {
          maxScore = score;
          maxClassId = c - 4;
        }
      }

      if (maxScore < confThreshold) continue;

      if (isNormalized) {
        x *= inputW;
        y *= inputH;
        w *= inputW;
        h *= inputH;
      }

      x = (x - padW) / ratio;
      y = (y - padH) / ratio;
      w /= ratio;
      h /= ratio;

      final x1 = (x - w / 2).clamp(0.0, origW);
      final y1 = (y - h / 2).clamp(0.0, origH);
      final x2 = (x + w / 2).clamp(0.0, origW);
      final y2 = (y + h / 2).clamp(0.0, origH);

      rawBoxes.add([x1, y1, x2, y2]);
      scores.add(maxScore);
      boxes.add(DetectionBox(
        x1: x1, y1: y1, x2: x2, y2: y2,
        confidence: maxScore,
        classId: maxClassId,
      ));
    }

    if (boxes.isEmpty) return [];
    final keep = _nms(rawBoxes, scores, _iouThreshold);
    return keep.map((i) => boxes[i]).toList();
  }

  // ══════════════════════════════════════════════════════════
  //  OCR
  // ══════════════════════════════════════════════════════════

  List<CharDetection> _runOCR(img.Image plateImage) {
    final (ratio, padW, padH) = _letterboxIntoBuffer(
      plateImage,
      _ocrInputWidth,
      _ocrInputHeight,
      _ocrInputBuffer,
    );

    _resetBuffer(_ocrOutputBuffer);
    _ocrInterpreter!.run(
      _ocrInputBuffer.buffer.asUint8List(),
      _ocrOutputBuffer,
    );

    return _parseOCR(
      _ocrOutputBuffer,
      ratio, padW, padH,
      _ocrConfThreshold,
      _ocrInputWidth, _ocrInputHeight,
    );
  }

  List<CharDetection> _parseOCR(
    List<List<List<double>>> output,
    double ratio,
    double padW,
    double padH,
    double confThreshold,
    int inputW,
    int inputH,
  ) {
    final chars = <CharDetection>[];
    final boxes = <List<double>>[];
    final scores = <double>[];

    final data = output[0];
    final numOutputs = data.length;
    final numDetections = data[0].length;
    final isNormalized = data[0][0] <= 2.0;

    for (int i = 0; i < numDetections; i++) {
      double x = data[0][i];
      double y = data[1][i];
      double w = data[2][i];
      double h = data[3][i];

      double maxScore = 0;
      int maxClassId = 0;
      for (int c = 4; c < numOutputs; c++) {
        final score = data[c][i];
        if (score > maxScore) {
          maxScore = score;
          maxClassId = c - 4;
        }
      }

      if (maxScore < confThreshold) continue;

      if (isNormalized) {
        x *= inputW;
        y *= inputH;
        w *= inputW;
        h *= inputH;
      }

      x = (x - padW) / ratio;
      y = (y - padH) / ratio;

      boxes.add([x - w / 2, y - h / 2, x + w / 2, y + h / 2]);
      scores.add(maxScore);
      chars.add(CharDetection(
        x: x,
        y: y,
        char: _ocrClasses[maxClassId] ?? '?',
        confidence: maxScore,
      ));
    }

    if (chars.isEmpty) return [];
    final keep = _nms(boxes, scores, _iouThreshold);
    return keep.map((i) => chars[i]).toList();
  }

  // ══════════════════════════════════════════════════════════
  //  CHARACTER GROUPING
  // ══════════════════════════════════════════════════════════

  (String, String) _processCharacters(List<CharDetection> chars) {
    final sorted = List<CharDetection>.from(chars)
      ..sort((a, b) => a.x.compareTo(b.x));
    final hasLetters = sorted.any((c) => c.char.contains(RegExp(r'[A-Z]')));
    return hasLetters
        ? _splitLettersNumbers(sorted.map((c) => c.char).join())
        : _splitByGap(sorted);
  }

  (String, String) _splitLettersNumbers(String text) {
    final letters = text.replaceAll(RegExp(r'[^A-Z]'), '');
    final numbers = text.replaceAll(RegExp(r'[^0-9]'), '');
    return (letters, numbers);
  }

  (String, String) _splitByGap(List<CharDetection> chars) {
    if (chars.length < 2) return ('', chars.map((c) => c.char).join());

    final gaps = <double>[
      for (int i = 0; i < chars.length - 1; i++) chars[i + 1].x - chars[i].x,
    ];

    final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
    final maxGap = gaps.reduce(math.max);
    final maxGapIndex = gaps.indexOf(maxGap);

    if (maxGap < avgGap * _gapRatio) {
      return ('', chars.map((c) => c.char).join());
    }

    final code = chars.sublist(0, maxGapIndex + 1).map((c) => c.char).join();
    final number = chars.sublist(maxGapIndex + 1).map((c) => c.char).join();
    return (code, number);
  }

  // ══════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════

  /// Letterbox [image] into [buffer], returning (ratio, padW, padH).
  /// Uses nearest-neighbour resize and fills padding with grey (114/255).
  (double, double, double) _letterboxIntoBuffer(
    img.Image image,
    int targetW,
    int targetH,
    Float32List buffer,
  ) {
    final ratio = math.min(targetW / image.width, targetH / image.height);
    final newW = (image.width * ratio).round();
    final newH = (image.height * ratio).round();
    final padW = (targetW - newW) / 2;
    final padH = (targetH - newH) / 2;

    const grayNorm = 114.0 / 255.0;
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = grayNorm;
    }

    final resized = img.copyResize(
      image,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.nearest,
    );

    final padWInt = padW.round();
    final padHInt = padH.round();

    for (int y = 0; y < newH; y++) {
      final outY = y + padHInt;
      final rowOffset = outY * targetW;
      for (int x = 0; x < newW; x++) {
        final pixel = resized.getPixel(x, y);
        final idx = (rowOffset + x + padWInt) * 3;
        buffer[idx] = pixel.r / 255.0;
        buffer[idx + 1] = pixel.g / 255.0;
        buffer[idx + 2] = pixel.b / 255.0;
      }
    }

    return (ratio, padW, padH);
  }

  void _resetBuffer(List<List<List<double>>> buffer) {
    for (final batch in buffer) {
      for (final row in batch) {
        for (int i = 0; i < row.length; i++) {
          row[i] = 0.0;
        }
      }
    }
  }

  DetectionBox _getBestDetection(List<DetectionBox> detections) =>
      detections.reduce((a, b) => a.confidence > b.confidence ? a : b);

  img.Image _cropPlate(img.Image image, DetectionBox box) {
    final padW = (box.width * _cropPadding).round();
    final padH = (box.height * _cropPadding).round();

    final x1 = (box.x1 - padW).clamp(0, image.width - 1).round();
    final y1 = (box.y1 - padH).clamp(0, image.height - 1).round();
    final x2 = (box.x2 + padW).clamp(0, image.width).round();
    final y2 = (box.y2 + padH).clamp(0, image.height).round();

    return img.copyCrop(image, x: x1, y: y1, width: x2 - x1, height: y2 - y1);
  }

  List<int> _nms(
    List<List<double>> boxes,
    List<double> scores,
    double iouThresh,
  ) {
    if (boxes.isEmpty) return [];

    final indices = List.generate(boxes.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));

    final keep = <int>[];
    final suppressed = List.filled(boxes.length, false);

    for (final i in indices) {
      if (suppressed[i]) continue;
      keep.add(i);
      for (final j in indices) {
        if (i == j || suppressed[j]) continue;
        if (_iou(boxes[i], boxes[j]) > iouThresh) suppressed[j] = true;
      }
    }

    return keep;
  }

  double _iou(List<double> a, List<double> b) {
    final x1 = math.max(a[0], b[0]);
    final y1 = math.max(a[1], b[1]);
    final x2 = math.min(a[2], b[2]);
    final y2 = math.min(a[3], b[3]);

    final intersection = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
    final areaA = (a[2] - a[0]) * (a[3] - a[1]);
    final areaB = (b[2] - b[0]) * (b[3] - b[1]);
    final union = areaA + areaB - intersection;

    return union > 0 ? intersection / union : 0;
  }
}

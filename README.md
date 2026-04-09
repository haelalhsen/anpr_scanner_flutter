# ANPR Scanner Flutter

A Flutter package for **Automatic Number Plate Recognition (ANPR)** using TFLite models. Runs a two-stage ML pipeline (detection + OCR) entirely on-device for real-time license plate scanning.

> **BYO Models** — the package does not bundle any TFLite models. You provide your own detection and OCR `.tflite` files.

## Features

- Real-time license plate detection and OCR on camera frames
- GPU-accelerated inference via TFLite GPU delegate (falls back to CPU)
- Drop-in `AnprScannerWidget` with built-in camera, permissions, loading UI, and scan flow
- Low-level `LicensePlateDetector` API for custom integrations
- Stability tracking with configurable quality gates for auto-capture
- Optimized YUV-to-RGB conversion with lookup tables and isolate offloading

## Quick Start

### 1. Add the dependency

```yaml
dependencies:
  anpr_scanner_flutter:
    path: ../  # or git/pub reference
```

### 2. Provide model files

Place your TFLite model files in your app's assets:

```
your_app/
  assets/
    models/
      detection.tflite   # YOLOv8-style plate detection model
      ocr.tflite          # Character detection model
```

Register them in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/
```

### 3. Platform setup

**Android** — Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

**iOS** — Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed to scan license plates.</string>
```

### 4. Use the scanner

```dart
import 'package:anpr_scanner_flutter/anpr_scanner_flutter.dart';

// Drop-in widget — handles everything automatically
AnprScannerWidget(
  detModelPath: 'assets/models/detection.tflite',
  ocrModelPath: 'assets/models/ocr.tflite',
  onPlateRecognized: (result) {
    print('Plate: ${result.fullPlate}');
    print('Code: ${result.code}, Number: ${result.number}');
  },
  onError: (error) => print('Error: $error'),
)
```

## Two Abstraction Levels

### High-Level: `AnprScannerWidget`

A self-contained widget that manages the full scan lifecycle:

**loading** -> **scanning** -> **capturing** -> **recognizing** -> **result**

```dart
AnprScannerWidget(
  detModelPath: 'assets/models/detection.tflite',
  ocrModelPath: 'assets/models/ocr.tflite',
  onPlateRecognized: (LicensePlateResult result) {
    Navigator.pop(context, result);
  },
  // Optional customization:
  delegateType: DelegateType.gpu,          // gpu (default), cpu, nnapi, auto
  captureQualityConfig: CaptureQualityConfig(
    minConfidence: 0.70,
    requiredStableFrames: 3,
    maxCentreMoveFraction: 0.08,
  ),
  preloadedDetector: myDetector,           // skip loading if already loaded
)
```

Includes:
- Camera permission handling
- Model loading overlay with progress
- Live bounding box overlay
- Pinch-to-zoom and tap-to-focus
- Torch toggle
- Capture flash animation
- Result card with plate image and metrics

### Low-Level: `LicensePlateDetector`

Direct access to the two-stage inference pipeline. Use this when you want full control over the image source and UI.

```dart
final detector = LicensePlateDetector();
await detector.initialize(
  detModelPath: 'assets/models/detection.tflite',
  ocrModelPath: 'assets/models/ocr.tflite',
  delegateType: DelegateType.gpu,
);

// Run on any img.Image (from camera, gallery, file, etc.)
final result = await detector.recognizePlate(image);

if (result != null) {
  print('Full plate: ${result.fullPlate}');
  print('Code: ${result.code}');
  print('Number: ${result.number}');
  print('Confidence: ${result.plateBox?.confidence}');
  print('Detection time: ${result.metrics.detectionMs}ms');
  print('OCR time: ${result.metrics.ocrMs}ms');
  print('Total time: ${result.metrics.totalMs}ms');
}

detector.dispose();
```

## ML Pipeline

The package runs a two-stage pipeline:

### Stage 1: Detection

- **Input**: 640x640 float32 letterboxed image
- **Model**: YOLOv8-style object detection
- **Output**: Bounding boxes with confidence scores
- **Post-processing**: Non-Maximum Suppression (NMS)

### Stage 2: OCR

- **Input**: 160x160 float32 letterboxed crop of the detected plate
- **Model**: Character-level detection (0-9, A-Z)
- **Output**: Character positions with class IDs and confidences
- **Post-processing**: Left-to-right sorting, then code/number splitting via:
  - Letter/number regex separation (when alphabetic characters are present)
  - Largest-gap heuristic (for all-numeric plates)

### GPU Delegate Strategy

- The **detection model** uses the GPU delegate for maximum performance (it's the heavier model).
- The **OCR model** uses CPU threads. Running two simultaneous GPU delegates crashes the native GPU driver on many Qualcomm Adreno and ARM Mali devices.

## Model Requirements

### Detection Model

| Property     | Value                    |
|-------------|--------------------------|
| Input shape  | `[1, 640, 640, 3]`     |
| Input type   | `float32` (0.0-1.0)    |
| Output       | YOLOv8 transposed format |
| Classes      | 1 (license plate)       |

### OCR Model

| Property     | Value                    |
|-------------|--------------------------|
| Input shape  | `[1, 160, 160, 3]`     |
| Input type   | `float32` (0.0-1.0)    |
| Output       | YOLOv8 transposed format |
| Classes      | 36 (0-9, A-Z)          |

## Key Classes

| Class | Purpose |
|-------|---------|
| `AnprScannerWidget` | Drop-in scanner widget with full UI |
| `LicensePlateDetector` | Core TFLite inference engine |
| `ModelServiceManagerOptimized` | Singleton model cache with async loading |
| `DetectionOnlyProcessor` | Real-time camera frame pipeline with stability tracking |
| `LicensePlateResult` | Recognition result (code, number, metrics, cropped plate) |
| `CaptureQualityConfig` | Stability gate thresholds for auto-capture |
| `RealtimeConfig` | Global tuning for frame pacing, conversion, thresholds |
| `DetectionOverlay` | Animated bounding box overlay widget |
| `ModelLoadingOverlay` | Model loading progress widget |

## Configuration

### `CaptureQualityConfig`

Controls when auto-capture triggers during real-time scanning:

```dart
CaptureQualityConfig(
  minConfidence: 0.55,          // Min detection confidence per frame
  requiredStableFrames: 3,      // Consecutive passing frames before capture
  maxCentreMoveFraction: 0.08,  // Max box centre drift between frames
  maxAreaChangeFraction: 0.06,  // Max box area change between frames
  minPlateAreaFraction: 0.005,  // Min plate area relative to frame
)
```

### `RealtimeConfig`

Static constants for global real-time tuning:

- `downsampleFactor` -- Frame downsampling during conversion (default: 1)
- `useIsolateConversion` -- Offload YUV-to-RGB to background isolate (default: true)
- `minFrameIntervalMs` -- Min time between processed frames (default: 50ms)
- `detectionConfidence` -- Live detection threshold (default: 0.50)
- `staleFrameThreshold` -- Frames before clearing overlay (default: 3)
- `useLookupTables` -- Pre-computed YUV tables (default: true)

## Package Structure

```
lib/
  anpr_scanner_flutter.dart          # Public API barrel file
  src/
    config/
      realtime_config.dart           # Frame pacing, conversion, stability thresholds
    models/
      detection_box.dart             # DetectionBox, CharDetection
      license_plate_result.dart      # LicensePlateResult, InferenceMetrics
      captured_frame.dart            # CapturedFrame, CaptureQualityConfig
    services/
      license_plate_detector.dart    # Core TFLite inference (detection + OCR)
      model_service_manager_optimized.dart  # Singleton async model loader/cache
      detection_only_processor.dart  # Real-time camera frame processor
    utils/
      camera_image_converter_optimized.dart  # YUV420/BGRA -> img.Image
    widgets/
      anpr_scanner_widget.dart       # High-level drop-in scanner widget
      detection_overlay.dart         # Animated bounding box overlay
      scan_result_overlay.dart       # Frozen frame, result card, flash, recognizing overlay
      loading_widgets.dart           # Model loading overlay
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `tflite_flutter` | TFLite model inference |
| `camera` | Camera stream access |
| `image` | Image manipulation (resize, crop, encode) |
| `permission_handler` | Camera permission requests |
| `image_picker` | Gallery image selection (low-level usage) |
| `path_provider` | File system paths |

## License

See [LICENSE](LICENSE) for details.

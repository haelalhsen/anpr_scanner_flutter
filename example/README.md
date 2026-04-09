# ANPR Scanner Example App

Demonstrates both abstraction levels of the `anpr_scanner_flutter` package.

## Prerequisites

### Model Files

Place your TFLite model files in `assets/models/` before running:

```
example/
  assets/
    models/
      detection.tflite   # YOLOv8-style plate detection model (640x640 input)
      ocr.tflite          # Character detection model (160x160 input)
```

The model paths are configured in `lib/main.dart`:

```dart
const String kDetModelPath = 'assets/models/detection.tflite';
const String kOcrModelPath = 'assets/models/ocr.tflite';
```

### Permissions

The app requires camera permission for the high-level example. Permission prompts are handled automatically by the scanner widget.

## Running

```bash
cd example
flutter pub get
flutter run
```

## Examples

### High-Level: AnprScannerWidget

**File**: `lib/high_level_example.dart`

The simplest way to use the package. Drops in `AnprScannerWidget` which handles:
- Camera setup and permissions
- Model loading with progress overlay
- Real-time plate detection with live bounding box
- Stability tracking and auto-capture
- OCR recognition
- Result display with plate image and performance metrics

```dart
AnprScannerWidget(
  detModelPath: detModelPath,
  ocrModelPath: ocrModelPath,
  onPlateRecognized: (result) {
    debugPrint('Plate recognized: ${result.fullPlate}');
  },
  onError: (error) {
    debugPrint('Scanner error: $error');
  },
)
```

The entire example is under 35 lines of code.

### Low-Level: LicensePlateDetector

**File**: `lib/low_level_example.dart`

Shows direct usage of the `LicensePlateDetector` API:
1. Initializes the detector with model paths
2. Picks an image from the device gallery
3. Runs the full detection + OCR pipeline on the static image
4. Displays the result including:
   - Recognized plate text (code + number)
   - Detection confidence
   - Per-stage performance metrics (detection, cropping, OCR, logic, total)

Use this approach when you want to:
- Process static images (from gallery, file, or network)
- Build a completely custom scanning UI
- Integrate plate recognition into an existing camera flow

## Project Structure

```
lib/
  main.dart                  # App entry point, home screen with example cards
  high_level_example.dart    # Drop-in AnprScannerWidget usage
  low_level_example.dart     # Direct LicensePlateDetector usage
assets/
  models/                    # Place .tflite files here (not checked in)
```

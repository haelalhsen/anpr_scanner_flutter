# Development Plan — anpr_scanner_flutter

## Overview

Build the `anpr_scanner_flutter` package in `lib/` based on the reference implementation in `lib-reference/` (read-only). The package exposes license plate detection + OCR at three abstraction levels. Consumer provides their own TFLite models.

---

## Progress Tracker

| Phase | Description                          | Status |
|-------|--------------------------------------|--------|
| 1     | Project Setup & Dependencies         | [x]    |
| 2     | Data Models                          | [x]    |
| 3     | Core ML Service                      | [x]    |
| 4     | Camera Image Conversion Utilities    | [x]    |
| 5     | Model Management & Real-Time Processing | [x] |
| 6     | Widgets                              | [x]    |
| 7     | High-Level Scanner Widget            | [x]    |
| 8     | Public API Barrel File               | [x]    |
| 9     | Tests                                | [x]    |
| 10    | Example App                          | [x]    |

---

## Phase 1: Project Setup & Dependencies

**Goal:** Fix project configuration so the package can actually be used as a dependency.

**Tasks:**
- [ ] Move from `dev_dependencies` to `dependencies`:
  - `image_picker`
  - `image`
  - `camera`
  - `path_provider`
  - `tflite_flutter`
  - `permission_handler`
- [ ] Keep `flutter_test` and `flutter_lints` in `dev_dependencies`
- [ ] Remove placeholder `Calculator` class from `lib/anpr_scanner_flutter.dart`
- [ ] Remove placeholder test from `test/anpr_scanner_flutter_test.dart`

**Reference files:** `pubspec.yaml`

---

## Phase 2: Data Models

**Goal:** Create foundational data classes with no widget/service dependencies.

**Tasks:**
- [ ] `lib/src/models/detection_box.dart`
  - `DetectionBox` — bounding box with `x1, y1, x2, y2`, `confidence`, `classId`, computed `centerX`, `centerY`, `width`, `height`
  - `CharDetection` — character position with `x`, `y`, `char`, `confidence`
- [ ] `lib/src/models/license_plate_result.dart`
  - `InferenceMetrics` — timing for detection, cropping, OCR, logic, total (with `toMap()` and `printMetrics()`)
  - `LicensePlateResult` — `code`, `number`, `fullPlate`, `plateBox`, `metrics`, `croppedPlate`
  - `LetterboxResult` — `image`, `ratio`, `padW`, `padH`
- [ ] `lib/src/models/captured_frame.dart`
  - `CapturedFrame` — `fullImage`, `plateBox`, computed `width`/`height`
  - `CaptureQualityConfig` — `minConfidence`, `requiredStableFrames`, `maxCentreMoveFraction`, `maxAreaChangeFraction`, `minPlateAreaFraction` (all with defaults)

**Reference files:** `lib-reference/services/license_plate_detector_metric_new.dart` (lines 1–109), `lib-reference/services/detection_only_processor.dart` (lines 1–55)

---

## Phase 3: Core ML Service

**Goal:** Port the TFLite inference engine — the heart of the package.

**Tasks:**
- [ ] `lib/src/services/license_plate_detector.dart`
  - `DelegateType` enum: `cpu`, `gpu`, `nnapi`, `auto`
  - `LicensePlateDetector` class:
    - `initialize({detModelPath, ocrModelPath, delegateType, numThreads})`
    - `recognizePlate(img.Image) → Future<LicensePlateResult?>`
    - `dispose()`
  - Internal methods (all from reference):
    - `_createInterpreterOptions()` — GPU on both iOS and Android, fallback to CPU
    - `_extractInputShapes()` / `_preallocateBuffers()` — pre-allocated Float32List buffers
    - `_runDetectionOptimized()` — letterbox into buffer, run interpreter, parse detections
    - `_runOCROptimized()` — letterbox cropped plate, run interpreter, parse characters
    - `_letterboxIntoBuffer()` — zero-allocation letterboxing
    - `_parseDetectionsOptimized()` / `_parseOCROptimized()` — output parsing with NMS
    - `_nms()` / `_calculateIoU()` — non-maximum suppression
    - `_getBestDetection()` / `_cropPlate()` — plate extraction
    - `_processCharacters()` / `_splitLettersNumbers()` / `_splitByGap()` — character grouping
  - Constants: `detConfThreshold=0.40`, `ocrConfThreshold=0.15`, `iouThreshold=0.45`, `gapRatio=1.8`, `cropPadding=0.05`
  - Static `ocrClasses` map (0–9, A–Z)

**Reference files:** `lib-reference/services/license_plate_detector_metric_new.dart` (lines 112–665)

---

## Phase 4: Camera Image Conversion Utilities

**Goal:** Convert platform-specific camera frames to `img.Image` for processing.

**Tasks:**
- [ ] `lib/src/utils/camera_image_converter.dart`
  - `CameraImageConverter` static class
  - `convert(CameraImage, {sensorOrientation, downsampleFactor}) → img.Image?`
  - `_convertYUV420()` — Android YUV_420_888, handles planar + semi-planar, BT.601 YUV→RGB
  - `_convertBGRA8888()` — iOS BGRA8888, single plane
  - Platform-based fallback for unknown format groups
  - Rotation by sensor orientation
- [ ] `lib/src/utils/camera_image_converter_optimized.dart`
  - `_CameraFrameData` DTO — serializable frame data for isolate transfer (copies raw bytes before CameraImage expires)
  - `_YuvLookupTables` — pre-computed Int16List tables for BT.601 coefficients (vToR, uToG, vToG, uToB), lazy-initialized static finals
  - `CameraImageConverterOptimized` static class:
    - `warmUp()` — eagerly init lookup tables
    - `convertAsync()` — extract frame data on main isolate, offload conversion via `compute()`
    - `convertSync()` — same but synchronous
    - `_extractFrameData()` — must run on main isolate while CameraImage is valid
    - `_convertInIsolate()` — top-level function for `compute()`
    - `_convertYUV420Optimized()` — lookup table conversion, no per-pixel floating point
    - `_convertBGRA8888Optimized()` — stride-aware direct access
    - `_enforceMaxDimension()` — safety cap on output dimensions

**Reference files:** `lib-reference/utils/image_conversion.dart`, `lib-reference/utils/image_conversion_optimized.dart`

---

## Phase 5: Model Management & Real-Time Processing

**Goal:** Singleton model caching and real-time camera frame processing with stability tracking.

**Tasks:**
- [ ] `lib/src/config/realtime_config.dart`
  - `RealtimeConfig` — static constants:
    - Frame conversion: `downsampleFactor=1`, `useIsolateConversion=true`
    - Detection thresholds: `detectionConfidence=0.50`, `ocrConfidence=0.20`
    - Frame pacing: `minFrameIntervalMs=100`, `thermalCooldownAfterSeconds=0`
    - Stability: `confirmationFrameCount=3`, `resultRetentionMs=800`, `staleFrameThreshold=3`
    - Resolution: `maxProcessingDimension=720`
    - YUV: `useLookupTables=true`
- [ ] `lib/src/services/model_service_manager.dart`
  - `LoadingState` enum: `notLoaded`, `loading`, `loaded`, `error`
  - `LoadingStatus` class: `state`, `errorMessage`, `progress`, computed `isLoaded`/`isLoading`/`hasError`
  - `ModelServiceManager` singleton:
    - Cache keyed by `(detModelPath, ocrModelPath)` string pair instead of PipelineType
    - `isDetectorCached(detModelPath, ocrModelPath) → bool`
    - `getCachedDetector(detModelPath, ocrModelPath) → LicensePlateDetector?`
    - `getOrLoadDetector(detModelPath, ocrModelPath, {delegateType, onStatusChange}) → Future<LicensePlateDetector>`
    - `getLoadingStatus(detModelPath, ocrModelPath)`
    - `getLoadingStatusStream(detModelPath, ocrModelPath)`
    - `disposeDetector(detModelPath, ocrModelPath)`
    - `disposeAll()`
    - `getDebugInfo()`
    - Internal `_waitForDetector()` with Completer
- [ ] `lib/src/services/detection_only_processor.dart`
  - `_StabilityTracker` (private):
    - `feed({box, image, imgW, imgH}) → CapturedFrame?`
    - Quality gates: detection present → confidence → plate area → centre drift → area change
    - Keeps highest-confidence frame in stable run
    - `reset()` / `dispose()`
  - `DetectionOnlyProcessor`:
    - Constructor: `detector`, `sensorOrientation`, `downsampleFactor`, `minIntervalMs`, `qualityConfig`
    - Callbacks: `onReadyToCapture`, `onFrameResult`, `onError`
    - `start()` / `stop()` / `resetStability()` / `dispose()`
    - `processFrame(CameraImage)` — guards (active, not processing, not disposed, not captured, min interval)
    - `_runPipeline()` — YUV→RGB → detection → stability tracker → callbacks

**Reference files:** `lib-reference/config/realtime_config.dart`, `lib-reference/services/model_service_manager.dart`, `lib-reference/services/detection_only_processor.dart`

---

## Phase 6: Widgets

**Goal:** Reusable UI components consumers can compose into their own screens.

**Tasks:**
- [ ] `lib/src/widgets/detection_overlay.dart`
  - `PreviewCoordinateMapper` — static methods:
    - `mapBoxToDisplay({box, processedImageWidth, processedImageHeight, displaySize}) → Rect` (BoxFit.cover transform)
    - `mapPointToDisplay()` — single point version
  - `DetectionOverlay` StatefulWidget:
    - Props: `detectionBox`, `processedImageWidth/Height`, `plateText`, `confidence`, `staleFrameThreshold`
    - `_TrackedBox` — lerp-interpolated rect + opacity
    - AnimationController at ~60fps, `_lerpSpeed=0.35`
    - Fade-in on first detection, smooth interpolation on updates, fade-out after stale threshold
  - `_DetectionOverlayPainter` — CustomPainter:
    - Box outline (green, rounded)
    - Corner brackets (thick, rounded caps)
    - Semi-transparent fill
    - Confidence badge (top-right)
    - Plate text label (centered below box)
  - `ScanningLineOverlay` — animated horizontal scanning line (cosmetic)
- [ ] `lib/src/widgets/scan_result_overlay.dart`
  - `FrozenFrameView` — displays captured `img.Image` as PNG bytes (encoded via `compute()`), pulsing bounding box overlay, BoxFit.contain coordinate mapping
  - `ScanResultCard` — slide-up card with:
    - Large monospace plate text
    - Code/Number/Confidence chips
    - Cropped plate thumbnail
    - Performance metrics breakdown
    - "Scan Again" / "Done" action buttons
  - `CaptureFlashOverlay` — 300ms white flash on capture
  - `RecognizingOverlay` — semi-transparent overlay with spinner during OCR
- [ ] `lib/src/widgets/loading_widgets.dart`
  - `ShimmerLoading` — animated shimmer shader mask
  - `SkeletonBox` — placeholder rectangle
  - `ModelLoadingOverlay` — full-screen loading with progress bar, pipeline name, status message, tip text
  - `LicensePlateSkeletonScreen` — skeleton layout mimicking actual UI

**Reference files:** `lib-reference/widgets/detection_overlay.dart`, `lib-reference/widgets/scan_result_overlay.dart`, `lib-reference/widgets/loading_widgets.dart`

---

## Phase 7: High-Level Scanner Widget

**Goal:** A self-contained, drop-in scanner widget derived from `ScanLpnScreen`.

**Tasks:**
- [ ] `lib/src/widgets/anpr_scanner_widget.dart`
  - `AnprScannerWidget` StatefulWidget:
    - Required props: `detModelPath`, `ocrModelPath`
    - Optional props: `delegateType`, `captureQualityConfig`, `preloadedDetector`, `onPlateRecognized(LicensePlateResult)`, `onError(String)`
  - Internal state machine — `ScanPhase` enum: `loading`, `scanning`, `capturing`, `recognizing`, `result`, `error`
  - Camera management:
    - Permission request via `permission_handler`
    - Back camera selection, `ResolutionPreset.high`, `ImageFormatGroup.yuv420`
    - Zoom (pinch gesture), torch toggle, tap-to-focus
    - Lifecycle handling (`WidgetsBindingObserver`) — pause/resume camera on app inactive/resumed
  - Model loading:
    - Use `ModelServiceManager.getOrLoadDetector()` with progress callback
    - Accept optional `preloadedDetector` to skip loading
  - Scanning flow:
    - Create `DetectionOnlyProcessor` with quality config
    - Wire `onFrameResult` for live overlay updates
    - Wire `onReadyToCapture` for capture trigger
    - On capture: stop stream, show flash, run OCR via `detector.recognizePlate()`
    - On result: show `ScanResultCard` with "Scan Again" / "Done"
  - UI layers (Stack):
    1. Camera preview (BoxFit.cover)
    2. Frozen frame (capturing/recognizing/result phases)
    3. Live detection overlay (scanning phase)
    4. Guide box with "Align plate here" (scanning phase)
    5. Capture flash
    6. Recognizing overlay
    7. Top bar (back button, title, torch toggle)
    8. Bottom status bar (searching/detected/locking indicators, stability bar)
    9. Result panel
    10. Zoom label

**Reference files:** `lib-reference/screens/scan_lpn_screen.dart`, `lib-reference/main.dart`

---

## Phase 8: Public API Barrel File

**Goal:** Single import for consumers.

**Tasks:**
- [ ] `lib/anpr_scanner_flutter.dart` — export all public types:
  ```dart
  // Models
  export 'src/models/detection_box.dart';
  export 'src/models/license_plate_result.dart';
  export 'src/models/captured_frame.dart';

  // Config
  export 'src/config/realtime_config.dart';

  // Services
  export 'src/services/license_plate_detector.dart';
  export 'src/services/model_service_manager.dart';
  export 'src/services/detection_only_processor.dart';

  // Utils
  export 'src/utils/camera_image_converter.dart';
  export 'src/utils/camera_image_converter_optimized.dart';

  // Widgets
  export 'src/widgets/detection_overlay.dart';
  export 'src/widgets/scan_result_overlay.dart';
  export 'src/widgets/loading_widgets.dart';
  export 'src/widgets/anpr_scanner_widget.dart';
  ```

---

## Phase 9: Tests

**Goal:** Unit tests for core logic that doesn't require device/TFLite runtime.

**Tasks:**
- [ ] `test/models/detection_box_test.dart`
  - `DetectionBox` computed properties (`centerX`, `centerY`, `width`, `height`)
- [ ] `test/services/character_splitting_test.dart`
  - `_splitLettersNumbers()` — mixed alpha+numeric plates
  - `_splitByGap()` — all-numeric plates with gap detection
  - Edge cases: single char, empty, no gap
- [ ] `test/services/stability_tracker_test.dart`
  - Stability counter increments on stable frames
  - Resets on confidence drop, drift, area change
  - Returns `CapturedFrame` after `requiredStableFrames` consecutive passes
  - Keeps highest-confidence frame
- [ ] `test/models/captured_frame_test.dart`
  - `CaptureQualityConfig` default values
- [ ] `test/utils/coordinate_mapper_test.dart`
  - `PreviewCoordinateMapper.mapBoxToDisplay()` — wider display, taller display, exact fit

---

## Phase 10: Example App

**Goal:** Comprehensive example demonstrating all three abstraction levels.

**Tasks:**
- [ ] `example/pubspec.yaml`
  - Depends on `anpr_scanner_flutter` (path: `..`)
  - Depends on `image_picker` for gallery picking
  - Assets section pointing to `assets/models/` (consumer places their `.tflite` files here)
- [ ] Platform configuration:
  - `example/ios/Runner/Info.plist` — `NSCameraUsageDescription`
  - `example/android/app/src/main/AndroidManifest.xml` — `CAMERA` permission
- [ ] `example/lib/main.dart` — home screen with navigation to three examples
- [ ] `example/lib/low_level_example.dart`
  - Pick image from gallery using `image_picker`
  - Create `LicensePlateDetector`, call `initialize()` with model paths
  - Run `recognizePlate()` on the picked image
  - Display: original image, cropped plate, plate text, code/number breakdown, full metrics table
  - Dispose detector on exit
- [ ] `example/lib/mid_level_example.dart`
  - Manual camera setup with `CameraController`
  - Create `LicensePlateDetector` + `DetectionOnlyProcessor`
  - Wire `onFrameResult` → custom `DetectionOverlay`
  - Wire `onReadyToCapture` → run OCR, show result in custom UI
  - Demonstrate: custom quality config, torch toggle, zoom
  - Show how to `resetStability()` and scan again
- [ ] `example/lib/high_level_example.dart`
  - Minimal code: just drop in `AnprScannerWidget`
  - Provide model paths and `onPlateRecognized` callback
  - Navigate back with result
  - Show the result on a simple screen

---

## Implementation Order

```
Phase 1 (setup)
  └→ Phase 2 (models)
       └→ Phase 3 (detector)
            ├→ Phase 4 (image conversion)
            └→ Phase 5 (model manager + processor)  — depends on 3 & 4
                 ├→ Phase 6 (widgets)
                 └→ Phase 7 (scanner widget)         — depends on 5 & 6
                      └→ Phase 8 (barrel file)
                           └→ Phase 10 (example app)

Phase 9 (tests) — runs alongside each phase
```

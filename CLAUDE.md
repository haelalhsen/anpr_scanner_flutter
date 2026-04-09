# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter package for Automatic Number Plate Recognition (ANPR). Uses TFLite models for real-time license plate detection and OCR on mobile devices. Consumer provides their own detection and OCR `.tflite` model files — the package does not bundle models.

## Build & Test Commands

```bash
flutter pub get              # Install dependencies
flutter test                 # Run all tests
flutter test test/<file>     # Run a single test file
flutter analyze              # Run static analysis (uses flutter_lints)
```

Example app:
```bash
cd example && flutter run    # Run the example app
```

## Architecture

### Package Structure

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
      model_service_manager.dart     # Singleton lazy-loader/cache for detectors
      detection_only_processor.dart  # Real-time camera frame processor
    utils/
      camera_image_converter.dart            # Basic YUV420/BGRA → img.Image
      camera_image_converter_optimized.dart  # Lookup-table + isolate version
    widgets/
      detection_overlay.dart         # Animated bounding box overlay
      scan_result_overlay.dart       # FrozenFrameView, ScanResultCard, flash, recognizing overlay
      loading_widgets.dart           # ModelLoadingOverlay, shimmer, skeleton
      anpr_scanner_widget.dart       # High-level drop-in scanner widget
example/
  lib/                               # Comprehensive usage examples
lib-reference/                       # READ-ONLY reference implementation — never modify
test/
```

### Three Abstraction Levels

1. **Low-level** — `LicensePlateDetector`: run detection + OCR on any `img.Image` directly
2. **Mid-level** — `DetectionOnlyProcessor`: process live camera frames with stability tracking, wire your own UI
3. **High-level** — `AnprScannerWidget`: drop-in widget that manages camera, permissions, model loading, and the full scan flow

### Two-Stage ML Pipeline

1. **Detection model** — YOLOv8-style object detection finds license plates. Input: 640x640 float32 letterboxed image. Output: bounding boxes with confidence scores.
2. **OCR model** — Character detection on cropped plate region. Input: 160x160 float32 letterboxed image. Output: character positions with class IDs (0-9, A-Z).

### Core Service Flow

- `LicensePlateDetector` — Runs both TFLite models with pre-allocated buffers. Handles letterboxing, NMS, and character splitting (code vs number segments).
- `ModelServiceManager` — Singleton that lazy-loads and caches detector instances keyed by `(detModelPath, ocrModelPath)`. No PipelineType — consumer provides model paths directly.
- `DetectionOnlyProcessor` — Real-time camera frame processor. Runs detection only on live frames, tracks bounding box stability, fires `onReadyToCapture` once when quality gates pass.
- `AnprScannerWidget` — Self-contained scanner with phase state machine: `loading → scanning → capturing → recognizing → result`.

### Processing Flow (Real-Time)

Camera stream → YUV-to-RGB conversion (optional isolate) → downsample → detection model → stability tracking → auto-capture best frame → OCR model → split code/number → result callback

### Key Design Decisions

- Consumer provides model paths — no bundled models, no PipelineType enum
- State management uses plain `setState` (no Provider/Bloc)
- GPU delegate preferred on both iOS and Android; falls back to CPU
- Character splitting uses two strategies: letter/number regex separation when alphabetic chars present, or largest-gap heuristic for all-numeric plates
- `ModelServiceManager` caches detectors by model path pair to avoid redundant loads

## Reference Code

`lib-reference/` contains the original working implementation. It is **read-only** and must never be modified. Use it as the source of truth when building the package in `lib/src/`.

## Development Plan

See `dev_plan.md` for the phased implementation plan.

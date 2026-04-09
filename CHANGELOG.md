## 1.0.0

* Initial release of the `anpr_scanner_flutter` package.

### Core Features
* **Two-Stage ML Pipeline**: Integrated TFLite support for sequential license plate detection and optical character recognition (OCR).
* **Drop-in Scanner Widget**: Added `AnprScannerWidget`, a fully self-contained UI that manages camera permissions, model loading, real-time scanning, and result presentation.
* **Low-Level API**: Added `LicensePlateDetector` to allow headless, direct processing of `img.Image` objects from any source (camera, gallery, or file system).
* **Smart OCR Parsing**: Built-in post-processing that sorts characters left-to-right and intelligently splits plate codes and numbers using regex and largest-gap heuristics.

### Performance & Optimization
* **Hybrid Hardware Acceleration**: Implemented an automated delegate strategy that routes the heavier detection model to the GPU while keeping OCR on the CPU to prevent native driver crashes.
* **Optimized Image Conversion**: Added `CameraImageConverterOptimized` utilizing pre-computed YUV lookup tables and isolate offloading for fast YUV-to-RGB conversion.
* **Async Model Caching**: Introduced `ModelServiceManagerOptimized` as a singleton to handle asynchronous model loading and memory management.

### Real-time Scanning & Stability Tracking
* **Auto-Capture Gates**: Introduced `CaptureQualityConfig` to ensure high-quality crops by enforcing configurable stability thresholds (minimum confidence, box drift, area change, and consecutive stable frames).
* **Frame Pacing**: Added `RealtimeConfig` to control global tuning constants like frame downsample factors and minimum interval processing times.
* **Frame Processing Pipeline**: Added `DetectionOnlyProcessor` to manage the continuous stream of camera frames efficiently.

### UI & UX Components
* **Interactive Camera View**: Integrated pinch-to-zoom, tap-to-focus, and torch toggle functionalities directly into the scanner widget.
* **Visual Feedback**: Added `DetectionOverlay` for smooth, animated bounding boxes during the scanning phase.
* **State Overlays**: Included `ModelLoadingOverlay` for initialization states and `ScanResultOverlay` (with flash animation) for the final capture transition.
* **Permission Handling**: Automated camera permission requests and state management within the high-level widget.
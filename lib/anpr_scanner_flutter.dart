// Automatic Number Plate Recognition (ANPR) package for Flutter.
//
// Consumer provides their own TFLite detection and OCR model files.
//
// Two levels of abstraction:
//   Low-level  — LicensePlateDetector: run inference on any img.Image
//   High-level — AnprScannerWidget: drop-in scanning widget with camera,
//                permissions, model loading, and full scan flow

// Models
export 'src/models/detection_box.dart';
export 'src/models/license_plate_result.dart';
export 'src/models/captured_frame.dart';

// Config
export 'src/config/realtime_config.dart';

// Services
export 'src/services/license_plate_detector.dart';
export 'src/services/model_service_manager_optimized.dart';
export 'src/services/detection_only_processor.dart';

// Utils
export 'src/utils/camera_image_converter_optimized.dart';

// Widgets
export 'src/widgets/detection_overlay.dart';
export 'src/widgets/scan_result_overlay.dart';
export 'src/widgets/loading_widgets.dart';
export 'src/widgets/anpr_scanner_widget.dart';

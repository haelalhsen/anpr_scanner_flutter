import 'package:anpr_scanner_flutter/anpr_scanner_flutter.dart';
import 'package:flutter/material.dart';

/// High-level example: drop in [AnprScannerWidget] with minimal code.
///
/// The widget handles camera setup, permissions, model loading, and the
/// full scan flow. You only need to supply model paths and a result callback.
class HighLevelExample extends StatelessWidget {
  final String detModelPath;
  final String ocrModelPath;

  const HighLevelExample({
    super.key,
    required this.detModelPath,
    required this.ocrModelPath,
  });

  @override
  Widget build(BuildContext context) {
    return AnprScannerWidget(
      detModelPath: detModelPath,
      ocrModelPath: ocrModelPath,
      onPlateRecognized: (LicensePlateResult result) {
        // The widget stays open by default after recognition so the user
        // can tap "Done" to pop. You can also pop here immediately:
        //   Navigator.pop(context, result);
        debugPrint('Plate recognized: ${result.fullPlate}');
      },
      onError: (String error) {
        debugPrint('Scanner error: $error');
      },
    );
  }
}

import 'package:anpr_scanner_flutter/anpr_scanner_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Low-level example: pick an image from the gallery and run
/// [LicensePlateDetector] directly, then display the full result.
class LowLevelExample extends StatefulWidget {
  final String detModelPath;
  final String ocrModelPath;

  const LowLevelExample({
    super.key,
    required this.detModelPath,
    required this.ocrModelPath,
  });

  @override
  State<LowLevelExample> createState() => _LowLevelExampleState();
}

class _LowLevelExampleState extends State<LowLevelExample> {
  final _detector = LicensePlateDetector();
  final _picker = ImagePicker();

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _statusMessage;
  LicensePlateResult? _result;

  @override
  void initState() {
    super.initState();
    _initDetector();
  }

  Future<void> _initDetector() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading models...';
    });

    try {
      await _detector.initialize(
        detModelPath: widget.detModelPath,
        ocrModelPath: widget.ocrModelPath,
        delegateType: DelegateType.gpu,
      );
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Models loaded. Pick an image to scan.';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Model load failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndRun() async {
    if (!_isInitialized) return;

    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Running recognition...';
      _result = null;
    });

    try {
      final bytes = await xFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        setState(() => _statusMessage = 'Failed to decode image.');
        return;
      }

      final result = await _detector.recognizePlate(image);

      setState(() {
        _result = result;
        _statusMessage = result == null
            ? 'No plate detected.'
            : 'Recognized: ${result.fullPlate}';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Low-Level Example'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status
            if (_statusMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusMessage!,
                    style: TextStyle(color: Colors.blue.shade800)),
              ),

            const SizedBox(height: 16),

            // Pick image button
            ElevatedButton.icon(
              onPressed: _isLoading || !_isInitialized ? null : _pickAndRun,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image),
              label: Text(_isLoading ? 'Processing...' : 'Pick Image & Scan'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),

            const SizedBox(height: 24),

            // Result
            if (_result != null) ...[
              _ResultCard(result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final LicensePlateResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final m = result.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plate text
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  result.fullPlate,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (result.code.isNotEmpty) ...[
                      _chip('Code', result.code),
                      const SizedBox(width: 8),
                    ],
                    _chip('Number', result.number),
                    if (result.plateBox != null) ...[
                      const SizedBox(width: 8),
                      _chip('Conf',
                          '${(result.plateBox!.confidence * 100).toInt()}%'),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Metrics
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Performance',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                _metricRow('Detection', m.detectionMs),
                _metricRow('Cropping', m.croppingMs),
                _metricRow('OCR', m.ocrMs),
                _metricRow('Logic', m.logicMs),
                const Divider(),
                _metricRow('Total E2E', m.totalMs, bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('$label: $value',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
      );

  Widget _metricRow(String label, double ms, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            Text('${ms.toStringAsFixed(1)} ms',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
}

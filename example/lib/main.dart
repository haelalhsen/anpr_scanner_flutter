import 'package:flutter/material.dart';

import 'high_level_example.dart';
import 'low_level_example.dart';

// ── Model paths ──────────────────────────────────────────────────────────────
//
// Place your .tflite files in example/assets/models/ and update these paths.
const String kDetModelPath = 'assets/models/detection.tflite';
const String kOcrModelPath = 'assets/models/ocr.tflite';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ANPR Scanner Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  HOME SCREEN
// ══════════════════════════════════════════════════════════════

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ANPR Scanner Examples'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ExampleCard(
            title: 'High-Level: AnprScannerWidget',
            subtitle:
                'Drop in the ready-made scanning widget. Handles camera, '
                'permissions, model loading, and the full scan flow.',
            icon: Icons.document_scanner,
            color: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const HighLevelExample(
                  detModelPath: kDetModelPath,
                  ocrModelPath: kOcrModelPath,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ExampleCard(
            title: 'Low-Level: LicensePlateDetector',
            subtitle:
                'Pick an image from your gallery and run the detector '
                'directly. Shows the full result and per-stage metrics.',
            icon: Icons.image_search,
            color: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LowLevelExample(
                  detModelPath: kDetModelPath,
                  ocrModelPath: kOcrModelPath,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade700, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Place detection.tflite and ocr.tflite in '
                    'example/assets/models/ before running.',
                    style: TextStyle(
                      color: Colors.amber.shade800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ExampleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

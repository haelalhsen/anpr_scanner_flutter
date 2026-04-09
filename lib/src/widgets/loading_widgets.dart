import 'package:flutter/material.dart';

/// Full-screen loading overlay shown while TFLite models are initialising.
///
/// Displays a pulsing icon, progress bar, and status message to keep the
/// user informed during the model loading phase.
class ModelLoadingOverlay extends StatelessWidget {
  /// Label shown as "Loading {pipelineName}".
  final String pipelineName;

  /// Progress value from 0.0 to 1.0. Shows indeterminate bar when 0.
  final double progress;

  /// Optional message shown below the title (e.g. "Loading OCR model...").
  final String? statusMessage;

  const ModelLoadingOverlay({
    super.key,
    required this.pipelineName,
    this.progress = 0.0,
    this.statusMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pulsing icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                onEnd: () {},
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.memory,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Loading $pipelineName',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                statusMessage ?? 'Initializing AI models...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: 200,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ),
                    if (progress > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 48),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 20, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Models are cached for faster access next time',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

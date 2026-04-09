import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/detection_box.dart';

// ══════════════════════════════════════════════════════════════
//  COORDINATE MAPPING
// ══════════════════════════════════════════════════════════════

/// Maps bounding box coordinates from processed-image space to camera-preview
/// display space, accounting for [BoxFit.cover] cropping.
class PreviewCoordinateMapper {
  PreviewCoordinateMapper._();

  /// Map [box] from processed-image pixel coordinates to widget display coordinates.
  static Rect mapBoxToDisplay({
    required DetectionBox box,
    required double processedImageWidth,
    required double processedImageHeight,
    required Size displaySize,
  }) {
    if (processedImageWidth <= 0 || processedImageHeight <= 0) return Rect.zero;

    final normX1 = box.x1 / processedImageWidth;
    final normY1 = box.y1 / processedImageHeight;
    final normX2 = box.x2 / processedImageWidth;
    final normY2 = box.y2 / processedImageHeight;

    final (scaledW, scaledH, offsetX, offsetY) =
        _coverTransform(processedImageWidth, processedImageHeight, displaySize);

    return Rect.fromLTRB(
      normX1 * scaledW + offsetX,
      normY1 * scaledH + offsetY,
      normX2 * scaledW + offsetX,
      normY2 * scaledH + offsetY,
    );
  }

  /// Map a single point from processed-image space to display space.
  static Offset mapPointToDisplay({
    required double x,
    required double y,
    required double processedImageWidth,
    required double processedImageHeight,
    required Size displaySize,
  }) {
    if (processedImageWidth <= 0 || processedImageHeight <= 0) return Offset.zero;

    final (scaledW, scaledH, offsetX, offsetY) =
        _coverTransform(processedImageWidth, processedImageHeight, displaySize);

    return Offset(
      (x / processedImageWidth) * scaledW + offsetX,
      (y / processedImageHeight) * scaledH + offsetY,
    );
  }

  static (double, double, double, double) _coverTransform(
    double imgW,
    double imgH,
    Size display,
  ) {
    final imageAspect = imgW / imgH;
    final displayAspect = display.width / display.height;

    double scaledW, scaledH, offsetX, offsetY;

    if (displayAspect > imageAspect) {
      scaledW = display.width;
      scaledH = display.width / imageAspect;
      offsetX = 0;
      offsetY = (display.height - scaledH) / 2;
    } else {
      scaledW = display.height * imageAspect;
      scaledH = display.height;
      offsetX = (display.width - scaledW) / 2;
      offsetY = 0;
    }

    return (scaledW, scaledH, offsetX, offsetY);
  }
}

// ══════════════════════════════════════════════════════════════
//  TRACKED BOX
// ══════════════════════════════════════════════════════════════

class _TrackedBox {
  Rect currentRect;
  Rect targetRect;
  double confidence;
  String? plateText;
  double opacity;
  double targetOpacity;

  _TrackedBox({
    required this.currentRect,
    required this.targetRect,
    required this.confidence,
    this.plateText,
    this.opacity = 0.0,
    this.targetOpacity = 1.0,
  });

  void lerp(double t) {
    currentRect = Rect.lerp(currentRect, targetRect, t) ?? targetRect;
    opacity = ui.lerpDouble(opacity, targetOpacity, t) ?? targetOpacity;
  }
}

// ══════════════════════════════════════════════════════════════
//  DETECTION OVERLAY
// ══════════════════════════════════════════════════════════════

/// Animated overlay that draws a bounding box on the camera preview.
///
/// Features:
/// - Coordinate mapping from detection space → display space (BoxFit.cover)
/// - Smooth interpolation between frame results (~60fps animation tick)
/// - Fade-in on first detection, fade-out after [staleFrameThreshold] misses
/// - Corner bracket rendering with confidence badge and optional plate label
class DetectionOverlay extends StatefulWidget {
  final DetectionBox? detectionBox;
  final double processedImageWidth;
  final double processedImageHeight;
  final String? plateText;
  final double confidence;
  final int staleFrameThreshold;

  const DetectionOverlay({
    super.key,
    this.detectionBox,
    required this.processedImageWidth,
    required this.processedImageHeight,
    this.plateText,
    this.confidence = 0.0,
    this.staleFrameThreshold = 3,
  });

  @override
  State<DetectionOverlay> createState() => _DetectionOverlayState();
}

class _DetectionOverlayState extends State<DetectionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  _TrackedBox? _trackedBox;
  int _framesWithoutDetection = 0;

  static const double _lerpSpeed = 0.35;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant DetectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _onNewDetection();
  }

  void _onNewDetection() {
    if (widget.detectionBox != null) {
      _framesWithoutDetection = 0;
      _updateTrackedBox();
      _ensureAnimating();
    } else {
      _framesWithoutDetection++;
      if (_framesWithoutDetection >= widget.staleFrameThreshold) {
        _fadeOut();
      }
    }
  }

  void _updateTrackedBox() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final targetRect = PreviewCoordinateMapper.mapBoxToDisplay(
      box: widget.detectionBox!,
      processedImageWidth: widget.processedImageWidth,
      processedImageHeight: widget.processedImageHeight,
      displaySize: renderBox.size,
    );

    if (_trackedBox == null) {
      _trackedBox = _TrackedBox(
        currentRect: targetRect,
        targetRect: targetRect,
        confidence: widget.confidence,
        plateText: widget.plateText,
        opacity: 0.0,
        targetOpacity: 1.0,
      );
    } else {
      _trackedBox!
        ..targetRect = targetRect
        ..targetOpacity = 1.0
        ..confidence = widget.confidence
        ..plateText = widget.plateText;
    }
  }

  void _fadeOut() {
    _trackedBox?.targetOpacity = 0.0;
    _ensureAnimating();
  }

  void _ensureAnimating() {
    if (!_animController.isAnimating) _animController.repeat();
  }

  void _onTick() {
    if (_trackedBox == null) {
      _animController.stop();
      return;
    }

    _trackedBox!.lerp(_lerpSpeed);

    if (_trackedBox!.opacity < 0.01 && _trackedBox!.targetOpacity == 0.0) {
      _trackedBox = null;
      _animController.stop();
    } else {
      final box = _trackedBox!;
      final rectDiff = (box.currentRect.left - box.targetRect.left).abs() +
          (box.currentRect.top - box.targetRect.top).abs() +
          (box.currentRect.right - box.targetRect.right).abs() +
          (box.currentRect.bottom - box.targetRect.bottom).abs();

      if (rectDiff < 0.5 && (box.opacity - box.targetOpacity).abs() < 0.01) {
        box.currentRect = box.targetRect;
        box.opacity = box.targetOpacity;
        _animController.stop();
      }
    }

    setState(() {});
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DetectionOverlayPainter(trackedBox: _trackedBox),
      size: Size.infinite,
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  OVERLAY PAINTER
// ══════════════════════════════════════════════════════════════

class _DetectionOverlayPainter extends CustomPainter {
  final _TrackedBox? trackedBox;

  static const double _cornerLength = 24.0;
  static const double _cornerThickness = 3.5;
  static const double _boxStrokeWidth = 1.5;
  static const double _cornerRadius = 6.0;
  static const double _labelFontSize = 13.0;
  static const double _labelPadding = 6.0;
  static const double _labelMarginBottom = 8.0;

  const _DetectionOverlayPainter({this.trackedBox});

  @override
  void paint(Canvas canvas, Size size) {
    if (trackedBox == null || trackedBox!.opacity < 0.01) return;

    final box = trackedBox!;
    final rect = box.currentRect;
    final opacity = box.opacity;

    _drawBoxOutline(canvas, rect, opacity);
    _drawCornerBrackets(canvas, rect, opacity);
    _drawBoxFill(canvas, rect, opacity);

    if (box.confidence > 0) {
      _drawConfidenceBadge(canvas, rect, box.confidence, opacity);
    }
    if (box.plateText != null && box.plateText!.isNotEmpty) {
      _drawPlateLabel(canvas, rect, box.plateText!, opacity, size);
    }
  }

  void _drawBoxOutline(Canvas canvas, Rect rect, double opacity) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(_cornerRadius)),
      Paint()
        ..color = Colors.green.withValues(alpha: 0.6 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _boxStrokeWidth,
    );
  }

  void _drawBoxFill(Canvas canvas, Rect rect, double opacity) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(_cornerRadius)),
      Paint()
        ..color = Colors.green.withValues(alpha: 0.08 * opacity)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, double opacity) {
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _cornerThickness
      ..strokeCap = StrokeCap.round;

    final len = math.min(_cornerLength, math.min(rect.width, rect.height) / 3);
    const r = _cornerRadius;

    // Top-left
    canvas.drawLine(Offset(rect.left, rect.top + len), Offset(rect.left, rect.top + r), paint);
    canvas.drawArc(Rect.fromLTWH(rect.left, rect.top, r * 2, r * 2), math.pi, math.pi / 2, false, paint);
    canvas.drawLine(Offset(rect.left + r, rect.top), Offset(rect.left + len, rect.top), paint);

    // Top-right
    canvas.drawLine(Offset(rect.right - len, rect.top), Offset(rect.right - r, rect.top), paint);
    canvas.drawArc(Rect.fromLTWH(rect.right - r * 2, rect.top, r * 2, r * 2), -math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(rect.right, rect.top + r), Offset(rect.right, rect.top + len), paint);

    // Bottom-left
    canvas.drawLine(Offset(rect.left, rect.bottom - len), Offset(rect.left, rect.bottom - r), paint);
    canvas.drawArc(Rect.fromLTWH(rect.left, rect.bottom - r * 2, r * 2, r * 2), math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(rect.left + r, rect.bottom), Offset(rect.left + len, rect.bottom), paint);

    // Bottom-right
    canvas.drawLine(Offset(rect.right - len, rect.bottom), Offset(rect.right - r, rect.bottom), paint);
    canvas.drawArc(Rect.fromLTWH(rect.right - r * 2, rect.bottom - r * 2, r * 2, r * 2), 0, math.pi / 2, false, paint);
    canvas.drawLine(Offset(rect.right, rect.bottom - r), Offset(rect.right, rect.bottom - len), paint);
  }

  void _drawConfidenceBadge(Canvas canvas, Rect rect, double confidence, double opacity) {
    final tp = TextPainter(
      text: TextSpan(
        text: '${(confidence * 100).toInt()}%',
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bw = tp.width + _labelPadding * 2;
    final bh = tp.height + _labelPadding;

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.right - bw, rect.top - bh - 4, bw, bh),
      const Radius.circular(4),
    );

    canvas.drawRRect(
      badgeRect,
      Paint()..color = Colors.green.shade700.withValues(alpha: 0.85 * opacity),
    );
    tp.paint(canvas, Offset(badgeRect.left + _labelPadding, badgeRect.top + _labelPadding / 2));
  }

  void _drawPlateLabel(Canvas canvas, Rect rect, String text, double opacity, Size canvasSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
          fontSize: _labelFontSize,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final lw = tp.width + _labelPadding * 3;
    final lh = tp.height + _labelPadding * 1.5;
    final lx = (rect.center.dx - lw / 2).clamp(4.0, canvasSize.width - lw - 4);
    final ly = (rect.bottom + _labelMarginBottom).clamp(4.0, canvasSize.height - lh - 4);

    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(lx, ly, lw, lh),
      const Radius.circular(6),
    );

    canvas.drawRRect(
      labelRect,
      Paint()..color = Colors.black.withValues(alpha: 0.7 * opacity),
    );
    canvas.drawRRect(
      labelRect,
      Paint()
        ..color = Colors.green.withValues(alpha: 0.5 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    tp.paint(canvas, Offset(lx + _labelPadding * 1.5, ly + _labelPadding * 0.75));
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter old) => true;
}

// ══════════════════════════════════════════════════════════════
//  SCANNING LINE OVERLAY
// ══════════════════════════════════════════════════════════════

/// Animated horizontal scanning line — purely cosmetic, signals active scanning.
class ScanningLineOverlay extends StatefulWidget {
  final bool isActive;
  final Rect? guideRect;

  const ScanningLineOverlay({
    super.key,
    required this.isActive,
    this.guideRect,
  });

  @override
  State<ScanningLineOverlay> createState() => _ScanningLineOverlayState();
}

class _ScanningLineOverlayState extends State<ScanningLineOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isActive) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ScanningLineOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive || widget.guideRect == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => CustomPaint(
        painter: _ScanningLinePainter(
          progress: _animation.value,
          guideRect: widget.guideRect!,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ScanningLinePainter extends CustomPainter {
  final double progress;
  final Rect guideRect;

  const _ScanningLinePainter({required this.progress, required this.guideRect});

  @override
  void paint(Canvas canvas, Size size) {
    final y = guideRect.top + guideRect.height * progress;
    canvas.drawLine(
      Offset(guideRect.left + 8, y),
      Offset(guideRect.right - 8, y),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(guideRect.left, y),
          Offset(guideRect.right, y),
          [
            Colors.transparent,
            Colors.green.withValues(alpha: 0.5),
            Colors.green.withValues(alpha: 0.5),
            Colors.transparent,
          ],
          [0.0, 0.2, 0.8, 1.0],
        )
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanningLinePainter old) =>
      old.progress != progress;
}

import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config/realtime_config.dart';

// ══════════════════════════════════════════════════════════════
//  FRAME DATA DTO
// ══════════════════════════════════════════════════════════════

/// Serializable snapshot of a [CameraImage] frame for isolate transfer.
///
/// [CameraImage] holds native plane pointers that expire after the stream
/// callback. We copy the raw bytes here on the main isolate, then pass
/// this DTO to [compute()].
class _CameraFrameData {
  final int width;
  final int height;
  final int sensorOrientation;
  final int downsampleFactor;
  final bool isYUV;

  // YUV planes
  final Uint8List? yPlane;
  final Uint8List? uPlane;
  final Uint8List? vPlane;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;

  // BGRA plane
  final Uint8List? bgraPlane;
  final int bgraRowStride;

  const _CameraFrameData({
    required this.width,
    required this.height,
    required this.sensorOrientation,
    required this.downsampleFactor,
    required this.isYUV,
    this.yPlane,
    this.uPlane,
    this.vPlane,
    this.yRowStride = 0,
    this.uvRowStride = 0,
    this.uvPixelStride = 1,
    this.bgraPlane,
    this.bgraRowStride = 0,
  });
}

// ══════════════════════════════════════════════════════════════
//  LOOKUP TABLES
// ══════════════════════════════════════════════════════════════

/// Pre-computed BT.601 YUV → RGB coefficient tables.
///
/// Replaces per-pixel floating-point math with a single integer lookup,
/// trading ~256KB of memory for a significant CPU reduction on live frames.
class _YuvLookupTables {
  static final Int16List _vToR = _buildVtoR();
  static final Int16List _uToG = _buildUtoG();
  static final Int16List _vToG = _buildVtoG();
  static final Int16List _uToB = _buildUtoB();

  static bool _initialized = false;

  static Int16List _buildVtoR() {
    final t = Int16List(256);
    for (int i = 0; i < 256; i++) { t[i] = (1.370705 * (i - 128)).round(); }
    return t;
  }

  static Int16List _buildUtoG() {
    final t = Int16List(256);
    for (int i = 0; i < 256; i++) { t[i] = (-0.337633 * (i - 128)).round(); }
    return t;
  }

  static Int16List _buildVtoG() {
    final t = Int16List(256);
    for (int i = 0; i < 256; i++) { t[i] = (-0.698001 * (i - 128)).round(); }
    return t;
  }

  static Int16List _buildUtoB() {
    final t = Int16List(256);
    for (int i = 0; i < 256; i++) { t[i] = (1.732446 * (i - 128)).round(); }
    return t;
  }

  static void ensureInitialized() {
    if (!_initialized) {
      // Access static finals to trigger lazy initialisation
      _vToR;
      _uToG;
      _vToG;
      _uToB;
      _initialized = true;
    }
  }

  static int vToR(int v) => _vToR[v];
  static int uToG(int u) => _uToG[u];
  static int vToG(int v) => _vToG[v];
  static int uToB(int u) => _uToB[u];
}

// ══════════════════════════════════════════════════════════════
//  OPTIMIZED CONVERTER
// ══════════════════════════════════════════════════════════════

/// High-performance [CameraImage] → [img.Image] converter.
///
/// - Pre-computed lookup tables replace per-pixel floating-point math
/// - Optional [compute()] offload keeps the main isolate free during conversion
/// - Safety cap on output dimensions prevents oversized images
class CameraImageConverterOptimized {
  CameraImageConverterOptimized._();

  /// Call once at startup to eagerly initialise the lookup tables.
  static void warmUp() {
    if (RealtimeConfig.useLookupTables) {
      _YuvLookupTables.ensureInitialized();
    }
  }

  /// Convert a camera frame asynchronously.
  ///
  /// Copies raw bytes on the main isolate (must happen before the callback
  /// returns and CameraImage is freed), then offloads conversion to a
  /// background isolate via [compute()] if [RealtimeConfig.useIsolateConversion]
  /// is true.
  static Future<img.Image?> convertAsync(
    CameraImage cameraImage, {
    int sensorOrientation = 90,
    int downsampleFactor = RealtimeConfig.downsampleFactor,
  }) async {
    final frameData = _extractFrameData(
      cameraImage,
      sensorOrientation,
      downsampleFactor,
    );
    if (frameData == null) return null;

    if (RealtimeConfig.useIsolateConversion) {
      return compute(_convertInIsolate, frameData);
    } else {
      return _convertInIsolate(frameData);
    }
  }

  /// Synchronous version — useful when [compute()] overhead isn't worth it
  /// (e.g. very short frames or when already on a background isolate).
  static img.Image? convertSync(
    CameraImage cameraImage, {
    int sensorOrientation = 90,
    int downsampleFactor = RealtimeConfig.downsampleFactor,
  }) {
    final frameData = _extractFrameData(
      cameraImage,
      sensorOrientation,
      downsampleFactor,
    );
    if (frameData == null) return null;
    return _convertInIsolate(frameData);
  }

  // ── Frame extraction (must run on main isolate) ─────────────────────────

  static _CameraFrameData? _extractFrameData(
    CameraImage image,
    int sensorOrientation,
    int downsampleFactor,
  ) {
    try {
      final isYUV = image.format.group == ImageFormatGroup.yuv420 ||
          (image.format.group != ImageFormatGroup.bgra8888 &&
              Platform.isAndroid);

      if (isYUV) {
        if (image.planes.length < 3) return null;
        return _CameraFrameData(
          width: image.width,
          height: image.height,
          sensorOrientation: sensorOrientation,
          downsampleFactor: downsampleFactor,
          isYUV: true,
          yPlane: Uint8List.fromList(image.planes[0].bytes),
          uPlane: Uint8List.fromList(image.planes[1].bytes),
          vPlane: Uint8List.fromList(image.planes[2].bytes),
          yRowStride: image.planes[0].bytesPerRow,
          uvRowStride: image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        );
      } else {
        if (image.planes.isEmpty) return null;
        return _CameraFrameData(
          width: image.width,
          height: image.height,
          sensorOrientation: sensorOrientation,
          downsampleFactor: downsampleFactor,
          isYUV: false,
          bgraPlane: Uint8List.fromList(image.planes[0].bytes),
          bgraRowStride: image.planes[0].bytesPerRow,
        );
      }
    } catch (_) {
      return null;
    }
  }

  // ── Isolate entry point ─────────────────────────────────────────────────

  static img.Image? _convertInIsolate(_CameraFrameData data) {
    try {
      img.Image? result = data.isYUV
          ? _convertYUV420(data)
          : _convertBGRA8888(data);

      if (result == null) return null;

      result = _enforceMaxDimension(result);

      if (data.sensorOrientation != 0) {
        result = img.copyRotate(result, angle: data.sensorOrientation);
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  // ── YUV420 ──────────────────────────────────────────────────────────────

  static img.Image? _convertYUV420(_CameraFrameData data) {
    final yBytes = data.yPlane;
    final uBytes = data.uPlane;
    final vBytes = data.vPlane;
    if (yBytes == null || uBytes == null || vBytes == null) return null;

    final ds = data.downsampleFactor;
    final outW = data.width ~/ ds;
    final outH = data.height ~/ ds;

    _YuvLookupTables.ensureInitialized();

    final result = img.Image(width: outW, height: outH);

    for (int row = 0; row < outH; row++) {
      final srcY = row * ds;
      final yRowOffset = srcY * data.yRowStride;
      final uvRowOffset = (srcY >> 1) * data.uvRowStride;

      for (int col = 0; col < outW; col++) {
        final srcX = col * ds;
        final y = yBytes[yRowOffset + srcX];

        final uvIdx = (srcX >> 1) * data.uvPixelStride;
        final u = uBytes[uvRowOffset + uvIdx];
        final v = vBytes[uvRowOffset + uvIdx];

        final r = (y + _YuvLookupTables.vToR(v)).clamp(0, 255);
        final g = (y + _YuvLookupTables.uToG(u) + _YuvLookupTables.vToG(v))
            .clamp(0, 255);
        final b = (y + _YuvLookupTables.uToB(u)).clamp(0, 255);

        result.setPixelRgb(col, row, r, g, b);
      }
    }

    return result;
  }

  // ── BGRA8888 ─────────────────────────────────────────────────────────────

  static img.Image? _convertBGRA8888(_CameraFrameData data) {
    final bytes = data.bgraPlane;
    if (bytes == null) return null;

    final ds = data.downsampleFactor;
    final outW = data.width ~/ ds;
    final outH = data.height ~/ ds;

    final result = img.Image(width: outW, height: outH);

    for (int row = 0; row < outH; row++) {
      final rowOffset = (row * ds) * data.bgraRowStride;
      for (int col = 0; col < outW; col++) {
        final idx = rowOffset + (col * ds) * 4;
        // BGRA byte order
        result.setPixelRgb(col, row, bytes[idx + 2], bytes[idx + 1], bytes[idx]);
      }
    }

    return result;
  }

  // ── Dimension cap ────────────────────────────────────────────────────────

  static img.Image _enforceMaxDimension(img.Image image) {
    final maxDim = RealtimeConfig.maxProcessingDimension;
    if (image.width <= maxDim && image.height <= maxDim) return image;

    final scale = maxDim /
        (image.width > image.height ? image.width : image.height).toDouble();

    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.nearest,
    );
  }
}

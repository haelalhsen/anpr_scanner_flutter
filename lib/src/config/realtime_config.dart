/// Centralised tuning parameters for real-time license plate processing.
///
/// These control runtime frame processing behaviour, separate from model
/// selection (which the consumer handles by providing model paths).
class RealtimeConfig {
  RealtimeConfig._();

  // ── Frame Conversion ────────────────────────────────────────────────────

  /// Downsample factor during YUV→RGB conversion.
  /// 1 = full resolution. Since the detection model input is 640×640,
  /// feeding a 720p frame at factor 2 (~640×360) loses no accuracy and
  /// halves conversion time.
  static const int downsampleFactor = 1;

  /// Offload YUV→RGB conversion to a background isolate via compute().
  /// Keeps the main isolate free during the ~50–100ms conversion.
  static const bool useIsolateConversion = true;

  // ── Detection Thresholds ────────────────────────────────────────────────

  /// Confidence threshold for live-frame detection.
  /// Slightly higher than static image (0.40) to reduce false positives
  /// on noisy / blurry live frames.
  static const double detectionConfidence = 0.50;

  /// Confidence threshold for live-frame OCR.
  static const double ocrConfidence = 0.20;

  // ── Frame Pacing ────────────────────────────────────────────────────────

  /// Minimum interval between processed frames in milliseconds.
  /// 0 = process as fast as possible.
  /// 100 = max ~10 FPS (or slower if inference exceeds 100ms).
  static const int minFrameIntervalMs = 50;

  /// Stop processing after this many seconds of continuous use to allow
  /// thermal cooldown. 0 = no limit.
  static const int thermalCooldownAfterSeconds = 0;

  // ── Result Stability ────────────────────────────────────────────────────

  /// Number of consecutive frames that must agree before confirming a result.
  static const int confirmationFrameCount = 3;

  /// How long (ms) to keep showing the last detection after it is lost,
  /// to prevent overlay flickering when the plate briefly leaves the frame.
  static const int resultRetentionMs = 800;

  /// Number of stale frames before clearing the live overlay bounding box.
  static const int staleFrameThreshold = 3;

  // ── Resolution Cap ──────────────────────────────────────────────────────

  /// Maximum dimension of a processed frame. Frames larger than this are
  /// downscaled (nearest-neighbour) as a safety cap, in addition to
  /// [downsampleFactor].
  static const int maxProcessingDimension = 720;

  // ── YUV Conversion ──────────────────────────────────────────────────────

  /// Use pre-computed lookup tables for YUV→RGB conversion.
  /// Trades ~256KB of memory for a significant per-pixel CPU reduction.
  static const bool useLookupTables = true;
}

import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Resizes food photos for upload and builds tiny thumbnails for the chat feed.
///
/// Uses the native `flutter_image_compress` codec, which runs off the UI thread
/// (Plan 029 §0.4) — a pure-Dart `package:image` decode of a 12 MP photo would
/// jank the timer animations for 1–3 s.
///
/// Injected into [NutritionPresenter] so unit tests can substitute a fake that
/// skips the platform channel.
class ImageCompressor {
  const ImageCompressor();

  /// Longest-side cap for the uploaded image. Bedrock downsamples anyway, so
  /// 1024px keeps the base64 payload comfortably under ~500 KB.
  static const int uploadMaxDimension = 1024;
  static const int uploadQuality = 80;

  /// Thumbnail cap — persisted next to the chat row, ~5–10 KB on disk.
  static const int thumbnailMaxDimension = 96;
  static const int thumbnailQuality = 70;

  /// Resize + re-encode [bytes] to a JPEG suitable for the vision endpoint.
  Future<Uint8List> compressForUpload(Uint8List bytes) =>
      FlutterImageCompress.compressWithList(
        bytes,
        minWidth: uploadMaxDimension,
        minHeight: uploadMaxDimension,
        quality: uploadQuality,
        format: CompressFormat.jpeg,
      );

  /// Build a small JPEG thumbnail for the chat feed indicator.
  Future<Uint8List> makeThumbnail(Uint8List bytes) =>
      FlutterImageCompress.compressWithList(
        bytes,
        minWidth: thumbnailMaxDimension,
        minHeight: thumbnailMaxDimension,
        quality: thumbnailQuality,
        format: CompressFormat.jpeg,
      );
}

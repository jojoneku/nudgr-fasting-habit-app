import 'dart:typed_data';

/// No-op on platforms with no clipboard image path. See
/// `clipboard_image_paste.dart`.
class ClipboardImagePaste {
  ClipboardImagePaste({required this.isActive, required this.onImages});

  /// Whether a paste right now belongs to this listener's input.
  final bool Function() isActive;

  /// Receives every image in one paste, in clipboard order.
  final void Function(List<Uint8List> images) onImages;

  void start() {}

  void dispose() {}
}

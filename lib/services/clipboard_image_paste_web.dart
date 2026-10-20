import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Web: reads image files out of the DOM `paste` event.
///
/// Listens on the document, not on an element. Flutter web edits text in a
/// DOM textarea of its own, which it creates and replaces as fields gain focus,
/// so there is no stable element to attach to; the event bubbles to the
/// document from whichever one is focused. [isActive] is what scopes it to the
/// Nudgy input.
///
/// The event is left to run as normal. A paste of text alone carries no image
/// and is ignored here; a paste of an image alone puts nothing in the field;
/// and a paste of both (an image copied from a web page) keeps its text.
class ClipboardImagePaste {
  ClipboardImagePaste({required this.isActive, required this.onImages});

  /// Whether a paste right now belongs to this listener's input.
  final bool Function() isActive;

  /// Receives every image in one paste, in clipboard order.
  final void Function(List<Uint8List> images) onImages;

  JSFunction? _listener;

  void start() {
    if (_listener != null) return;
    final listener = _onPaste.toJS;
    _listener = listener;
    web.document.addEventListener('paste', listener);
  }

  void dispose() {
    final listener = _listener;
    if (listener == null) return;
    web.document.removeEventListener('paste', listener);
    _listener = null;
  }

  void _onPaste(web.ClipboardEvent event) {
    if (!isActive()) return;
    final items = event.clipboardData?.items;
    if (items == null) return;
    final files = <web.File>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind != 'file' || !item.type.startsWith('image/')) continue;
      final file = item.getAsFile();
      if (file != null) files.add(file);
    }
    if (files.isEmpty) return;
    _read(files);
  }

  /// Reads after the event returns: the files stay readable once the event is
  /// over, and the read is async anyway.
  Future<void> _read(List<web.File> files) async {
    try {
      final images = <Uint8List>[
        for (final file in files)
          (await file.arrayBuffer().toDart).toDart.asUint8List(),
      ];
      if (_listener != null) onImages(images);
    } catch (e) {
      debugPrint('ClipboardImagePaste: could not read pasted image: $e');
    }
  }
}

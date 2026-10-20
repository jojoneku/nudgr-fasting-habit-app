/// Images pasted with Ctrl/Cmd+V, for the Nudgy input.
///
/// Flutter's [Clipboard] reads text only, so an image on the clipboard needs a
/// platform path of its own. The browser hands a pasted image to the page in
/// the DOM `paste` event, which is what the web build listens to; every other
/// platform gets a no-op. On Android, images from the keyboard's clipboard
/// arrive through the text field's content insertion instead (see
/// `ContentInsertionConfiguration` in the chat input bar), so nothing here is
/// needed for it.
library;

export 'clipboard_image_paste_stub.dart'
    if (dart.library.js_interop) 'clipboard_image_paste_web.dart';

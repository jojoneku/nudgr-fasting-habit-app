import 'package:flutter/material.dart';

/// Lightweight, theme-aware Markdown renderer for AI chat bubbles.
///
/// The coach models emit light Markdown — bold, bullets, the occasional
/// heading or horizontal rule. Rendering it as a raw `Text` widget leaked the
/// syntax (`##`, `**`, `---`) into the bubble. A full Markdown package is
/// overkill (and heavy) for a chat line, so this handles just the subset the
/// models produce, styled entirely from [Theme] so it works in both light and
/// dark mode.
///
/// Supported block elements (line-based):
///   - ATX headings `#`..`######`      → bold label, one size step down per level
///   - horizontal rules `---`/`***`     → a hairline divider
///   - blockquotes `> …`                → left-accented note (used for `> Correction:`)
///   - unordered bullets `- ` / `* `    → `•` with hanging indent
///   - ordered items `1. `              → number with hanging indent
///   - blank lines                      → paragraph spacing
/// Supported inline spans: `**bold**`, `__bold__`, `*italic*`, `_italic_`,
/// and `` `code` `` (nested emphasis inside bold is parsed too).
class ChatMarkdown extends StatelessWidget {
  final String text;

  /// Base color for body text — defaults to `colorScheme.onSurface`.
  final Color? color;
  final double fontSize;
  final double height;

  const ChatMarkdown(
    this.text, {
    super.key,
    this.color,
    this.fontSize = 14,
    this.height = 1.45,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = TextStyle(
      color: color ?? cs.onSurface,
      fontSize: fontSize,
      height: height,
    );

    final blocks = <Widget>[];
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var pendingGap = false; // collapse runs of blank lines into one gap

    void addGap() {
      if (blocks.isNotEmpty) blocks.add(const SizedBox(height: 8));
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        pendingGap = true;
        continue;
      }
      if (pendingGap) {
        addGap();
        pendingGap = false;
      }

      // Horizontal rule: --- / *** / ___ (3+).
      if (RegExp(r'^([-*_])\1{2,}$').hasMatch(trimmed)) {
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(height: 1, color: cs.outlineVariant),
        ));
        continue;
      }

      // Heading: #.. → bold, sized down by level (capped so it stays chat-sized).
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final content = heading.group(2)!.replaceAll(RegExp(r'\s*#+\s*$'), '');
        final size = (fontSize + 3 - level).clamp(fontSize, fontSize + 2);
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Text.rich(
            _inline(
                content,
                base.copyWith(
                  fontSize: size.toDouble(),
                  fontWeight: FontWeight.w700,
                )),
          ),
        ));
        continue;
      }

      // Blockquote: > … (e.g. the models' "> Correction:" self-fix line).
      final quote = RegExp(r'^>\s?(.*)$').firstMatch(trimmed);
      if (quote != null) {
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: cs.primary.withValues(alpha: 0.5), width: 3),
            ),
          ),
          child: Text.rich(
            _inline(
                quote.group(1)!,
                base.copyWith(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                )),
          ),
        ));
        continue;
      }

      // Unordered bullet: - / * / + .
      final bullet = RegExp(r'^([-*+])\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        blocks.add(_marker('•  ', bullet.group(2)!, base, cs));
        continue;
      }

      // Ordered item: 1. / 2) .
      final ordered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      if (ordered != null) {
        blocks.add(
            _marker('${ordered.group(1)}.  ', ordered.group(2)!, base, cs));
        continue;
      }

      // Plain paragraph line.
      blocks.add(Text.rich(_inline(trimmed, base)));
    }

    if (blocks.isEmpty) return Text(text, style: base);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  /// A list row: fixed marker + hanging-indented inline content.
  Widget _marker(
      String marker, String content, TextStyle base, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(marker, style: base.copyWith(color: cs.onSurfaceVariant)),
          Expanded(child: Text.rich(_inline(content, base))),
        ],
      ),
    );
  }

  /// Parse inline emphasis into a [TextSpan] tree. Handles `**bold**`, `__bold__`,
  /// `*italic*`, `_italic_` and `` `code` ``; bold content is re-parsed so
  /// `**a *b* c**` keeps its inner italic.
  static TextSpan _inline(String text, TextStyle style) {
    final pattern = RegExp(
      r'(\*\*|__)(.+?)\1' // bold
      r'|(?<!\w)([*_])(.+?)\3(?!\w)' // italic (avoid mid-word underscores)
      r'|`([^`]+)`', // inline code
    );

    final spans = <InlineSpan>[];
    var index = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start), style: style));
      }
      if (m.group(1) != null) {
        final bold = style.copyWith(fontWeight: FontWeight.w700);
        spans.add(_inline(m.group(2)!, bold));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(4),
          style: style.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(5) != null) {
        spans.add(TextSpan(
          text: m.group(5),
          style: style.copyWith(fontFamily: 'monospace'),
        ));
      }
      index = m.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: style));
    }
    return TextSpan(style: style, children: spans);
  }
}

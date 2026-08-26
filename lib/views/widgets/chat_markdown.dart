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
///   - GFM pipe tables                  → a real bordered table, scrolled
///                                        horizontally when it will not fit
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

    // Indexed rather than a for-in: a table is several lines and has to be able
    // to consume them together.
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        pendingGap = true;
        continue;
      }
      if (pendingGap) {
        addGap();
        pendingGap = false;
      }

      // Table: a header row of pipes followed by a |---|:--:| delimiter row.
      // Checked before every other block, because a row's cells can start with
      // characters the line-based branches below would claim first.
      final consumed = _tableRowSpan(lines, i);
      if (consumed > 1) {
        blocks.add(_table(
          lines.sublist(i, i + consumed),
          base,
          cs,
        ));
        i += consumed - 1;
        continue;
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

  /// How many lines from [start] form a GFM pipe table, or 0 if none does.
  ///
  /// Requires the delimiter row, not just pipes: a sentence like "cash | credit"
  /// is prose, and a one-line "table" is a sentence with a pipe in it. Rows stop
  /// at the first line without a pipe, so a table needs no blank line after it.
  static int _tableRowSpan(List<String> lines, int start) {
    if (start + 1 >= lines.length) return 0;
    if (!lines[start].contains('|')) return 0;
    final delimiter = lines[start + 1].trim();
    if (!RegExp(r'^\|?[\s:|-]+\|?$').hasMatch(delimiter) ||
        !delimiter.contains('-') ||
        !delimiter.contains('|')) {
      return 0;
    }
    var end = start + 2;
    while (end < lines.length && lines[end].contains('|')) {
      end++;
    }
    return end - start;
  }

  /// Splits one table row into cells, dropping the leading and trailing pipes
  /// models usually write but Markdown does not require.
  static List<String> _cells(String row) {
    var t = row.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  /// Alignment per column, read off the delimiter row (`---:` right, `:-:`
  /// centre). Numbers in a money table read far better right-aligned, and the
  /// model is the only thing that knows which columns hold them.
  static List<TextAlign> _alignments(String delimiter, int columns) {
    final specs = _cells(delimiter);
    return [
      for (var i = 0; i < columns; i++)
        if (i >= specs.length)
          TextAlign.left
        else if (specs[i].endsWith(':') && specs[i].startsWith(':'))
          TextAlign.center
        else if (specs[i].endsWith(':'))
          TextAlign.right
        else
          TextAlign.left,
    ];
  }

  Widget _table(List<String> rows, TextStyle base, ColorScheme cs) {
    final header = _cells(rows.first);
    final body = [for (final r in rows.skip(2)) _cells(r)];
    // Ragged rows are common in generated tables. Pad rather than drop, so a
    // missing trailing cell costs an empty box instead of the whole row.
    final columns = [
      header.length,
      for (final r in body) r.length,
    ].reduce((a, b) => a > b ? a : b);
    final align = _alignments(rows[1], columns);

    List<Widget> cellsFor(List<String> cells, {required bool isHeader}) => [
          for (var i = 0; i < columns; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text.rich(
                _inline(
                  i < cells.length ? cells[i] : '',
                  isHeader
                      ? base.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          fontSize: base.fontSize! - 1,
                        )
                      : base,
                ),
                textAlign: align[i],
              ),
            ),
        ];

    final table = Table(
      // Sized to content, not stretched: a two-column money table stretched to
      // the bubble width leaves a gulf between label and figure.
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder(
        horizontalInside: BorderSide(color: cs.outlineVariant, width: 0.5),
        top: BorderSide(color: cs.outlineVariant, width: 0.5),
        bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(color: cs.surfaceContainerHighest),
          children: cellsFor(header, isHeader: true),
        ),
        for (final r in body) TableRow(children: cellsFor(r, isHeader: false)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // A chat bubble is narrow and a table has a minimum width it cannot go
      // below, so let it scroll sideways rather than overflow the bubble.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table,
      ),
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

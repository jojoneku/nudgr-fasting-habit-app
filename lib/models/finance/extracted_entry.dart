import 'finance_parse_result.dart';

/// A field of a transaction that the confirm card can resolve inline.
///
/// Only structured fields appear here: each one maps to a picker (dropdown,
/// category sheet, date chip, type toggle, amount field), so a gap is filled
/// with a tap instead of a clarifying question and another AI round trip.
/// Free-text fields (description, note, owedBy) are never "missing" — a blank
/// one is simply blank.
enum EntryField {
  amount,
  type,
  account,
  transferTo,
  category;

  /// Short label for the inline chip on the confirm card.
  String get label => switch (this) {
        EntryField.amount => 'Amount',
        EntryField.type => 'Type',
        EntryField.account => 'Account',
        EntryField.transferTo => 'To',
        EntryField.category => 'Category',
      };
}

/// One transaction the AI extracted from a message, plus what it could not
/// pin down.
///
/// The draft always survives binding. When the model names an account or
/// category that isn't in the user's real lists, that *one field* is dropped
/// and recorded in [missing] — the row is never discarded and never carries a
/// fabricated id. That is the whole difference from the old classifier, which
/// answered an unrecognised name with `StepGiveUp` and sent the entire message
/// to a blank form.
class ExtractedEntry {
  final ParsedTransaction txn;

  /// Structured fields still to be filled before this row can commit.
  final Set<EntryField> missing;

  /// The model's own confidence in this row, 0–1. Drives the "check this one"
  /// affordance; it never silently drops a row.
  final double confidence;

  const ExtractedEntry({
    required this.txn,
    this.missing = const {},
    this.confidence = 1,
  });

  /// Ready to commit: nothing structured outstanding, and the draft agrees.
  ///
  /// Both halves are checked because they answer different questions —
  /// [missing] is what the *model* admitted it couldn't determine, while
  /// [ParsedTransaction.isComplete] is what the *commit path* requires. A row
  /// the model was quietly wrong about must not slip through on an empty
  /// `missing` set.
  bool get isReady => missing.isEmpty && txn.isComplete;

  /// Below this the row is shown with a "check this" hint. It is deliberately
  /// the same floor the old classifier used, so the bar for trusting a model
  /// answer hasn't moved just because the pipeline around it did.
  static const double confidenceFloor = 0.6;

  bool get isLowConfidence => confidence < confidenceFloor;

  ExtractedEntry copyWith({
    ParsedTransaction? txn,
    Set<EntryField>? missing,
    double? confidence,
  }) =>
      ExtractedEntry(
        txn: txn ?? this.txn,
        missing: missing ?? this.missing,
        confidence: confidence ?? this.confidence,
      );

  /// Applies an inline edit: swaps the draft in and clears [field] from
  /// [missing], since the user has just answered it themselves.
  ExtractedEntry resolve(EntryField field, ParsedTransaction updated) =>
      copyWith(
        txn: updated,
        missing: {...missing}..remove(field),
      );
}

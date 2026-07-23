/// Outcome of scanning a receipt photo into a single expense
/// ([AiCoachService.parseReceiptFromImage]).
///
/// Mirrors the food-photo path's `PhotoParseResult`: a status the caller
/// switches over, plus the extracted fields when [status] is [ok]. The client
/// logs ONE transaction for the grand [total] (per product decision); the
/// merchant becomes the description and [categoryHint] is handed to the finance
/// classifier to resolve against the user's own category list.
enum ReceiptParseStatus {
  /// A receipt was read — [ReceiptParseResult.total] is set and > 0.
  ok,

  /// The photo isn't a receipt / no total could be read. Nothing to log.
  notReceipt,

  /// The per-user daily AI cap was reached (HTTP 429).
  rateLimited,

  /// Couldn't reach the backend at all (transport error) — retryable.
  networkError,

  /// Reached the backend but it errored (5xx, auth, unhandled op).
  serverError,

  /// Service not configured / signed out (no cloud vision available).
  unavailable,

  /// 200 OK but the body wasn't the shape we expected.
  failed,
}

class ReceiptParseResult {
  const ReceiptParseResult(
    this.status, {
    this.total,
    this.merchant,
    this.currency,
    this.date,
    this.categoryHint,
    this.confidence,
    this.httpStatus,
    this.detail,
  });

  final ReceiptParseStatus status;

  /// Grand total actually paid (> 0 when [status] is [ok]).
  final double? total;

  /// Vendor/store name as read from the receipt, cleaned up. May be null.
  final String? merchant;

  /// ISO currency code if the receipt showed one (e.g. "PHP"). Advisory only.
  final String? currency;

  /// Transaction date printed on the receipt, if any.
  final DateTime? date;

  /// One or two plain words describing the purchase, for categorisation.
  final String? categoryHint;

  /// Model's confidence in the extracted total, 0–1.
  final double? confidence;

  /// HTTP status on [serverError], for diagnostics.
  final int? httpStatus;

  /// Free-form diagnostic detail (never shown verbatim to the user).
  final String? detail;

  bool get isOk => status == ReceiptParseStatus.ok;

  factory ReceiptParseResult.fromJson(Map<String, dynamic> json) {
    final intent = json['intent'] as String?;
    if (intent != 'receipt') {
      return const ReceiptParseResult(ReceiptParseStatus.notReceipt);
    }
    final total = (json['total'] as num?)?.toDouble();
    if (total == null || total <= 0) {
      return const ReceiptParseResult(ReceiptParseStatus.notReceipt);
    }
    final rawDate = json['date'] as String?;
    return ReceiptParseResult(
      ReceiptParseStatus.ok,
      total: total,
      merchant: (json['merchant'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['merchant'] as String).trim(),
      currency: json['currency'] as String?,
      date: rawDate == null ? null : DateTime.tryParse(rawDate),
      categoryHint: (json['category_hint'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['category_hint'] as String).trim(),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
}

import 'extracted_entry.dart';
import 'finance_parse_result.dart';
import 'transaction_record.dart';

/// Where a captured money event came from.
enum CaptureSource { androidNotification, share, email }

/// Life of an inbox row: it waits, then the user approves or declines it.
enum CaptureStatus { pending, approved, declined }

/// One captured money event, from first sight to approve / decline.
///
/// Immutable. The [draft] is the same [ParsedTransaction] the chat, voice and
/// receipt paths produce, so the inbox row, the Add Transaction sheet and the
/// commit path all speak one type. See `.claude/plans/070-capture-inbox.md`.
class CapturedTransaction {
  final String id;
  final CaptureSource source;

  /// Package name for a notification, `share` for the share sheet, the
  /// sender's domain for email.
  final String sourceApp;

  /// Human label shown on the row ("GCash").
  final String sourceLabel;

  /// When the source posted it — the notification's post time.
  final DateTime capturedAt;
  final String rawTitle;

  /// What the parser read. Shown on tap so the user can check the parse.
  final String rawText;

  /// Dedupe key. Declined fingerprints are remembered for 30 days so a
  /// re-posted notification does not come back.
  final String fingerprint;

  final ParsedTransaction draft;

  /// 1.0 = per-app template matched, 0.6 = generic amount + direction,
  /// 0.3 = amount only.
  final double confidence;

  /// Masked card digits when the text carried them ("1234"); drives the
  /// per-card account map.
  final String? accountLast4;

  final CaptureStatus status;
  final DateTime? resolvedAt;

  /// Ledger record (or the outflow leg of a transfer) created on approve.
  final String? transactionId;

  final DateTime updatedAt;

  CapturedTransaction({
    required this.id,
    required this.source,
    required this.sourceApp,
    required this.sourceLabel,
    required this.capturedAt,
    required this.rawTitle,
    required this.rawText,
    required this.fingerprint,
    required this.draft,
    this.confidence = 0,
    this.accountLast4,
    this.status = CaptureStatus.pending,
    this.resolvedAt,
    this.transactionId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isPending => status == CaptureStatus.pending;

  /// Ready to post: amount, type, account and category (or the transfer
  /// destination) are all set. Date is never missing — the capture time is
  /// always known.
  bool get isReady => draft.isComplete;

  /// Structured fields the user still has to supply, in picker order.
  Set<EntryField> get missing {
    final m = <EntryField>{};
    if (draft.amount == null || draft.amount! <= 0) m.add(EntryField.amount);
    if (draft.type == null) m.add(EntryField.type);
    if (draft.accountId == null) m.add(EntryField.account);
    if (draft.type == TransactionType.transfer) {
      if (draft.transferToAccountId == null ||
          draft.transferToAccountId == draft.accountId) {
        m.add(EntryField.transferTo);
      }
    } else if (draft.categoryId == null) {
      m.add(EntryField.category);
    }
    return m;
  }

  CapturedTransaction copyWith({
    ParsedTransaction? draft,
    double? confidence,
    String? accountLast4,
    CaptureStatus? status,
    DateTime? resolvedAt,
    bool clearResolvedAt = false,
    String? transactionId,
    bool clearTransactionId = false,
    DateTime? updatedAt,
  }) =>
      CapturedTransaction(
        id: id,
        source: source,
        sourceApp: sourceApp,
        sourceLabel: sourceLabel,
        capturedAt: capturedAt,
        rawTitle: rawTitle,
        rawText: rawText,
        fingerprint: fingerprint,
        draft: draft ?? this.draft,
        confidence: confidence ?? this.confidence,
        accountLast4: accountLast4 ?? this.accountLast4,
        status: status ?? this.status,
        resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
        transactionId:
            clearTransactionId ? null : (transactionId ?? this.transactionId),
        updatedAt: updatedAt ?? DateTime.now(),
      );

  factory CapturedTransaction.fromJson(Map<String, dynamic> json) {
    final d = (json['draft'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CapturedTransaction(
      id: json['id'] as String,
      source: CaptureSource.values.asNameMap()[json['source'] as String?] ??
          CaptureSource.androidNotification,
      sourceApp: json['sourceApp'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      rawTitle: json['rawTitle'] as String? ?? '',
      rawText: json['rawText'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      draft: ParsedTransaction(
        amount: (d['amount'] as num?)?.toDouble(),
        type: TransactionType.values.asNameMap()[d['type'] as String?],
        accountId: d['accountId'] as String?,
        transferToAccountId: d['transferToAccountId'] as String?,
        categoryId: d['categoryId'] as String?,
        description: d['description'] as String? ?? '',
        descriptionIsClean: true,
        date: DateTime.tryParse(d['date'] as String? ?? ''),
        note: d['note'] as String?,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      accountLast4: json['accountLast4'] as String?,
      status: CaptureStatus.values.asNameMap()[json['status'] as String?] ??
          CaptureStatus.pending,
      resolvedAt: DateTime.tryParse(json['resolvedAt'] as String? ?? ''),
      transactionId: json['transactionId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'sourceApp': sourceApp,
        'sourceLabel': sourceLabel,
        'capturedAt': capturedAt.toIso8601String(),
        'rawTitle': rawTitle,
        'rawText': rawText,
        'fingerprint': fingerprint,
        'draft': {
          'amount': draft.amount,
          'type': draft.type?.name,
          'accountId': draft.accountId,
          'transferToAccountId': draft.transferToAccountId,
          'categoryId': draft.categoryId,
          'description': draft.description,
          'date': draft.date?.toIso8601String(),
          'note': draft.note,
        },
        'confidence': confidence,
        'accountLast4': accountLast4,
        'status': status.name,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'transactionId': transactionId,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

import 'transaction_record.dart';

/// What the regex+dict preprocessor produces from a raw chat input. The
/// classifier (AI) only runs when this can't fully resolve and there's no
/// hard error.
class PreparseResult {
  final double? amount;
  final TransactionType? type;
  final String? accountId;
  final String? transferToAccountId;
  final String? categoryId;

  /// The preprocessor suspects this expense is reimbursable (spent now, owed
  /// back). A non-binding suggestion — the form pre-checks the toggle so the
  /// user confirms. Orthogonal to [isFullyResolved].
  final bool reimbursable;

  /// Transaction date parsed from the text ("yesterday", "last friday",
  /// "aug 20"). Null means the message named no date, and the commit path
  /// stamps "now" as it always has.
  final DateTime? date;

  /// Free-text note, from a `note:` or `//` marker. Kept apart from the
  /// description, exactly as the manual form keeps them apart.
  final String? note;

  /// Who owes the money back, for a reimbursable expense ("spotted Jana 800").
  final String? owedBy;

  /// When the payback is expected. Null is "ASAP" — the same default the form
  /// uses — and is only set when the text names a date behind a payback cue.
  final DateTime? expectedReimbursementDate;

  final List<String> unresolvedTokens;
  final List<String> ambiguousAccountTokens;
  final FinanceParseError? hardError;
  final String rawInput;

  const PreparseResult({
    this.amount,
    this.type,
    this.accountId,
    this.transferToAccountId,
    this.categoryId,
    this.reimbursable = false,
    this.date,
    this.note,
    this.owedBy,
    this.expectedReimbursementDate,
    this.unresolvedTokens = const [],
    this.ambiguousAccountTokens = const [],
    this.hardError,
    required this.rawInput,
  });

  /// All required fields filled (no AI clarification needed).
  bool get isFullyResolved {
    if (amount == null || amount! <= 0) return false;
    if (type == null) return false;
    if (accountId == null) return false;
    if (type == TransactionType.transfer) {
      return transferToAccountId != null && transferToAccountId != accountId;
    }
    return categoryId != null;
  }

  /// A draft can be promoted to a TransactionRecord once fully resolved.
  ParsedTransaction toDraft() => ParsedTransaction(
        amount: amount,
        type: type,
        accountId: accountId,
        transferToAccountId: transferToAccountId,
        categoryId: categoryId,
        reimbursable: reimbursable,
        date: date,
        note: note,
        owedBy: owedBy,
        expectedReimbursementDate: expectedReimbursementDate,
        description: rawInput,
      );
}

/// What the preprocessor produces from one chat message, which may describe
/// more than one transaction ("500 food gcash and 300 grab bpi").
///
/// [segments] is never empty unless [hardError] is set: a message with no
/// recognised separator yields exactly one segment, so the single-entry path is
/// just the length-1 case of this and needs no special handling upstream.
class PreparseBatch {
  /// One result per transaction described, in the order they were written.
  final List<PreparseResult> segments;

  /// An error covering the whole message (empty, too long, viewing a past
  /// date). Per-segment problems live on each [PreparseResult] instead.
  final FinanceParseError? hardError;

  /// The original, unsegmented message.
  final String rawInput;

  const PreparseBatch({
    required this.segments,
    this.hardError,
    required this.rawInput,
  });

  const PreparseBatch.error(FinanceParseError error, this.rawInput)
      : segments = const [],
        hardError = error;

  bool get isMulti => segments.length > 1;

  /// Segments the regex+dictionary layer resolved completely — committable
  /// without consulting the AI at all.
  List<PreparseResult> get resolved =>
      segments.where((s) => s.hardError == null && s.isFullyResolved).toList();

  /// Segments still needing the AI (or the form): partially resolved, or
  /// individually hard-errored.
  List<PreparseResult> get unresolved =>
      segments.where((s) => s.hardError != null || !s.isFullyResolved).toList();

  bool get allResolved => segments.isNotEmpty && unresolved.isEmpty;
}

/// Accumulating draft of a transaction across one or more parse turns.
/// Each AI classifier turn merges new non-null fields onto the prior state.
class ParsedTransaction {
  final double? amount;
  final TransactionType? type;
  final String? accountId;
  final String? transferToAccountId;
  final String? categoryId;
  final String description;

  /// Suggested reimbursable expense (spent now, owed back). Carried into the
  /// commit/form so the reimbursable toggle starts on.
  final bool reimbursable;

  /// True when [description] is already a clean, human-meaningful label (the AI
  /// classifier wrote it) rather than raw chat input. When false the commit
  /// path strips extraction tokens (amount/account/etc.) out of it first.
  final bool descriptionIsClean;

  /// Transaction date. Null means "no date named" — the commit path stamps now.
  final DateTime? date;

  /// Free-text note, kept apart from [description] as the form keeps them.
  final String? note;

  /// Who owes a reimbursable expense back.
  final String? owedBy;

  /// Expected payback date; null is "ASAP".
  final DateTime? expectedReimbursementDate;

  const ParsedTransaction({
    this.amount,
    this.type,
    this.accountId,
    this.transferToAccountId,
    this.categoryId,
    this.reimbursable = false,
    this.date,
    this.note,
    this.owedBy,
    this.expectedReimbursementDate,
    this.description = '',
    this.descriptionIsClean = false,
  });

  bool get isComplete {
    if (amount == null || amount! <= 0) return false;
    if (type == null || accountId == null) return false;
    if (type == TransactionType.transfer) {
      return transferToAccountId != null && transferToAccountId != accountId;
    }
    return categoryId != null;
  }

  ParsedTransaction copyWith({
    double? amount,
    TransactionType? type,
    String? accountId,
    String? transferToAccountId,
    String? categoryId,
    bool? reimbursable,
    DateTime? date,
    String? note,
    String? owedBy,
    DateTime? expectedReimbursementDate,
    String? description,
    bool? descriptionIsClean,
  }) =>
      ParsedTransaction(
        amount: amount ?? this.amount,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        transferToAccountId: transferToAccountId ?? this.transferToAccountId,
        categoryId: categoryId ?? this.categoryId,
        reimbursable: reimbursable ?? this.reimbursable,
        date: date ?? this.date,
        note: note ?? this.note,
        owedBy: owedBy ?? this.owedBy,
        expectedReimbursementDate:
            expectedReimbursementDate ?? this.expectedReimbursementDate,
        description: description ?? this.description,
        descriptionIsClean: descriptionIsClean ?? this.descriptionIsClean,
      );

  /// Merge non-null fields from [other] onto this draft. [reimbursable] is
  /// sticky — once suggested it stays on (a later turn never silently clears
  /// it), so we only forward a `true`.
  ///
  /// [date], [note], [owedBy] and [expectedReimbursementDate] merge the same
  /// way as every other field: a later turn that says nothing about them leaves
  /// what the preparser deterministically extracted in place, rather than
  /// letting the model's silence erase it.
  ParsedTransaction mergeWith(ParsedTransaction other) => copyWith(
        amount: other.amount,
        type: other.type,
        accountId: other.accountId,
        transferToAccountId: other.transferToAccountId,
        categoryId: other.categoryId,
        reimbursable: other.reimbursable ? true : null,
        date: other.date,
        note: other.note,
        owedBy: other.owedBy,
        expectedReimbursementDate: other.expectedReimbursementDate,
        description: other.description.isEmpty ? null : other.description,
        descriptionIsClean:
            other.description.isEmpty ? null : other.descriptionIsClean,
      );
}

/// Hard-error categories that short-circuit before the AI ever runs.
enum FinanceParseError {
  empty,
  tooLong,
  noAmount,
  multipleAmounts,
  invalidAmount,
  signCategoryMismatch,
  noCategoriesForType,
  viewingPastDate,
}

extension FinanceParseErrorMessage on FinanceParseError {
  String get userMessage {
    switch (this) {
      case FinanceParseError.empty:
        return 'Type something to log.';
      case FinanceParseError.tooLong:
        return 'Keep it under 500 characters.';
      case FinanceParseError.noAmount:
        return 'I need an amount — try something like "-500 food gcash".';
      case FinanceParseError.multipleAmounts:
        return 'One amount per entry. Did you mean a transfer?';
      case FinanceParseError.invalidAmount:
        return 'Amount must be greater than zero.';
      case FinanceParseError.signCategoryMismatch:
        return 'Sign doesn\'t match the category (e.g. +500 with an expense).';
      case FinanceParseError.noCategoriesForType:
        return 'No categories of that type — add one first.';
      case FinanceParseError.viewingPastDate:
        return 'View only — clear the date filter to log.';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI classifier step (one per turn)
// ─────────────────────────────────────────────────────────────────────────────

/// Outcome of one AI classifier turn. Closed set — switch over it exhaustively.
sealed class ClassifierStep {
  const ClassifierStep();
}

/// AI is confident — has all required fields. Presenter shows summary +
/// [Yes/Edit/Cancel] row; commits only on user Yes.
class StepResolved extends ClassifierStep {
  /// Every transaction being confirmed together. Length 1 for the ordinary
  /// single-entry case; longer when one chat message described several.
  final List<ParsedTransaction> transactions;

  /// Token to learn into the personal dictionary on confirm (e.g. "hamburger"
  /// → "Food"). Null when nothing new was learned this turn.
  final String? learnedToken;

  final String summaryText;

  /// Segments of a multi-transaction message that could NOT be resolved. They
  /// are not part of [transactions] and are not committed on confirm — the
  /// presenter hands the first one to the clarify loop afterwards so the user
  /// settles them one at a time.
  final List<PreparseResult> deferred;

  StepResolved({
    required ParsedTransaction transaction,
    this.learnedToken,
    required this.summaryText,
  })  : transactions = List.unmodifiable([transaction]),
        deferred = const [],
        _learnedPairs = null;

  StepResolved.batch({
    required List<ParsedTransaction> transactions,
    required this.summaryText,
    List<PreparseResult> deferred = const [],
    Map<String, String> learnedPairs = const {},
  })  : transactions = List.unmodifiable(transactions),
        deferred = List.unmodifiable(deferred),
        learnedToken = null,
        _learnedPairs = Map.unmodifiable(learnedPairs);

  /// Explicit token→categoryId pairs to learn on confirm.
  ///
  /// A batch needs these rather than a bare [learnedToken]: each segment learns
  /// against *its own* category, and pairing one segment's token with another
  /// segment's category would persist a mapping the user never confirmed.
  final Map<String, String>? _learnedPairs;

  /// Everything to learn on confirm, as token → categoryId. Derived from
  /// [learnedToken] for a single transaction, explicit for a batch.
  Map<String, String> get learnedPairs {
    final pairs = _learnedPairs;
    if (pairs != null) return pairs;
    final token = learnedToken;
    final categoryId = transactions.first.categoryId;
    if (token == null || categoryId == null) return const {};
    return {token: categoryId};
  }

  /// The first (and usually only) transaction.
  ParsedTransaction get transaction => transactions.first;

  bool get isBatch => transactions.length > 1;
}

/// AI needs more info. Render [question] above the input and optionally render
/// [quickReplies] as tappable chips.
class StepClarify extends ClassifierStep {
  final String question;
  final List<QuickReply>? quickReplies;
  final ParsedTransaction partialDraft;

  const StepClarify({
    required this.question,
    this.quickReplies,
    required this.partialDraft,
  });
}

/// AI couldn't resolve — open the form prefilled with what we know.
class StepGiveUp extends ClassifierStep {
  final String reason;
  final ParsedTransaction partialDraft;

  const StepGiveUp({required this.reason, required this.partialDraft});
}

/// A tappable chip shown alongside a clarifying question. [replyText] is
/// inserted into the input as the user's reply, then sent.
class QuickReply {
  final String label;
  final String replyText;

  const QuickReply({required this.label, required this.replyText});

  factory QuickReply.fromJson(Map<String, dynamic> json) => QuickReply(
        label: json['label'] as String? ?? '',
        replyText: json['replyText'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ephemeral chat state (lives in LedgerPresenter, never persisted)
// ─────────────────────────────────────────────────────────────────────────────

enum ChatPhase { idle, classifying, clarifying }

class LedgerChatTurn {
  final String text;
  final bool isUser;
  final List<QuickReply>? quickReplies;
  final DateTime at;

  const LedgerChatTurn({
    required this.text,
    required this.isUser,
    this.quickReplies,
    required this.at,
  });
}

class LedgerChatState {
  final ChatPhase phase;
  final List<LedgerChatTurn> turns;
  final ParsedTransaction draft;
  final int turnCount;
  final ClassifierStep? lastStep;

  const LedgerChatState({
    this.phase = ChatPhase.idle,
    this.turns = const [],
    this.draft = const ParsedTransaction(),
    this.turnCount = 0,
    this.lastStep,
  });

  const LedgerChatState.idle() : this();

  LedgerChatState copyWith({
    ChatPhase? phase,
    List<LedgerChatTurn>? turns,
    ParsedTransaction? draft,
    int? turnCount,
    ClassifierStep? lastStep,
    bool clearLastStep = false,
  }) =>
      LedgerChatState(
        phase: phase ?? this.phase,
        turns: turns ?? this.turns,
        draft: draft ?? this.draft,
        turnCount: turnCount ?? this.turnCount,
        lastStep: clearLastStep ? null : (lastStep ?? this.lastStep),
      );
}

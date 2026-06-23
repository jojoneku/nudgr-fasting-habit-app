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
        description: rawInput,
      );
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

  /// True when [description] is already a clean, human-meaningful label (the AI
  /// classifier wrote it) rather than raw chat input. When false the commit
  /// path strips extraction tokens (amount/account/etc.) out of it first.
  final bool descriptionIsClean;

  const ParsedTransaction({
    this.amount,
    this.type,
    this.accountId,
    this.transferToAccountId,
    this.categoryId,
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
    String? description,
    bool? descriptionIsClean,
  }) =>
      ParsedTransaction(
        amount: amount ?? this.amount,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        transferToAccountId: transferToAccountId ?? this.transferToAccountId,
        categoryId: categoryId ?? this.categoryId,
        description: description ?? this.description,
        descriptionIsClean: descriptionIsClean ?? this.descriptionIsClean,
      );

  /// Merge non-null fields from [other] onto this draft.
  ParsedTransaction mergeWith(ParsedTransaction other) => copyWith(
        amount: other.amount,
        type: other.type,
        accountId: other.accountId,
        transferToAccountId: other.transferToAccountId,
        categoryId: other.categoryId,
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
  final ParsedTransaction transaction;

  /// Token to learn into the personal dictionary on confirm (e.g. "hamburger"
  /// → "Food"). Null when nothing new was learned this turn.
  final String? learnedToken;

  final String summaryText;

  const StepResolved({
    required this.transaction,
    this.learnedToken,
    required this.summaryText,
  });
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

// Parser + validator for the AI classifier's JSON response (Plan 026 §3.3).
//
// Pulled out of [OnDeviceAiCoachService] so it can be unit-tested without
// mocking flutter_gemma. Pure logic — no I/O.
//
// Every named entity in the model output is validated against the live
// account / category lists; hallucinated names downgrade the step to
// [StepGiveUp] rather than passing through.

import 'dart:convert';

import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/transaction_record.dart';

/// Below this confidence the AI's `resolved` step is downgraded to `clarify`
/// to ask the user to confirm explicitly.
const double kFinanceClassifierConfidenceFloor = 0.6;

/// Parses [text] (raw AI output, possibly with prose around the JSON) into a
/// [ClassifierStep]. Returns null when no JSON object can be extracted or
/// when the response shape is unrecognized.
ClassifierStep? parseFinanceClassifierResponse({
  required String text,
  required List<FinancialAccount> accounts,
  required List<FinanceCategory> categories,
  required PreparseResult preparse,
}) {
  final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
  if (match == null) return null;

  final dynamic decoded;
  try {
    decoded = jsonDecode(match.group(0)!);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final step = decoded['step'] as String?;
  final draft = preparse.toDraft();

  switch (step) {
    case 'clarify':
      final question = (decoded['question'] as String?)?.trim() ?? '';
      if (question.isEmpty) return null;
      final rawReplies = decoded['quickReplies'];
      final replies = (rawReplies is List)
          ? rawReplies
              .whereType<Map<String, dynamic>>()
              .map(QuickReply.fromJson)
              .where((r) => r.label.isNotEmpty)
              .toList()
          : null;
      return StepClarify(
        question: question,
        quickReplies: replies == null || replies.isEmpty ? null : replies,
        partialDraft: draft,
      );

    case 'give_up':
      return StepGiveUp(
        reason: (decoded['reason'] as String?)?.trim() ?? 'Could not resolve.',
        partialDraft: draft,
      );

    case 'resolved':
      final confidence = (decoded['confidence'] as num?)?.toDouble();
      if (confidence != null &&
          confidence < kFinanceClassifierConfidenceFloor) {
        return StepClarify(
          question: 'I\'m not sure — can you confirm the account and category?',
          partialDraft: draft,
        );
      }

      final amount = (decoded['amount'] as num?)?.toDouble() ?? preparse.amount;
      final typeName = decoded['type'] as String?;
      final type =
          TransactionType.values.where((t) => t.name == typeName).firstOrNull;
      if (amount == null || amount <= 0 || type == null) {
        return StepGiveUp(
            reason: 'Missing required fields.', partialDraft: draft);
      }

      final accountId =
          _findAccountIdByName(decoded['account'] as String?, accounts);
      if (accountId == null) {
        return StepGiveUp(
            reason: 'Account not in the list.', partialDraft: draft);
      }

      String? transferToId;
      String? categoryId;
      if (type == TransactionType.transfer) {
        transferToId =
            _findAccountIdByName(decoded['transferTo'] as String?, accounts);
        if (transferToId == null || transferToId == accountId) {
          return StepGiveUp(
              reason: 'Transfer destination missing.', partialDraft: draft);
        }
      } else {
        final cat =
            _findCategoryByName(decoded['category'] as String?, categories);
        if (cat == null) {
          return StepGiveUp(
              reason: 'Category not in the list.', partialDraft: draft);
        }
        final wanted = cat.type == CategoryType.income
            ? TransactionType.inflow
            : TransactionType.outflow;
        if (type != wanted) {
          return StepGiveUp(
              reason: 'Category type doesn\'t match the amount sign.',
              partialDraft: draft);
        }
        categoryId = cat.id;
      }

      final summary = (decoded['summaryText'] as String?)?.trim() ??
          'Log this transaction?';
      final learnedToken = (decoded['learnedToken'] as String?)?.trim();

      return StepResolved(
        transaction: ParsedTransaction(
          amount: amount,
          type: type,
          accountId: accountId,
          transferToAccountId: transferToId,
          categoryId: categoryId,
          description: preparse.rawInput,
        ),
        learnedToken: (learnedToken == null || learnedToken.isEmpty)
            ? null
            : learnedToken,
        summaryText: summary,
      );
  }
  return null;
}

String? _findAccountIdByName(String? name, List<FinancialAccount> accounts) {
  if (name == null || name.trim().isEmpty) return null;
  final n = name.trim().toLowerCase();
  for (final a in accounts) {
    if (a.name.toLowerCase() == n) return a.id;
  }
  return null;
}

FinanceCategory? _findCategoryByName(
    String? name, List<FinanceCategory> categories) {
  if (name == null || name.trim().isEmpty) return null;
  final n = name.trim().toLowerCase();
  for (final c in categories) {
    if (c.name.toLowerCase() == n) return c;
  }
  return null;
}

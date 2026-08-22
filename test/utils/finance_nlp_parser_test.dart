import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_nlp_parser.dart';

FinancialAccount _acc(String name,
        {String? id, AccountCategory cat = AccountCategory.bank}) =>
    FinancialAccount(
      id: id ?? name.toLowerCase(),
      name: name,
      category: cat,
      balance: 0,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String name, CategoryType type, {String? id}) =>
    FinanceCategory(
      id: id ?? name.toLowerCase(),
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

void main() {
  final bpi = _acc('BPI');
  final bdo = _acc('BDO');
  final gcash = _acc('GCash', cat: AccountCategory.ewallet);
  final cash = _acc('Cash', cat: AccountCategory.cash);

  final food = _cat('Food', CategoryType.expense);
  final salary = _cat('Salary', CategoryType.income);
  final transport = _cat('Transportation', CategoryType.expense);

  final accounts = [bpi, bdo, gcash, cash];
  final categories = [food, salary, transport];

  PreparseResult run(String input,
      {Map<String, String> dict = const {},
      List<FinancialAccount>? overrideAccounts,
      List<FinanceCategory>? overrideCategories,
      bool viewingPastDate = false}) {
    return preparseFinanceInput(
      input: input,
      categories: overrideCategories ?? categories,
      accounts: overrideAccounts ?? accounts,
      learnedDict: dict,
      viewingPastDate: viewingPastDate,
    );
  }

  group('hard errors', () {
    test('empty input', () {
      expect(run('').hardError, FinanceParseError.empty);
      expect(run('   ').hardError, FinanceParseError.empty);
    });

    test('input over 500 chars', () {
      expect(run('a' * 501).hardError, FinanceParseError.tooLong);
    });

    test('no digits anywhere', () {
      expect(run('food gcash').hardError, FinanceParseError.noAmount);
    });

    test('multiple amounts', () {
      expect(run('-500 -300 food gcash').hardError,
          FinanceParseError.multipleAmounts);
    });

    test('zero amount', () {
      expect(run('0 food gcash').hardError, FinanceParseError.invalidAmount);
    });

    test('sign / category mismatch (+ with expense category)', () {
      expect(run('+500 food gcash').hardError,
          FinanceParseError.signCategoryMismatch);
    });

    test('no categories of the inferred type', () {
      expect(
        run('+500 gcash', overrideCategories: [food, transport]).hardError,
        FinanceParseError.noCategoriesForType,
      );
    });

    test('viewing past date short-circuits', () {
      expect(run('-500 food gcash', viewingPastDate: true).hardError,
          FinanceParseError.viewingPastDate);
    });
  });

  group('signed amount happy paths', () {
    test('-500 food gcash → fully resolved outflow', () {
      final r = run('-500 food gcash');
      expect(r.hardError, isNull);
      expect(r.amount, 500);
      expect(r.type, TransactionType.outflow);
      expect(r.accountId, gcash.id);
      expect(r.categoryId, food.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('+5000 salary bpi → fully resolved inflow', () {
      final r = run('+5000 salary bpi');
      expect(r.amount, 5000);
      expect(r.type, TransactionType.inflow);
      expect(r.accountId, bpi.id);
      expect(r.categoryId, salary.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('unsigned amount with unambiguous expense category → outflow', () {
      final r = run('500 food gcash');
      expect(r.type, TransactionType.outflow);
      expect(r.isFullyResolved, isTrue);
    });

    test('unsigned amount with unambiguous income category → inflow', () {
      final r = run('1000 salary bpi');
      expect(r.type, TransactionType.inflow);
      expect(r.isFullyResolved, isTrue);
    });
  });

  group('normalization', () {
    test('strips ₱ currency prefix', () {
      final r = run('-₱500 food gcash');
      expect(r.amount, 500);
      expect(r.isFullyResolved, isTrue);
    });

    test('strips php currency prefix', () {
      final r = run('-php500 food gcash');
      expect(r.amount, 500);
    });

    test('strips php currency suffix', () {
      final r = run('-500php food gcash');
      expect(r.amount, 500);
    });

    test('strips ₱ currency suffix', () {
      final r = run('-500₱ food gcash');
      expect(r.amount, 500);
    });

    test('strips spaced "pesos" suffix', () {
      final r = run('-500 pesos food gcash');
      expect(r.amount, 500);
    });

    test('suffix p does not eat a word starting with p', () {
      final r = run('-120 plates gcash');
      expect(r.amount, 120);
    });

    test('strips thousand-commas', () {
      final r = run('-1,500 food gcash');
      expect(r.amount, 1500);
    });

    test('decimal amounts preserved', () {
      final r = run('-99.50 food gcash');
      expect(r.amount, 99.5);
    });

    test('case-insensitive account/category', () {
      final r = run('-500 FOOD GCASH');
      expect(r.accountId, gcash.id);
      expect(r.categoryId, food.id);
    });
  });

  group('paid for someone (card → cash)', () {
    final cc = _acc('CC', cat: AccountCategory.creditCard);
    final withCard = [bpi, gcash, cash, cc];

    test('payback phrasing routes to a CC → Cash transfer', () {
      final r = run('paid 800 on my cc for jana, she paid me back',
          overrideAccounts: withCard);
      expect(r.type, TransactionType.transfer);
      expect(r.amount, 800);
      expect(r.accountId, cc.id); // from = the card charged
      expect(r.transferToAccountId, cash.id); // to = cash they handed back
    });

    test('"refunded" also counts as a payback signal', () {
      final r = run('spotted 1200 cc for mike refunded in cash',
          overrideAccounts: withCard);
      expect(r.type, TransactionType.transfer);
      expect(r.accountId, cc.id);
    });

    test('no payback signal stays a normal expense, not a transfer', () {
      // Money hasn't come back yet — must NOT become a wash transfer.
      final r = run('paid 500 for jana', overrideAccounts: withCard);
      expect(r.type, isNot(TransactionType.transfer));
    });
  });

  group('reimbursable suggestion', () {
    test('"work expense" flags the expense as reimbursable', () {
      final r = run('1200 hotel bpi work expense');
      expect(r.reimbursable, isTrue);
    });

    test('"reimbursable" keyword on a fully-resolved expense', () {
      final r = run('500 food gcash reimbursable');
      expect(r.reimbursable, isTrue);
      expect(r.type, TransactionType.outflow);
      expect(r.isFullyResolved, isTrue); // commits straight as reimbursable
    });

    test('future "she\'ll pay me back" → reimbursable, not a transfer', () {
      final r = run("200 food gcash she'll pay me back");
      expect(r.reimbursable, isTrue);
      expect(r.type, isNot(TransactionType.transfer));
    });

    test('no signal → not reimbursable', () {
      expect(run('500 food gcash').reimbursable, isFalse);
    });

    test('income is never flagged reimbursable', () {
      // Explicit + sign makes it income; the suggestion must not apply.
      final r = run('+5000 salary bpi reimbursable');
      expect(r.reimbursable, isFalse);
    });
  });

  group('account fuzzy + prefix matching', () {
    test('prefix match resolves "gca" → GCash (single hit)', () {
      final r = run('-500 food gca');
      expect(r.accountId, gcash.id);
    });

    test('ambiguous account prefix records the token, no resolve', () {
      final bpiSave = _acc('BPI Savings');
      final r = run('-500 food b',
          overrideAccounts: [bpi, bpiSave, bdo, gcash, cash]);
      expect(r.accountId, isNull);
      expect(r.ambiguousAccountTokens, contains('b'));
    });

    test('fuzzy Levenshtein 1 — "gcsh" → GCash', () {
      final r = run('-500 food gcsh');
      expect(r.accountId, gcash.id);
    });

    test('too short for fuzzy match', () {
      final r = run('-500 food gc');
      expect(r.accountId, isNull);
    });
  });

  group('personal dictionary fallback', () {
    test('learned token resolves to category', () {
      final r = run('-500 gcash hamburger', dict: {'hamburger': food.id});
      expect(r.categoryId, food.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('learned token referencing a deleted category is ignored', () {
      final r = run('-500 gcash hamburger', dict: {'hamburger': 'deleted-id'});
      expect(r.categoryId, isNull);
      expect(r.unresolvedTokens, contains('hamburger'));
    });
  });

  group('unresolved tokens', () {
    test('unknown tokens captured for AI fallback', () {
      final r = run('500 gcash hamburger');
      expect(r.amount, 500);
      expect(r.accountId, gcash.id);
      expect(r.unresolvedTokens, contains('hamburger'));
      expect(r.isFullyResolved, isFalse);
    });

    test('no account, no category, just amount', () {
      final r = run('500 something');
      expect(r.amount, 500);
      expect(r.accountId, isNull);
      expect(r.categoryId, isNull);
      expect(r.unresolvedTokens, contains('something'));
    });
  });

  group('transfers', () {
    test('"transfer 1000 bpi gcash" → fully resolved transfer', () {
      final r = run('transfer 1000 bpi gcash');
      expect(r.type, TransactionType.transfer);
      expect(r.amount, 1000);
      expect(r.accountId, bpi.id);
      expect(r.transferToAccountId, gcash.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('alias "trf" routes through transfer pattern', () {
      final r = run('trf 1000 bpi gcash');
      expect(r.type, TransactionType.transfer);
    });

    test('arrow alias "->" routes through transfer pattern', () {
      final r = run('1000 bpi -> gcash');
      expect(r.type, TransactionType.transfer);
      expect(r.transferToAccountId, gcash.id);
    });

    test('missing target account leaves transferToAccountId null', () {
      final r = run('transfer 1000 bpi');
      expect(r.type, TransactionType.transfer);
      expect(r.accountId, bpi.id);
      expect(r.transferToAccountId, isNull);
      expect(r.isFullyResolved, isFalse);
    });

    test('"transfer" with "to" separator', () {
      final r = run('transfer 500 bpi to gcash');
      expect(r.accountId, bpi.id);
      expect(r.transferToAccountId, gcash.id);
    });
  });

  group('excluded accounts', () {
    test('inactive accounts not matched', () {
      final inactive = FinancialAccount(
        id: 'old',
        name: 'OldBank',
        category: AccountCategory.bank,
        balance: 0,
        colorHex: '#FFFFFF',
        icon: 'wallet',
        isActive: false,
      );
      final r = run('-500 food oldbank',
          overrideAccounts: [bpi, bdo, gcash, cash, inactive]);
      expect(r.accountId, isNull);
    });

    test('sub-accounts not matched', () {
      final sub = FinancialAccount(
        id: 'maya-savings',
        name: 'MayaSavings',
        category: AccountCategory.savings,
        parentAccountId: 'maya',
        balance: 0,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );
      final r = run('-500 food mayasavings',
          overrideAccounts: [bpi, bdo, gcash, cash, sub]);
      expect(r.accountId, isNull);
    });

    test('custodian accounts not matched', () {
      final custodian = FinancialAccount(
        id: 'cust',
        name: 'Custodian',
        category: AccountCategory.custodian,
        balance: 0,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );
      final r = run('-500 food custodian',
          overrideAccounts: [bpi, bdo, gcash, cash, custodian]);
      expect(r.accountId, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Multi-word account names — the "BPI Personal vs BPI Vybe" complaint.
  // ───────────────────────────────────────────────────────────────────────────

  group('multi-word account names', () {
    final bpiPersonal = _acc('BPI Personal', id: 'bpi-personal');
    final bpiVybe = _acc('BPI Vybe', id: 'bpi-vybe');
    final bpiCc = _acc('BPI CC', id: 'bpi-cc', cat: AccountCategory.creditCard);
    final multi = [bpiPersonal, bpiVybe, bpiCc, gcash, cash];

    test('the full name resolves instead of asking which BPI', () {
      final r = run('-500 food bpi personal', overrideAccounts: multi);
      expect(r.accountId, bpiPersonal.id);
      expect(r.ambiguousAccountTokens, isEmpty);
      expect(r.isFullyResolved, isTrue);
    });

    test('word order inside the message does not matter', () {
      final r = run('bpi personal -500 food', overrideAccounts: multi);
      expect(r.accountId, bpiPersonal.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('a sibling multi-word name resolves to itself, not its sibling', () {
      final r = run('-500 food bpi vybe', overrideAccounts: multi);
      expect(r.accountId, bpiVybe.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('the shared first word alone is still ambiguous', () {
      final r = run('-500 food bpi', overrideAccounts: multi);
      expect(r.accountId, isNull);
      expect(r.ambiguousAccountTokens, contains('bpi'));
    });

    test('a partial second word still resolves ("bpi pers")', () {
      final r = run('-500 food bpi pers', overrideAccounts: multi);
      expect(r.accountId, bpiPersonal.id);
    });

    test('matching the name whole does not eat the category token', () {
      final r = run('bpi personal 500 food', overrideAccounts: multi);
      expect(r.accountId, bpiPersonal.id);
      expect(r.categoryId, food.id);
      expect(r.unresolvedTokens, isEmpty);
    });

    test('unknown words survive the account sweep for the AI', () {
      final r = run('500 bpi personal jollibee', overrideAccounts: multi);
      expect(r.accountId, bpiPersonal.id);
      expect(r.unresolvedTokens, contains('jollibee'));
    });
  });

  group('transfer direction', () {
    final bpiPersonal = _acc('BPI Personal', id: 'bpi-personal');
    final bpiVybe = _acc('BPI Vybe', id: 'bpi-vybe');
    final multi = [bpiPersonal, bpiVybe, gcash, cash];

    test('both legs resolve when the source name is multi-word', () {
      final r =
          run('transfer 1000 bpi personal to gcash', overrideAccounts: multi);
      expect(r.type, TransactionType.transfer);
      expect(r.accountId, bpiPersonal.id);
      expect(r.transferToAccountId, gcash.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('both legs resolve when the destination name is multi-word', () {
      final r = run('transfer 1000 gcash to bpi vybe', overrideAccounts: multi);
      expect(r.accountId, gcash.id);
      expect(r.transferToAccountId, bpiVybe.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('"from" marks the source even when it comes second', () {
      final r = run('transfer 500 to gcash from bpi personal',
          overrideAccounts: multi);
      expect(r.accountId, bpiPersonal.id);
      expect(r.transferToAccountId, gcash.id);
    });

    test('a bare "from" makes the leading label the destination', () {
      final r =
          run('transfer 500 gcash from bpi vybe', overrideAccounts: multi);
      expect(r.accountId, bpiVybe.id);
      expect(r.transferToAccountId, gcash.id);
    });

    test('"into" behaves like "to"', () {
      final r =
          run('transfer 250 bpi personal into cash', overrideAccounts: multi);
      expect(r.accountId, bpiPersonal.id);
      expect(r.transferToAccountId, cash.id);
    });

    test('an ambiguous source no longer steals the destination slot', () {
      // "bpi" matches two accounts. Previously the resolver filled `from` with
      // the first thing that resolved — gcash, the stated destination — and
      // left `to` empty, silently reversing the transfer.
      final r = run('transfer 1000 bpi to gcash', overrideAccounts: multi);
      expect(r.accountId, isNull);
      expect(r.transferToAccountId, gcash.id);
      expect(r.ambiguousAccountTokens, contains('bpi'));
      expect(r.isFullyResolved, isFalse);
    });

    test('same account on both sides leaves the destination unset', () {
      final r = run('transfer 100 gcash to gcash', overrideAccounts: multi);
      expect(r.accountId, gcash.id);
      expect(r.transferToAccountId, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Multiple transactions in one message.
  // ───────────────────────────────────────────────────────────────────────────

  group('batch segmentation', () {
    PreparseBatch batch(String input,
        {Map<String, String> dict = const {},
        List<FinancialAccount>? overrideAccounts,
        bool viewingPastDate = false}) {
      return preparseFinanceBatch(
        input: input,
        categories: categories,
        accounts: overrideAccounts ?? accounts,
        learnedDict: dict,
        viewingPastDate: viewingPastDate,
      );
    }

    test('a single transaction is a one-segment batch', () {
      final b = batch('-500 food gcash');
      expect(b.isMulti, isFalse);
      expect(b.segments, hasLength(1));
      expect(b.allResolved, isTrue);
    });

    test('"and" splits two fully-resolved entries', () {
      final b = batch('-500 food gcash and -300 transportation bpi');
      expect(b.segments, hasLength(2));
      expect(b.allResolved, isTrue);
      expect(b.segments[0].accountId, gcash.id);
      expect(b.segments[0].categoryId, food.id);
      expect(b.segments[1].accountId, bpi.id);
      expect(b.segments[1].categoryId, transport.id);
    });

    test('commas, semicolons and newlines all split', () {
      for (final sep in [', ', '; ', '\n']) {
        final b =
            batch(['-500 food gcash', '-300 transportation bpi'].join(sep));
        expect(b.segments, hasLength(2), reason: 'separator "$sep"');
        expect(b.allResolved, isTrue, reason: 'separator "$sep"');
      }
    });

    test('three entries in one message', () {
      final b =
          batch('-500 food gcash; -300 transportation bpi; +5000 salary bdo');
      expect(b.segments, hasLength(3));
      expect(b.allResolved, isTrue);
      expect(b.segments[2].type, TransactionType.inflow);
    });

    test('a transfer and an expense in one message', () {
      final b = batch('transfer 1000 bpi to gcash and -200 food cash');
      expect(b.segments, hasLength(2));
      expect(b.segments[0].type, TransactionType.transfer);
      expect(b.segments[0].transferToAccountId, gcash.id);
      expect(b.segments[1].type, TransactionType.outflow);
      expect(b.allResolved, isTrue);
    });

    test('a partially-resolved segment is reported, not fatal', () {
      final b = batch('-500 food gcash and -300 hamburger bpi');
      expect(b.segments, hasLength(2));
      expect(b.resolved, hasLength(1));
      expect(b.unresolved, hasLength(1));
      expect(b.unresolved.first.unresolvedTokens, contains('hamburger'));
      expect(b.allResolved, isFalse);
    });

    test('"and" inside a description does not split it', () {
      // Only one piece carries a digit, so this is one transaction and the
      // description stays whole.
      final b = batch('coffee and donuts 150 gcash');
      expect(b.isMulti, isFalse);
      expect(b.segments.first.rawInput, 'coffee and donuts 150 gcash');
      expect(b.segments.first.amount, 150);
    });

    test('a thousand-comma is not a separator', () {
      final b = batch('-1,500 food gcash');
      expect(b.isMulti, isFalse);
      expect(b.segments.first.amount, 1500);
      expect(b.segments.first.isFullyResolved, isTrue);
    });

    test('the payback wash transfer survives its comma', () {
      final b = batch('paid 800 on my cc for jana, she paid me back',
          overrideAccounts: [
            bpi,
            gcash,
            cash,
            _acc('CC', id: 'cc', cat: AccountCategory.creditCard),
          ]);
      expect(b.isMulti, isFalse);
      expect(b.segments.first.type, TransactionType.transfer);
    });

    test('two amounts with no separator stay one ambiguous entry', () {
      final b = batch('-500 -300 food gcash');
      expect(b.isMulti, isFalse);
      expect(b.segments.first.hardError, FinanceParseError.multipleAmounts);
    });

    test('whole-message errors are reported once, not per segment', () {
      expect(batch('').hardError, FinanceParseError.empty);
      expect(batch('').segments, isEmpty);
      expect(
          batch('-500 food gcash and -300 transportation bpi',
                  viewingPastDate: true)
              .hardError,
          FinanceParseError.viewingPastDate);
      expect(batch('x' * 501).hardError, FinanceParseError.tooLong);
    });

    test('non-amount noise pieces are dropped, not parsed', () {
      final b = batch('logged: -500 food gcash and -300 transportation bpi');
      expect(b.segments, hasLength(2));
      expect(b.allResolved, isTrue);
    });
  });

  group('smarter no-AI fallback', () {
    test('a learned token survives a typo', () {
      final r = run('-500 gcash jollibe', dict: {'jollibee': food.id});
      expect(r.categoryId, food.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('a learned token survives trailing punctuation', () {
      final r = run('-500 gcash jollibee!', dict: {'jollibee': food.id});
      expect(r.categoryId, food.id);
    });

    test('two learned tokens equally near a typo do not resolve it', () {
      // "grab" and "crab" are both one edit from "arab" — recalling the user's
      // own mapping is fine, picking between two of them is not.
      final r =
          run('-500 gcash arab', dict: {'grab': transport.id, 'crab': food.id});
      expect(r.categoryId, isNull);
      expect(r.unresolvedTokens, contains('arab'));
    });

    test('a typo near two tokens sharing one category still resolves', () {
      final r = run('-500 gcash arab',
          dict: {'grab': transport.id, 'crab': transport.id});
      expect(r.categoryId, transport.id);
    });

    test('the sole loggable account needs no naming', () {
      final r = run('-500 food', overrideAccounts: [gcash]);
      expect(r.accountId, gcash.id);
      expect(r.isFullyResolved, isTrue);
    });

    test('a named account still wins over the sole-account fallback', () {
      final r = run('-500 food gcash', overrideAccounts: [gcash]);
      expect(r.accountId, gcash.id);
    });

    test('with several accounts an unnamed one stays unresolved', () {
      final r = run('-500 food');
      expect(r.accountId, isNull);
      expect(r.isFullyResolved, isFalse);
    });
  });
}

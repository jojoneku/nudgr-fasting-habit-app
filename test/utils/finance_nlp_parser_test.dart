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
}

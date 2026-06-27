import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/quick_log_router.dart';

void main() {
  group('QuickLogRouter.route', () {
    QuickLogTarget route(String t, {Set<String> accounts = const {}}) =>
        QuickLogRouter.route(t, accountNames: accounts);

    group('→ finance', () {
      test('money verb', () {
        expect(route('spent 200 on coffee'), QuickLogTarget.finance);
        expect(route('paid 50 jeepney'), QuickLogTarget.finance);
        expect(route('bought groceries 1200'), QuickLogTarget.finance);
        expect(route('salary 25000'), QuickLogTarget.finance);
        expect(route('refund 300'), QuickLogTarget.finance);
        expect(route('transfer 1000 bpi gcash'), QuickLogTarget.finance);
      });

      test('currency marker', () {
        expect(route('₱150 grab'), QuickLogTarget.finance);
        expect(route('\$20 lunch out'), QuickLogTarget.finance);
        expect(route('150 php load'), QuickLogTarget.finance);
        expect(route('p200 parking'), QuickLogTarget.finance);
        expect(route('500 pesos taxi'), QuickLogTarget.finance);
      });

      test('signed amount', () {
        expect(route('-500 food gcash'), QuickLogTarget.finance);
        expect(route('+25000 salary'), QuickLogTarget.finance);
      });

      test('known account name token', () {
        expect(
          route('500 gcash hamburger', accounts: {'gcash', 'bpi'}),
          QuickLogTarget.finance,
        );
        expect(
          route('1200 from bpi', accounts: {'gcash', 'bpi'}),
          QuickLogTarget.finance,
        );
      });
    });

    group('→ nutrition', () {
      test('plain food, no money signal', () {
        expect(route('2 eggs and rice'), QuickLogTarget.nutrition);
        expect(route('chicken breast 200g'), QuickLogTarget.nutrition);
        expect(route('ate adobo'), QuickLogTarget.nutrition);
        expect(route('1 cup rice'), QuickLogTarget.nutrition);
        expect(route('had a banana'), QuickLogTarget.nutrition);
      });

      test('exercise routes to nutrition', () {
        expect(route('ran 5km'), QuickLogTarget.nutrition);
        expect(route('walked 30 minutes'), QuickLogTarget.nutrition);
      });

      test('bare amount + word without a finance cue defaults to nutrition',
          () {
        // No verb, currency, sign, or known account → recoverable default.
        expect(route('150 grab'), QuickLogTarget.nutrition);
      });

      test('empty / whitespace', () {
        expect(route(''), QuickLogTarget.nutrition);
        expect(route('   '), QuickLogTarget.nutrition);
      });
    });

    group('word-boundary safety', () {
      test('finance verbs do not match inside larger words', () {
        // "payday"/"billboard"/"buying"-free food text must not route finance.
        expect(route('billboard sandwich'), QuickLogTarget.nutrition);
        expect(route('payday cake'), QuickLogTarget.nutrition);
      });

      test('account name does not match inside a larger word', () {
        // "cash" account must not trip on "cashew".
        expect(
          route('cashew nuts 30g', accounts: {'cash'}),
          QuickLogTarget.nutrition,
        );
      });
    });
  });
}

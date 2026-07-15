import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/presenters/hub_presenter.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockStorageService storage;
  late MockFastingPresenter fasting;
  late MockQuestPresenter quests;

  // Closure-backed in-memory persistence for the saved card order.
  List<String> savedOrder = [];

  setUp(() {
    savedOrder = [];
    storage = MockStorageService();
    fasting = MockFastingPresenter();
    quests = MockQuestPresenter();

    when(fasting.isFasting).thenReturn(false);
    when(quests.hasUrgentQuest).thenReturn(false);
    when(storage.loadHubCardOrder())
        .thenAnswer((_) async => List.of(savedOrder));
    when(storage.saveHubCardOrder(any)).thenAnswer((inv) async {
      savedOrder = List.of(inv.positionalArguments[0] as List<String>);
    });
  });

  HubPresenter build() => HubPresenter(
        storage: storage,
        fasting: fasting,
        quests: quests,
        treasury: null,
      );

  const defaultOrder = [
    HubCardType.quests,
    HubCardType.treasury,
    HubCardType.weightLog,
    HubCardType.fasting,
    HubCardType.nutrition,
    HubCardType.activity,
    HubCardType.stats,
  ];

  test('no saved order → default priority order', () async {
    final p = build();
    await p.restored;
    expect(p.cardOrder, defaultOrder);
    p.dispose();
  });

  test('reorderCards persists the new order to storage', () async {
    final p = build();
    await p.restored;

    // Move Quests (index 0) below Treasury (to index 2 pre-adjustment).
    p.reorderCards(0, 2);
    await pumpEventQueue();

    expect(p.cardOrder.first, HubCardType.treasury);
    expect(savedOrder, p.cardOrder.map((t) => t.name).toList());
    p.dispose();
  });

  test('saved order is restored on construction (survives restart)', () async {
    final first = build();
    await first.restored;
    first.reorderCards(0, 3); // quests → after weightLog
    await pumpEventQueue();
    final reordered = first.cardOrder;
    first.dispose();

    final second = build();
    await second.restored;
    expect(second.cardOrder, reordered);
    second.dispose();
  });

  test('unknown names are dropped and missing card types appended', () async {
    savedOrder = ['stats', 'ghostCard', 'nutrition', 'bodyMeasurements'];
    final p = build();
    await p.restored;

    expect(p.cardOrder.take(2), [HubCardType.stats, HubCardType.nutrition]);
    // Every non-body card still present exactly once.
    expect(p.cardOrder.toSet(), defaultOrder.toSet());
    expect(p.cardOrder.length, defaultOrder.length);
    p.dispose();
  });

  test('active cards are still promoted above the restored manual order',
      () async {
    savedOrder = defaultOrder.map((t) => t.name).toList();
    when(fasting.isFasting).thenReturn(true);
    final p = build();
    await p.restored;

    expect(p.cardOrder.first, HubCardType.fasting);
    // Remaining cards keep the saved relative order.
    expect(
      p.cardOrder.skip(1).toList(),
      defaultOrder.where((t) => t != HubCardType.fasting).toList(),
    );
    p.dispose();
  });

  test('storage load failure keeps the default order', () async {
    when(storage.loadHubCardOrder()).thenAnswer((_) async {
      throw Exception('disk on fire');
    });
    final p = build();
    await p.restored;
    expect(p.cardOrder, defaultOrder);
    p.dispose();
  });
}

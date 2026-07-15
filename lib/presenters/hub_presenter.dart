import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import 'fasting_presenter.dart';
import 'quest_presenter.dart';
import 'treasury_dashboard_presenter.dart';

enum HubCardType {
  fasting,
  nutrition,
  activity,
  treasury,
  quests,
  stats,
  weightLog,
  bodyMeasurements,
}

class HubPresenter extends ChangeNotifier {
  HubPresenter({
    required StorageService storage,
    required FastingPresenter fasting,
    required QuestPresenter quests,
    required TreasuryDashboardPresenter? treasury,
  })  : _storage = storage,
        _fasting = fasting,
        _quests = quests,
        _treasury = treasury {
    fasting.addListener(_onSourceChanged);
    quests.addListener(_onSourceChanged);
    treasury?.addListener(_onSourceChanged);
    _recompute();
    _restored = _restoreSavedOrder();
  }

  final StorageService _storage;
  final FastingPresenter _fasting;
  final QuestPresenter _quests;
  final TreasuryDashboardPresenter? _treasury;

  late final Future<void> _restored;

  /// Completes once the persisted card order (if any) has been applied.
  /// Exposed for tests; the UI just reacts to the notify.
  @visibleForTesting
  Future<void> get restored => _restored;

  // Body is folded into the Weight slot (rendered as a 2-up tile), so it is not
  // a standalone card in the order. Stats/Character is surfaced (de-prioritised).
  List<HubCardType> _cardOrder = HubCardType.values
      .where((t) => t != HubCardType.bodyMeasurements)
      .toList();
  List<HubCardType>? _manualOrder;
  bool _pendingRecompute = false;

  List<HubCardType> get cardOrder => _cardOrder;

  /// Called by the drag-to-reorder list. Persists the user's preferred order
  /// and uses it as the base for future auto-recomputes.
  void reorderCards(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = List<HubCardType>.from(_cardOrder);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _cardOrder = list;
    _manualOrder = list;
    unawaited(_storage.saveHubCardOrder(list.map((t) => t.name).toList()));
    notifyListeners();
  }

  /// Load the order saved by [reorderCards] and use it as the manual base.
  /// Unknown names (removed card types) are dropped; card types added after
  /// the order was saved are appended in declaration order, so a stale saved
  /// list degrades gracefully instead of hiding cards.
  Future<void> _restoreSavedOrder() async {
    final List<String> names;
    try {
      names = await _storage.loadHubCardOrder();
    } catch (_) {
      return; // storage hiccup — keep the default order
    }
    if (names.isEmpty) return;

    final byName = {for (final t in HubCardType.values) t.name: t};
    final restored = <HubCardType>[];
    for (final name in names) {
      final type = byName[name];
      if (type == null ||
          type == HubCardType.bodyMeasurements ||
          restored.contains(type)) {
        continue;
      }
      restored.add(type);
    }
    if (restored.isEmpty) return;
    for (final type in HubCardType.values) {
      if (type == HubCardType.bodyMeasurements) continue;
      if (!restored.contains(type)) restored.add(type);
    }

    _manualOrder = restored;
    _recompute();
  }

  void _onSourceChanged() {
    if (_pendingRecompute) return;
    _pendingRecompute = true;
    Future.microtask(() {
      _pendingRecompute = false;
      _recompute();
    });
  }

  void _recompute() {
    final active = <HubCardType>[];
    if (_fasting.isFasting) active.add(HubCardType.fasting);
    if (_quests.hasUrgentQuest) active.add(HubCardType.quests);
    if (_treasury?.hasBillImminent == true) {
      active.add(HubCardType.treasury);
    }

    // Hero + Quests + Finance lead; preserved/secondary features sit lower.
    // Body is folded into the Weight slot; Stats/Character is de-prioritised.
    final base = _manualOrder ??
        const [
          HubCardType.quests,
          HubCardType.treasury,
          HubCardType.weightLog,
          HubCardType.fasting,
          HubCardType.nutrition,
          HubCardType.activity,
          HubCardType.stats,
        ];

    final newOrder = [
      ...active,
      ...base.where((t) => !active.contains(t)),
    ];

    if (!_listEquals(newOrder, _cardOrder)) {
      _cardOrder = newOrder;
      notifyListeners();
    }
  }

  bool _listEquals(List<HubCardType> a, List<HubCardType> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _fasting.removeListener(_onSourceChanged);
    _quests.removeListener(_onSourceChanged);
    _treasury?.removeListener(_onSourceChanged);
    super.dispose();
  }
}

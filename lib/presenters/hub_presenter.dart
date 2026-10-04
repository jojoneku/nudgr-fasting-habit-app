import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/hub_card_config.dart';
import '../services/storage_service.dart';
import '../utils/safe_notifier.dart';
import 'activity_presenter.dart';
import 'fasting_presenter.dart';
import 'nutrition_presenter.dart';
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

class HubPresenter extends ChangeNotifier with SafeNotifier {
  HubPresenter({
    required StorageService storage,
    required FastingPresenter fasting,
    required QuestPresenter quests,
    required TreasuryDashboardPresenter? treasury,
    NutritionPresenter? nutrition,
    ActivityPresenter? activity,
  })  : _storage = storage,
        _fasting = fasting,
        _quests = quests,
        _treasury = treasury,
        _nutrition = nutrition,
        _activity = activity {
    fasting.addListener(_onSourceChanged);
    quests.addListener(_onSourceChanged);
    treasury?.addListener(_onSourceChanged);
    nutrition?.addListener(_onSourceChanged);
    activity?.addListener(_onSourceChanged);
    _recompute();
    _restored = _restoreSavedState();
  }

  final StorageService _storage;
  final FastingPresenter _fasting;
  final QuestPresenter _quests;
  final TreasuryDashboardPresenter? _treasury;
  final NutritionPresenter? _nutrition;
  final ActivityPresenter? _activity;

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

  bool _isSmartSortEnabled = true;
  bool get isSmartSortEnabled => _isSmartSortEnabled;

  final Map<HubCardType, HubCardConfig> _cardConfigs = {};

  Map<HubCardType, bool> _lastCompactStates = {};

  List<HubCardType> get cardOrder => _cardOrder;

  /// All cards available for configuration (excluding body measurements which is nested).
  List<HubCardType> get allCards => HubCardType.values
      .where((t) => t != HubCardType.bodyMeasurements)
      .toList();

  HubCardVisibility visibilityOf(HubCardType type) =>
      _cardConfigs[type]?.visibility ?? HubCardVisibility.auto;

  void setCardVisibility(HubCardType type, HubCardVisibility visibility) {
    if (visibilityOf(type) == visibility) return;
    _cardConfigs[type] = HubCardConfig(visibility: visibility);
    _persistConfigs();
    _recompute(forceNotify: true);
  }

  void setSmartSortEnabled(bool enabled) {
    if (_isSmartSortEnabled == enabled) return;
    _isSmartSortEnabled = enabled;
    unawaited(_storage.saveHubSmartSort(enabled));
    _recompute(forceNotify: true);
  }

  void resetToDefaultLayout() {
    _cardConfigs.clear();
    _isSmartSortEnabled = true;
    _manualOrder = null;
    unawaited(_storage.saveHubCardOrder(const []));
    unawaited(_storage.saveHubSmartSort(true));
    unawaited(_storage.saveHubCardConfigs(const {}));
    _recompute(forceNotify: true);
  }

  /// Whether a card should render in its compact (1-row glance) form.
  bool isCompact(HubCardType type) {
    final vis = visibilityOf(type);
    if (vis == HubCardVisibility.compact) return true;
    if (vis == HubCardVisibility.expanded) return false;

    // Auto adaptation based on live activity state:
    switch (type) {
      case HubCardType.fasting:
        return !_fasting.isFasting;
      case HubCardType.nutrition:
        final cals = _nutrition?.todayCalories ?? 0;
        return cals == 0;
      case HubCardType.treasury:
        final t = _treasury;
        if (t == null) return false;
        if (t.hasBillImminent) return false;
        return t.accounts.isEmpty || t.upcomingBills.isEmpty;
      case HubCardType.quests:
        return !_quests.hasUrgentQuest;
      case HubCardType.activity:
        final steps = _activity?.todaySteps ?? 0;
        return steps == 0;
      case HubCardType.stats:
        return true;
      case HubCardType.weightLog:
      case HubCardType.bodyMeasurements:
        return false;
    }
  }

  /// Called by the drag-to-reorder list. Persists the user's preferred order
  /// and uses it as the base for future auto-recomputes.
  void reorderCards(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = List<HubCardType>.from(_cardOrder);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _cardOrder = list;

    final manual = List<HubCardType>.from(list);
    for (final t in allCards) {
      if (!manual.contains(t)) manual.add(t);
    }
    _manualOrder = manual;
    unawaited(_storage.saveHubCardOrder(manual.map((t) => t.name).toList()));
    safeNotify();
  }

  void _persistConfigs() {
    final serialized = <String, String>{};
    for (final entry in _cardConfigs.entries) {
      serialized[entry.key.name] = entry.value.visibility.name;
    }
    unawaited(_storage.saveHubCardConfigs(serialized));
  }

  /// Load the order and configuration saved from storage.
  Future<void> _restoreSavedState() async {
    try {
      _isSmartSortEnabled = await _storage.loadHubSmartSort();
    } catch (_) {}

    try {
      final configs = await _storage.loadHubCardConfigs();
      for (final entry in configs.entries) {
        final type =
            HubCardType.values.where((t) => t.name == entry.key).firstOrNull;
        if (type != null) {
          _cardConfigs[type] = HubCardConfig(
            visibility: HubCardVisibility.fromString(entry.value),
          );
        }
      }
    } catch (_) {}

    final List<String> names;
    try {
      names = await _storage.loadHubCardOrder();
    } catch (_) {
      return; // storage hiccup — keep the default order
    }
    if (names.isNotEmpty) {
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
      if (restored.isNotEmpty) {
        for (final type in HubCardType.values) {
          if (type == HubCardType.bodyMeasurements) continue;
          if (!restored.contains(type)) restored.add(type);
        }
        _manualOrder = restored;
      }
    }

    _recompute(forceNotify: true);
  }

  void _onSourceChanged() {
    if (_pendingRecompute || isDisposed) return;
    _pendingRecompute = true;
    Future.microtask(() {
      _pendingRecompute = false;
      if (!isDisposed) _recompute();
    });
  }

  void _recompute({bool forceNotify = false}) {
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

    List<HubCardType> ordered;
    if (_isSmartSortEnabled) {
      final active = <HubCardType>[];
      if (_fasting.isFasting) active.add(HubCardType.fasting);
      if (_quests.hasUrgentQuest) active.add(HubCardType.quests);
      if (_treasury?.hasBillImminent == true) {
        active.add(HubCardType.treasury);
      }
      ordered = [
        ...active,
        ...base.where((t) => !active.contains(t)),
      ];
    } else {
      ordered = List<HubCardType>.from(base);
    }

    // Filter out hidden cards
    final newOrder = ordered
        .where((t) => visibilityOf(t) != HubCardVisibility.hidden)
        .toList();

    final currentCompactStates = {
      for (final type in HubCardType.values) type: isCompact(type),
    };

    final orderChanged = !_listEquals(newOrder, _cardOrder);
    final compactChanged =
        !_mapEquals(_lastCompactStates, currentCompactStates);

    if (forceNotify || orderChanged || compactChanged) {
      _cardOrder = newOrder;
      _lastCompactStates = currentCompactStates;
      safeNotify();
    }
  }

  bool _mapEquals(Map<HubCardType, bool> a, Map<HubCardType, bool> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
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
    _nutrition?.removeListener(_onSourceChanged);
    _activity?.removeListener(_onSourceChanged);
    super.dispose();
  }
}

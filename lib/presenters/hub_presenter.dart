import 'dart:async';
import 'package:flutter/foundation.dart';
import 'fasting_presenter.dart';
import 'quest_presenter.dart';
import 'treasury_dashboard_presenter.dart';

enum HubCardType { fasting, nutrition, activity, treasury, quests, stats }

class HubPresenter extends ChangeNotifier {
  HubPresenter({
    required FastingPresenter fasting,
    required QuestPresenter quests,
    required TreasuryDashboardPresenter? treasury,
  })  : _fasting = fasting,
        _quests = quests,
        _treasury = treasury {
    fasting.addListener(_onSourceChanged);
    quests.addListener(_onSourceChanged);
    treasury?.addListener(_onSourceChanged);
    _recompute();
  }

  final FastingPresenter _fasting;
  final QuestPresenter _quests;
  final TreasuryDashboardPresenter? _treasury;

  List<HubCardType> _cardOrder = HubCardType.values.toList();
  bool _pendingRecompute = false;

  List<HubCardType> get cardOrder => _cardOrder;

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

    const defaultOrder = [
      HubCardType.nutrition,
      HubCardType.activity,
      HubCardType.treasury,
      HubCardType.quests,
      HubCardType.fasting,
      HubCardType.stats,
    ];

    final newOrder = [
      ...active,
      ...defaultOrder.where((t) => !active.contains(t)),
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

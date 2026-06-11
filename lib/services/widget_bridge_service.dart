import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nutrition_goals.dart' show MeasurementUnit;
import '../models/widget/widget_snapshot.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/quest_presenter.dart';
import '../utils/finance_format.dart';
import 'storage_service.dart';

/// Route a widget tap maps to inside the app (deep-link target).
enum WidgetRoute { fasting, foodLog, expenseAdd, weightLog, quests }

/// Bridges app state → native Android home-screen widgets.
///
/// The app is the single writer of [WidgetSnapshot]: this service listens to the
/// core presenters and pushes a denormalized snapshot into `home_widget`'s own
/// (unscoped) prefs whenever they change. Widgets render from that snapshot and
/// never read the `u/$userId/`-scoped app store. See `docs/android_widgets_spec.md`.
///
/// Inline widget actions (start/end fast, complete quest) are handled safely: the
/// background tap only records a tap-time token + optimistically updates the
/// snapshot (no RPG state touched), and [drainPendingActions] applies them through
/// the real presenters on next foreground.
class WidgetBridgeService {
  WidgetBridgeService({
    required this.storage,
    required this.fasting,
    required this.ledger,
    required this.quests,
    this.nutrition,
  });

  final StorageService storage;
  final FastingPresenter fasting;
  final LedgerPresenter ledger;
  final QuestPresenter quests;
  final NutritionPresenter? nutrition;

  /// Fully-qualified native provider class names. Keep in sync with the
  /// `<receiver>` entries in AndroidManifest.xml.
  static const List<String> _providers = [
    'com.nudgr.app.FastingWidgetProvider',
    'com.nudgr.app.FoodWidgetProvider',
    'com.nudgr.app.ExpenseWidgetProvider',
    'com.nudgr.app.WeightWidgetProvider',
    'com.nudgr.app.QuestWidgetProvider',
  ];

  Timer? _debounce;
  bool _attached = false;
  Map<String, Object?>? _lastPushed;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void attach() {
    if (_attached) return;
    _attached = true;
    fasting.addListener(_schedulePush);
    ledger.addListener(_schedulePush);
    quests.addListener(_schedulePush);
    nutrition?.addListener(_schedulePush);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _debounce?.cancel();
    fasting.removeListener(_schedulePush);
    ledger.removeListener(_schedulePush);
    quests.removeListener(_schedulePush);
    nutrition?.removeListener(_schedulePush);
  }

  void _schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), pushSnapshot);
  }

  // ── Snapshot push ────────────────────────────────────────────────────────────

  /// Builds the current snapshot and pushes it to every native provider.
  ///
  /// Skips the write when nothing changed since the last push: the fasting
  /// ticker notifies every second while a fast/eating window is live, and
  /// re-pushing an identical snapshot would spam 20+ channel writes plus four
  /// provider broadcasts each second (elapsed time ticks natively via the
  /// widget Chronometer, so it is not part of the snapshot).
  Future<void> pushSnapshot() async {
    final data = _build().toWidgetData();
    if (_lastPushed != null && mapEquals(_lastPushed, data)) return;
    await _write(data);
  }

  /// Clears the snapshot on sign-out so a second account on a shared device never
  /// sees the first user's data. ([[project_signout_wipes_local]])
  Future<void> clearForSignOut() async {
    await storage.saveWidgetLastUserId(null);
    await storage.saveWidgetPendingActions([]);
    await _write(WidgetSnapshot.empty().toWidgetData());
  }

  Future<void> _write(Map<String, Object?> data) async {
    try {
      for (final entry in data.entries) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
      for (final provider in _providers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: provider);
      }
      _lastPushed = data;
    } catch (e) {
      // Leave _lastPushed unset so the next notify retries the full write.
      _lastPushed = null;
      debugPrint('WidgetBridgeService: push failed: $e');
    }
  }

  WidgetSnapshot _build() {
    // Fasting
    final isFasting = fasting.isFasting;
    final start = fasting.startTime;
    final hasFastClock = isFasting && start != null;
    final startMillis = hasFastClock ? start.millisecondsSinceEpoch : 0;
    final targetMillis = hasFastClock
        ? start
            .add(Duration(hours: fasting.fastingGoalHours))
            .millisecondsSinceEpoch
        : 0;

    // Expense (current selected month + today)
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayOutflow = ledger.dailyOutflowMap[todayKey] ?? 0.0;

    // Quests
    final done = quests.todayCompletedQuests.length;
    final total = done +
        quests.todayActiveQuests.length +
        quests.todayOverdueQuests.length;
    final next = quests.nextUrgentQuest ??
        (quests.todayActiveQuests.isNotEmpty
            ? quests.todayActiveQuests.first
            : null);

    return WidgetSnapshot(
      signedIn: true,
      snapshotDate: todayKey,
      isFasting: isFasting,
      fastStartMillis: startMillis,
      targetMillis: targetMillis,
      fastingGoalHours: fasting.fastingGoalHours,
      currentStreak: fasting.currentStreak,
      fastPhaseLabel: fasting.currentPhase.label,
      todayCalories: nutrition?.todayCalories ?? 0,
      calorieGoal: nutrition?.effectiveGoal ?? 0,
      proteinGrams: (nutrition?.todayProtein ?? 0).round(),
      proteinGoal: nutrition?.proteinGoal ?? -1,
      monthOutflowLabel: formatPesoCompact(ledger.filteredMonthOutflow),
      todayOutflowLabel: formatPeso(todayOutflow),
      latestWeightLabel: _weightLabel(),
      weightDeltaLabel: _weightDeltaLabel(),
      questsDoneToday: done,
      questsTotalToday: total,
      nextQuestLabel: next?.title ?? '',
      nextQuestId: next?.id ?? -1,
      hasUrgentQuest: quests.hasUrgentQuest,
    );
  }

  String _weightLabel() {
    final w = nutrition?.latestWeight;
    if (w == null) return '';
    final imperial = nutrition!.measurementUnit == MeasurementUnit.imperial;
    final value = imperial ? w.weightKg * 2.20462 : w.weightKg;
    return '${value.toStringAsFixed(1)} ${imperial ? 'lb' : 'kg'}';
  }

  String _weightDeltaLabel() {
    final d = nutrition?.weightDelta;
    if (d == null || d == 0) return '';
    final imperial = nutrition!.measurementUnit == MeasurementUnit.imperial;
    final value = imperial ? d * 2.20462 : d;
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)} ${imperial ? 'lb' : 'kg'}';
  }

  // ── Deep-link routing ────────────────────────────────────────────────────────

  /// Maps a launch/click Uri (e.g. `nudgr://food`) to a [WidgetRoute].
  /// Returns null for action Uris (handled by [onInteractiveAction]) or unknown
  /// hosts.
  static WidgetRoute? parseLaunchUri(Uri? uri) {
    if (uri == null) return null;
    switch (uri.host) {
      case 'fasting':
        return WidgetRoute.fasting;
      case 'food':
        return WidgetRoute.foodLog;
      case 'expense':
        return WidgetRoute.expenseAdd;
      case 'weight':
        return WidgetRoute.weightLog;
      case 'quests':
        return WidgetRoute.quests;
      default:
        return null;
    }
  }

  // ── Inline actions (queue + drain) ─────────────────────────────────────────

  /// Applies any queued widget-tap actions through the real presenters, then
  /// pushes an authoritative snapshot. Called on app foreground.
  ///
  /// Actions are applied on app-open (not at tap time); for `startfast` the tap
  /// timestamp is honored so the fast clock reflects when the user actually
  /// tapped. `stopfast`/`completequest` award XP/HP via the presenters here —
  /// never in the background isolate.
  Future<void> drainPendingActions() async {
    final actions = await storage.loadWidgetPendingActions();
    if (actions.isNotEmpty) {
      // Clear first so a crash mid-drain can't double-apply.
      await storage.saveWidgetPendingActions([]);
      for (final token in actions) {
        final parts = token.split('|');
        final action = parts.isNotEmpty ? parts[0] : '';
        final ts = parts.length > 1 ? int.tryParse(parts[1]) : null;
        try {
          switch (action) {
            case 'startfast':
              if (!fasting.isFasting) {
                await fasting.startFast();
                if (ts != null) {
                  await fasting
                      .rebaseStartTime(DateTime.fromMillisecondsSinceEpoch(ts));
                }
              }
              break;
            case 'stopfast':
              if (fasting.isFasting) await fasting.stopFast();
              break;
            case 'completequest':
              final id = parts.length > 2 ? int.tryParse(parts[2]) : null;
              if (id != null) await quests.completeQuest(id);
              break;
          }
        } catch (e) {
          debugPrint('WidgetBridgeService: drain "$action" failed: $e');
        }
      }
    }
    // Always refresh the widgets — this is also the authoritative initial push
    // on sign-in and the refresh on every app foreground.
    await pushSnapshot();
  }

  /// Background isolate entry — runs when a widget action button is tapped.
  /// MUST stay lightweight and never touch RPG state: it only records a
  /// tap-time token and optimistically updates the snapshot so the widget feels
  /// instant. The authoritative mutation happens in [drainPendingActions].
  @pragma('vm:entry-point')
  static Future<void> onInteractiveAction(Uri? uri) async {
    if (uri == null) return;
    final action = uri.host; // hosts are lower-cased by Uri
    final id = uri.queryParameters['id'];
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final prefs = await SharedPreferences.getInstance();
      final queue =
          prefs.getStringList(StorageService.kWidgetPendingActions) ?? [];
      queue.add(id == null ? '$action|$now' : '$action|$now|$id');
      await prefs.setStringList(StorageService.kWidgetPendingActions, queue);

      // Optimistic snapshot so the fasting widget responds immediately.
      // Numbers go as Strings to match WidgetSnapshot.toWidgetData (see note there).
      if (action == 'startfast') {
        await HomeWidget.saveWidgetData('w_is_fasting', true);
        await HomeWidget.saveWidgetData('w_fast_start_millis', '$now');
      } else if (action == 'stopfast') {
        await HomeWidget.saveWidgetData('w_is_fasting', false);
        await HomeWidget.saveWidgetData('w_fast_start_millis', '0');
      }
      await HomeWidget.updateWidget(
          qualifiedAndroidName: 'com.nudgr.app.FastingWidgetProvider');
    } catch (e) {
      debugPrint('WidgetBridgeService.onInteractiveAction failed: $e');
    }
  }
}

import 'package:flutter/foundation.dart';

import '../models/meal_slot.dart';
import '../models/quest.dart';
import '../models/tdee_profile.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'auth_presenter.dart';
import 'fasting_presenter.dart';
import 'nutrition_presenter.dart';
import 'quest_presenter.dart';

/// Drives the first-run "Awakening" onboarding wizard. Holds the step index and
/// a draft profile, exposes a [previewProfile] whose derived numbers come purely
/// from [TdeeProfile] getters (no new math), and commits by delegating to the
/// existing nutrition / fasting / quest presenters. Constructor injection only.
///
/// Spec: openspec/changes/redesign-onboarding-awakening/specs/onboarding/spec.md
class OnboardingPresenter extends ChangeNotifier {
  OnboardingPresenter({
    required StorageService storage,
    required NutritionPresenter nutrition,
    required FastingPresenter fasting,
    required QuestPresenter quests,
    required NotificationService notifications,
    required AuthPresenter auth,
  })  : _storage = storage,
        _nutrition = nutrition,
        _fasting = fasting,
        _quests = quests,
        _notifications = notifications,
        _auth = auth {
    // Re-check for a synced cloud profile when nutrition state changes — the
    // pull completes asynchronously during/after the sign-in step.
    _nutrition.addListener(_onDependencyChanged);
    _auth.addListener(_onDependencyChanged);
  }

  final StorageService _storage;
  final NutritionPresenter _nutrition;
  final FastingPresenter _fasting;
  final QuestPresenter _quests;
  final NotificationService _notifications;
  final AuthPresenter _auth;

  static const int lastStep = 8;

  int _step = 0;
  int get step => _step;

  // ── Draft (mirrors TdeeSetupScreen state; commit reuses existing math) ───────
  double? _weightKg;
  double? _heightCm;
  int? _ageYears;
  String _sex = 'male';
  ActivityLevel _activityLevel = ActivityLevel.moderatelyActive;
  String _goal = 'maintain'; // 'cut' | 'maintain' | 'bulk' | 'recomp'
  int _protocolHours = 16; // Warrior Mode 16:8

  double? get weightKg => _weightKg;
  double? get heightCm => _heightCm;
  int? get ageYears => _ageYears;
  String get sex => _sex;
  ActivityLevel get activityLevel => _activityLevel;
  String get goal => _goal;
  int get protocolHours => _protocolHours;

  // ── Navigation ───────────────────────────────────────────────────────────────
  void next() {
    if (_step < lastStep) {
      _step++;
      notifyListeners();
    }
  }

  void back() {
    if (_step > 0) {
      _step--;
      notifyListeners();
    }
  }

  void goToStep(int step) {
    _step = step.clamp(0, lastStep);
    notifyListeners();
  }

  // ── Draft mutations ────────────────────────────────────────────────────────
  void setBody(
      {double? weightKg, double? heightCm, int? ageYears, String? sex}) {
    if (weightKg != null) _weightKg = weightKg;
    if (heightCm != null) _heightCm = heightCm;
    if (ageYears != null) _ageYears = ageYears;
    if (sex != null) _sex = sex;
    notifyListeners();
  }

  void setActivity(ActivityLevel level) {
    _activityLevel = level;
    notifyListeners();
  }

  void setGoal(String goal) {
    _goal = goal;
    notifyListeners();
  }

  void setProtocol(int hours) {
    _protocolHours = hours;
    notifyListeners();
  }

  /// Prefills the draft from an existing saved profile (used by "Replay the
  /// Awakening" so the flow opens populated).
  void prefillFromSavedProfile() {
    final p = _nutrition.tdeeProfile;
    if (p == null) return;
    _weightKg = p.weightKg;
    _heightCm = p.heightCm;
    _ageYears = p.ageYears;
    _sex = p.sex;
    _activityLevel = p.activityLevel;
    _goal = p.goal;
    _protocolHours = _fasting.fastingGoalHours;
    notifyListeners();
  }

  /// A draft [TdeeProfile] once body basics are valid; null otherwise. All
  /// numbers shown in the Status Window are read from this object's getters.
  /// [calorieAdjustment] is left null so the model's per-goal default applies.
  TdeeProfile? get previewProfile {
    final w = _weightKg;
    final h = _heightCm;
    final a = _ageYears;
    if (w == null || h == null || a == null) return null;
    return TdeeProfile(
      weightKg: w,
      heightCm: h,
      ageYears: a,
      sex: _sex,
      activityLevel: _activityLevel,
      goal: _goal,
    );
  }

  bool get canRevealStats => previewProfile != null;

  // ── Identity / auth passthrough (keeps the flow depending only on this) ──────
  bool get isSignedIn => _auth.isSignedIn;
  bool get authLoading => _auth.isLoading;
  String? get authError => _auth.error;
  void clearAuthError() => _auth.clearError();
  Future<void> signInWithGoogle() => _auth.signInWithGoogle();

  // ── Welcome-back (existing cloud data) ───────────────────────────────────────
  bool get cloudProfileFound =>
      _auth.isSignedIn && _nutrition.tdeeProfile != null;

  /// Accepts the welcome-back offer: marks onboarding complete WITHOUT
  /// overwriting the pulled profile and WITHOUT seeding the starter quest.
  Future<void> fastForwardFromCloud() async {
    await _storage.saveOnboardingComplete(true);
    notifyListeners();
  }

  // ── Notifications (non-blocking) ─────────────────────────────────────────────
  Future<void> requestNotifications() async {
    try {
      await _notifications.requestPermissions();
    } catch (_) {
      // Denial / platform error must never block the flow.
    }
  }

  // ── Commit ───────────────────────────────────────────────────────────────────
  /// Skips the flow: keeps today's defaults (no profile written), marks the gate
  /// complete, seeds nothing. Idempotent.
  Future<void> skip() async {
    await _storage.saveOnboardingComplete(true);
  }

  /// Completes the flow: persists the profile, macro-filled goals, and the
  /// chosen fasting protocol, then marks the gate complete. The starter quest is
  /// seeded ONLY on the genuine first completion (flag false → true).
  Future<void> complete() async {
    final profile = previewProfile;
    if (profile != null) {
      await _nutrition.saveTdeeProfile(profile);
      await _nutrition.updateGoals(
        _nutrition.goals.copyWith(
          mode: TrackingMode.standard,
          proteinGrams: profile.suggestedProteinG.toDouble(),
          carbsGrams: profile.suggestedCarbsG.toDouble(),
          fatGrams: profile.suggestedFatG.toDouble(),
        ),
      );
    }
    await _fasting.updateFastingGoal(_protocolHours);

    final alreadyComplete = await _storage.loadOnboardingComplete();
    if (!alreadyComplete) {
      await _quests.addQuest(_starterQuest());
    }
    await _storage.saveOnboardingComplete(true);
  }

  Quest _starterQuest() => Quest(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'Begin your first fast',
        hour: 20,
        minute: 0,
        days: List<bool>.filled(7, true),
      );

  void _onDependencyChanged() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _nutrition.removeListener(_onDependencyChanged);
    _auth.removeListener(_onDependencyChanged);
    super.dispose();
  }
}

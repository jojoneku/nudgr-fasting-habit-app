import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/meal_slot.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/quest.dart';
import 'package:intermittent_fasting/models/tdee_profile.dart';
import 'package:intermittent_fasting/presenters/auth_presenter.dart';
import 'package:intermittent_fasting/presenters/fasting_presenter.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/presenters/onboarding_presenter.dart';
import 'package:intermittent_fasting/presenters/quest_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/notification_service.dart';

// Lightweight hand fakes — the shared generated mock file can't be regenerated
// with the current toolchain without breaking other suites, so the onboarding
// test stands alone: a real LocalStorageService plus fakes that record calls.

class _FakeNutrition extends ChangeNotifier implements NutritionPresenter {
  NutritionGoals _goals = NutritionGoals.initial();
  TdeeProfile? _tdee;
  TdeeProfile? savedProfile;
  NutritionGoals? savedGoals;

  void setCloudProfile(TdeeProfile? p) {
    _tdee = p;
    notifyListeners();
  }

  @override
  NutritionGoals get goals => _goals;
  @override
  TdeeProfile? get tdeeProfile => _tdee;
  @override
  Future<void> saveTdeeProfile(TdeeProfile profile) async {
    savedProfile = profile;
    _tdee = profile;
  }

  @override
  Future<void> updateGoals(NutritionGoals newGoals) async {
    savedGoals = newGoals;
    _goals = newGoals;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuth extends ChangeNotifier implements AuthPresenter {
  bool signedIn = false;

  @override
  bool get isSignedIn => signedIn;
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  void clearError() {}
  @override
  Future<void> signInWithGoogle() async {
    signedIn = true;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeFasting extends ChangeNotifier implements FastingPresenter {
  @override
  int fastingGoalHours = 16;
  int? committedGoal;

  @override
  Future<void> updateFastingGoal(int hours) async {
    committedGoal = hours;
    fastingGoalHours = hours;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeQuests extends ChangeNotifier implements QuestPresenter {
  final List<Quest> added = [];

  @override
  Future<void> addQuest(Quest quest) async => added.add(quest);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeNotifications implements NotificationService {
  bool throwOnRequest = false;
  int requestCount = 0;

  @override
  Future<bool> requestPermissions() async {
    requestCount++;
    if (throwOnRequest) throw Exception('denied');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late LocalStorageService storage;
  late _FakeNutrition nutrition;
  late _FakeFasting fasting;
  late _FakeQuests quests;
  late _FakeNotifications notifications;
  late _FakeAuth auth;
  late OnboardingPresenter p;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    nutrition = _FakeNutrition();
    fasting = _FakeFasting();
    quests = _FakeQuests();
    notifications = _FakeNotifications();
    auth = _FakeAuth();
    p = OnboardingPresenter(
      storage: storage,
      nutrition: nutrition,
      fasting: fasting,
      quests: quests,
      notifications: notifications,
      auth: auth,
    );
  });

  tearDown(() => p.dispose());

  void enterValidBody() {
    p.setBody(weightKg: 74.6, heightCm: 176, ageYears: 29, sex: 'male');
    p.setActivity(ActivityLevel.moderatelyActive);
    p.setGoal('cut');
  }

  group('navigation', () {
    test('next / back clamp at bounds', () {
      expect(p.step, 0);
      p.back();
      expect(p.step, 0, reason: 'cannot go below 0');
      for (var i = 0; i < 20; i++) {
        p.next();
      }
      expect(p.step, OnboardingPresenter.lastStep, reason: 'clamps at last');
      p.back();
      expect(p.step, OnboardingPresenter.lastStep - 1);
    });

    test('goToStep clamps into range', () {
      p.goToStep(99);
      expect(p.step, OnboardingPresenter.lastStep);
      p.goToStep(-5);
      expect(p.step, 0);
    });
  });

  group('previewProfile', () {
    test('is null until body basics are entered', () {
      expect(p.previewProfile, isNull);
      expect(p.canRevealStats, false);
    });

    test('mirrors TdeeProfile getters exactly (no new math)', () {
      enterValidBody();
      final preview = p.previewProfile!;
      final expected = const TdeeProfile(
        weightKg: 74.6,
        heightCm: 176,
        ageYears: 29,
        sex: 'male',
        activityLevel: ActivityLevel.moderatelyActive,
        goal: 'cut',
      );
      expect(preview.bmr, expected.bmr);
      expect(preview.tdee, expected.tdee);
      expect(preview.targetCalories, expected.targetCalories);
      expect(preview.suggestedProteinG, expected.suggestedProteinG);
      expect(preview.suggestedCarbsG, expected.suggestedCarbsG);
      expect(preview.suggestedFatG, expected.suggestedFatG);
      expect(p.canRevealStats, true);
    });
  });

  group('complete', () {
    test('commits profile, standard-mode macro goals, protocol, seeds quest',
        () async {
      enterValidBody();
      p.setProtocol(18);

      await p.complete();

      expect(nutrition.savedProfile, isNotNull);
      expect(nutrition.savedGoals!.mode, TrackingMode.standard);
      expect(nutrition.savedGoals!.proteinGrams, isNotNull);
      expect(fasting.committedGoal, 18);
      expect(quests.added.length, 1);
      expect(await storage.loadOnboardingComplete(), true);
    });

    test('does NOT re-seed the starter quest on replay (already complete)',
        () async {
      await storage.saveOnboardingComplete(true);
      enterValidBody();

      await p.complete();

      expect(quests.added, isEmpty);
      expect(await storage.loadOnboardingComplete(), true);
    });
  });

  group('skip', () {
    test('marks complete, keeps defaults, seeds nothing', () async {
      await p.skip();

      expect(await storage.loadOnboardingComplete(), true);
      expect(nutrition.savedProfile, isNull);
      expect(nutrition.savedGoals, isNull);
      expect(quests.added, isEmpty);
    });
  });

  group('welcome-back', () {
    test('cloudProfileFound is true only when signed in with a pulled profile',
        () {
      expect(p.cloudProfileFound, false);
      auth.signedIn = true;
      expect(p.cloudProfileFound, false, reason: 'still no profile');
      nutrition.setCloudProfile(const TdeeProfile(
        weightKg: 70,
        heightCm: 175,
        ageYears: 30,
        sex: 'male',
        activityLevel: ActivityLevel.sedentary,
        goal: 'maintain',
      ));
      expect(p.cloudProfileFound, true);
    });

    test('fastForwardFromCloud marks complete without touching the profile',
        () async {
      await p.fastForwardFromCloud();

      expect(await storage.loadOnboardingComplete(), true);
      expect(nutrition.savedProfile, isNull);
      expect(quests.added, isEmpty);
    });
  });

  group('prefill (replay)', () {
    test('loads draft from the saved profile and fasting goal', () {
      nutrition.setCloudProfile(const TdeeProfile(
        weightKg: 82,
        heightCm: 180,
        ageYears: 41,
        sex: 'female',
        activityLevel: ActivityLevel.veryActive,
        goal: 'recomp',
      ));
      fasting.fastingGoalHours = 18;

      p.prefillFromSavedProfile();

      expect(p.weightKg, 82);
      expect(p.heightCm, 180);
      expect(p.ageYears, 41);
      expect(p.sex, 'female');
      expect(p.activityLevel, ActivityLevel.veryActive);
      expect(p.goal, 'recomp');
      expect(p.protocolHours, 18);
    });
  });

  group('review edit navigation', () {
    test('advance is a normal next() when not editing', () {
      expect(p.step, 0);
      p.advance();
      expect(p.step, 1);
    });

    test('editStep jumps to the step; the next advance returns to Review', () {
      p.editStep(2);
      expect(p.step, 2);
      p.advance();
      expect(p.step, OnboardingPresenter.reviewStep);
      // Subsequent advances resume stepping forward normally.
      p.advance();
      expect(p.step, OnboardingPresenter.reviewStep + 1);
    });
  });

  group('notifications', () {
    test('requestNotifications never throws on denial/error', () async {
      notifications.throwOnRequest = true;
      await expectLater(p.requestNotifications(), completes);
      expect(notifications.requestCount, 1);
    });
  });
}

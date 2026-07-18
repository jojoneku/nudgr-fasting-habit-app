import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/estimation_source.dart';
import 'package:intermittent_fasting/models/extracted_food_item.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/services/food_photo_store.dart';
import 'package:intermittent_fasting/services/image_compressor.dart';

import '../mocks.mocks.dart';

/// Compressor that skips the platform channel — returns bytes unchanged.
class _PassthroughCompressor extends ImageCompressor {
  const _PassthroughCompressor();
  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async => bytes;
  @override
  Future<Uint8List> makeThumbnail(Uint8List bytes) async => bytes;
}

/// Photo store that records calls instead of touching the filesystem.
class _FakePhotoStore extends FoodPhotoStore {
  int saves = 0;
  final List<String> deleted = [];
  String? lastSavedPath;

  @override
  Future<String> saveThumbnail(Uint8List jpegBytes, String id) async {
    saves++;
    lastSavedPath = 'food_photos/$id.jpg';
    return lastSavedPath!;
  }

  @override
  Future<String?> absolutePath(String relativePath) async => null;

  @override
  Future<void> delete(String relativePath) async => deleted.add(relativePath);
}

PhotoParseResult _okResult() => const PhotoParseResult(
      PhotoParseStatus.ok,
      items: [
        ExtractedFoodItem(
          name: 'Chicken adobo',
          grams: 180,
          hydeDescription: 'Chicken adobo, Filipino braised chicken',
          rawText: 'Chicken adobo',
          estimatedMacros: EstimatedMacros(
            calories: 320,
            proteinG: 28,
            carbsG: 4,
            fatG: 21,
          ),
        ),
      ],
      intent: ParseIntent.itemsList,
    );

void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;
  late MockFastingPresenter mockFasting;
  late MockAiCoachService mockOnDevice;
  late MockAiCoachService mockCloud;
  late _FakePhotoStore photoStore;

  final today = _todayKey();

  NutritionPresenter buildPresenter({bool withCloud = true}) {
    return NutritionPresenter(
      statsPresenter: mockStats,
      fastingPresenter: mockFasting,
      storage: mockStorage,
      foodDb: MockFoodDbService(),
      aiCoach: mockOnDevice,
      cloudAi: withCloud ? mockCloud : null,
      imageCompressor: const _PassthroughCompressor(),
      photoStore: photoStore,
    );
  }

  setUp(() async {
    mockStorage = MockStorageService();
    mockStats = MockStatsPresenter();
    mockFasting = MockFastingPresenter();
    mockOnDevice = MockAiCoachService();
    mockCloud = MockAiCoachService();
    photoStore = _FakePhotoStore();

    when(mockStorage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(mockStorage.loadTodayNutritionLog())
        .thenAnswer((_) async => DailyNutritionLog.empty(today));
    when(mockStorage.loadNutritionGoals())
        .thenAnswer((_) async => NutritionGoals.initial());
    when(mockStorage.loadNutritionHistory()).thenAnswer((_) async => []);
    when(mockStorage.loadTdeeProfile()).thenAnswer((_) async => null);
    when(mockStorage.loadFoodLibrary()).thenAnswer((_) async => []);
    when(mockStorage.loadNutritionStreak()).thenAnswer((_) async => 0);
    when(mockStorage.loadNutritionGoalMetDate()).thenAnswer((_) async => null);
    when(mockStorage.loadLogStreak()).thenAnswer((_) async => 0);
    when(mockStorage.loadLogStreakDate()).thenAnswer((_) async => null);
    when(mockStorage.saveNutritionLog(any)).thenAnswer((_) async {});
    when(mockStorage.saveNutritionGoals(any)).thenAnswer((_) async {});
    when(mockStorage.saveNutritionStreak(any)).thenAnswer((_) async {});
    when(mockStorage.saveNutritionGoalMetDate(any)).thenAnswer((_) async {});
    when(mockStorage.saveLogStreak(any)).thenAnswer((_) async {});
    when(mockStorage.saveLogStreakDate(any)).thenAnswer((_) async {});
    when(mockStorage.loadCalorieGoalCreditedDates())
        .thenAnswer((_) async => <String>{});
    when(mockStorage.loadProteinGoalCreditedDates())
        .thenAnswer((_) async => <String>{});
    when(mockStorage.loadStreakMilestonePaid()).thenAnswer((_) async => 0);
    when(mockStorage.saveCalorieGoalCreditedDates(any))
        .thenAnswer((_) async {});
    when(mockStorage.saveProteinGoalCreditedDates(any))
        .thenAnswer((_) async {});
    when(mockStorage.saveStreakMilestonePaid(any)).thenAnswer((_) async {});
    when(mockStorage.loadPersonalDict()).thenAnswer((_) async => []);
    when(mockStorage.savePersonalDict(any)).thenAnswer((_) async {});
    when(mockStorage.loadFoodFeedback()).thenAnswer((_) async => []);
    when(mockStorage.saveFoodFeedback(any)).thenAnswer((_) async {});
    when(mockStorage.loadChatMessagesRaw(any)).thenAnswer((_) async => []);
    when(mockStorage.saveChatMessages(any, any)).thenAnswer((_) async {});
    when(mockStorage.loadWeightLog()).thenAnswer((_) async => []);
    when(mockStorage.loadBodyMeasurements()).thenAnswer((_) async => []);
    when(mockStorage.loadMeasurementUnit())
        .thenAnswer((_) async => MeasurementUnit.metric);
    when(mockStorage.loadLastRecompXpDate()).thenAnswer((_) async => null);

    when(mockStats.stats).thenReturn(UserStats.initial());
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.modifyHp(any)).thenAnswer((_) async {});
    when(mockStats.awardStat(any)).thenAnswer((_) async {});

    when(mockFasting.isFasting).thenReturn(false);

    when(mockOnDevice.isAvailable).thenReturn(false);
    when(mockOnDevice.downloadProgress).thenReturn(null);

    when(mockCloud.isAvailable).thenReturn(true);
    when(mockCloud.downloadProgress).thenReturn(null);
  });

  group('photo logging (resolve → review → commit)', () {
    test('resolve stages a pending estimate WITHOUT logging', () async {
      when(mockCloud.parseFoodFromImage(any, any, any))
          .thenAnswer((_) async => _okResult());
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));

      // Estimate is staged for review — nothing logged yet.
      expect(presenter.hasPendingChat, isTrue);
      expect(presenter.pendingChatEntries, hasLength(1));
      expect(presenter.chatMessages, isEmpty);
      expect(presenter.todayCalories, 0);
      expect(photoStore.saves, 1); // thumbnail prepared during resolve
      expect(presenter.photoParseError, isNull);
    });

    test('commit logs the reviewed photo estimate with its thumbnail',
        () async {
      when(mockCloud.parseFoodFromImage(any, any, any))
          .thenAnswer((_) async => _okResult());
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));
      await presenter.commitPendingChat();

      expect(presenter.chatMessages, hasLength(1));
      final msg = presenter.chatMessages.first;
      expect(msg.isPhoto, isTrue);
      expect(msg.photoThumbnailPath, photoStore.lastSavedPath);
      expect(msg.foodItems.single.estimationSource, EstimationSource.photoAi);
      expect(presenter.todayCalories, 320);
      expect(presenter.hasPendingChat, isFalse);
    });

    test('discard drops the estimate and deletes the orphan thumbnail',
        () async {
      when(mockCloud.parseFoodFromImage(any, any, any))
          .thenAnswer((_) async => _okResult());
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));
      presenter.discardPendingChat();

      expect(presenter.hasPendingChat, isFalse);
      expect(presenter.chatMessages, isEmpty);
      expect(presenter.todayCalories, 0);
      expect(photoStore.deleted, contains(photoStore.lastSavedPath));
    });

    test('does NOT auto-learn a photo item into the personal dictionary',
        () async {
      // §0.2 — vision estimates are the least-verified input and must never
      // silently poison the personal dictionary.
      when(mockCloud.parseFoodFromImage(any, any, any))
          .thenAnswer((_) async => _okResult());
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));

      verifyNever(mockStorage.savePersonalDict(any));
    });

    test('disposing mid-parse does not throw or commit', () async {
      // §0.4 — the vision call ends in notifyListeners(); dismissing the sheet
      // mid-flight must not touch a disposed notifier.
      when(mockCloud.parseFoodFromImage(any, any, any)).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _okResult();
      });
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      final future =
          presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));
      presenter.dispose();

      await expectLater(future, completes);
      expect(presenter.chatMessages, isEmpty);
    });

    test('surfaces the daily-cap message on a rate-limited response', () async {
      when(mockCloud.parseFoodFromImage(any, any, any)).thenAnswer(
          (_) async => const PhotoParseResult(PhotoParseStatus.rateLimited));
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));

      expect(presenter.photoParseError, contains('limit'));
      expect(presenter.chatMessages, isEmpty);
    });

    test('reports a friendly error when no food is detected', () async {
      when(mockCloud.parseFoodFromImage(any, any, any)).thenAnswer(
          (_) async => const PhotoParseResult(PhotoParseStatus.noFood));
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));

      expect(presenter.photoParseError, isNotNull);
      expect(presenter.chatMessages, isEmpty);
    });

    test('errors out when cloud AI is not configured', () async {
      final presenter = buildPresenter(withCloud: false);
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));

      expect(presenter.photoParseError, contains('Cloud AI'));
      expect(presenter.chatMessages, isEmpty);
    });

    test('only a network error blames the connection', () async {
      when(mockCloud.parseFoodFromImage(any, any, any)).thenAnswer((_) async =>
          const PhotoParseResult(PhotoParseStatus.networkError,
              detail: 'SocketException'));
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));

      expect(presenter.photoParseError, contains('connection'));
      expect(presenter.chatMessages, isEmpty);
    });

    test('a server error does NOT blame the connection and shows the code',
        () async {
      // The regression that shipped: a backend failure (here HTTP 400) was
      // reported as "check your connection". It must not be anymore.
      when(mockCloud.parseFoodFromImage(any, any, any)).thenAnswer((_) async =>
          const PhotoParseResult(PhotoParseStatus.serverError,
              httpStatus: 400, detail: 'unsupported_op'));
      final presenter = buildPresenter();
      await Future.delayed(Duration.zero);

      await presenter.resolvePhotoPreview(Uint8List.fromList([1, 2, 3]));

      expect(presenter.photoParseError, isNotNull);
      expect(presenter.photoParseError, isNot(contains('connection')));
      expect(presenter.photoParseError, contains('400'));
      expect(presenter.chatMessages, isEmpty);
    });
  });
}

String _todayKey() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

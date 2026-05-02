import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/services/health_service.dart';
import 'package:intermittent_fasting/services/notification_service.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/food_db_service.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/presenters/fasting_presenter.dart';
import 'package:intermittent_fasting/presenters/activity_presenter.dart';
import 'package:intermittent_fasting/presenters/quest_presenter.dart';
import 'package:intermittent_fasting/presenters/hub_presenter.dart';
import 'package:intermittent_fasting/presenters/settings_presenter.dart';

@GenerateMocks([
  StorageService,
  HealthService,
  NotificationService,
  AiCoachService,
  FoodDbService,
])
@GenerateNiceMocks([
  MockSpec<StatsPresenter>(),
  MockSpec<FastingPresenter>(),
  MockSpec<ActivityPresenter>(),
  MockSpec<QuestPresenter>(),
  MockSpec<HubPresenter>(),
  MockSpec<SettingsPresenter>(),
])
void main() {}

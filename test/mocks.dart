import 'package:mockito/annotations.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/services/health_service.dart';
import 'package:intermittent_fasting/services/notification_service.dart';
import 'package:intermittent_fasting/services/ai_estimation_service.dart';
import 'package:intermittent_fasting/services/food_db_service.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/presenters/fasting_presenter.dart';
import 'package:intermittent_fasting/presenters/activity_presenter.dart';

@GenerateMocks([
  StorageService,
  HealthService,
  NotificationService,
  AiEstimationService,
  FoodDbService,
  StatsPresenter,
  FastingPresenter,
  ActivityPresenter,
])
void main() {}

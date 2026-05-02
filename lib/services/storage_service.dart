import '../models/activity_goals.dart';
import '../models/activity_log.dart';
import '../models/daily_nutrition_log.dart';
import '../models/fasting_log.dart';
import '../models/food_template.dart';
import '../models/habit_routine.dart';
import '../models/nutrition_goals.dart';
import '../models/quest.dart';
import '../models/quest_achievement.dart';
import '../models/tdee_profile.dart';
import '../models/user_stats.dart';
import '../models/finance/bill.dart';
import '../models/finance/budget.dart';
import '../models/finance/installment.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/monthly_summary.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';
import '../models/personal_food_entry.dart';

abstract class StorageService {
  static const String keyIsFasting = 'isFasting';
  static const String keyStartTime = 'startTime';
  static const String keyEatingStartTime = 'eatingStartTime';
  static const String keyElapsedSeconds = 'elapsedSeconds';
  static const String keyFastingGoalHours = 'fastingGoalHours';
  static const String keyHistory = 'history';
  static const String keyQuests = 'quests';
  static const String keyUserStats = 'userStats';
  static const String keyLastPenaltyCheckDate = 'lastPenaltyCheckDate';
  static const String keyQuestRoutines = 'quest_routines';
  static const String keyQuestAchievements = 'quest_achievements';
  static const String keyQuestPenaltyCheckDate = 'questPenaltyCheckDate';
  static const String keyNutritionLogs = 'nutritionLogs';
  static const String keyNutritionGoals = 'nutritionGoals';
  static const String keyNutritionStreak = 'nutritionStreak';
  static const String keyNutritionGoalMetDate = 'nutritionGoalMetDate';
  static const String keyTdeeProfile = 'tdeeProfile';
  static const String keyFoodLibrary = 'foodLibrary';
  static const String keyLogStreak = 'nutritionLogStreak';
  static const String keyLogStreakDate = 'nutritionLogStreakDate';
  static const String keyActivityLogs = 'activityLogs';
  static const String keyActivityGoals = 'activityGoals';
  static const String keyActivityGoalMetDate = 'activityGoalMetDate';
  static const String keyActivityStreak = 'activityStreak';
  static const String keyPreferredStepsSource = 'preferredStepsSourceId';
  static const String keyChatMessages = 'nutritionChatMessages';
  static const String keyFinancialAccounts = 'finance_accounts';
  static const String keyTransactions = 'finance_transactions';
  static const String keyFinanceCategories = 'finance_categories';
  static const String keyBudgets = 'finance_budgets';
  static const String keyBudgetedExpenses = 'finance_budgeted_expenses';
  static const String keyBills = 'finance_bills';
  static const String keyReceivables = 'finance_receivables';
  static const String keyMonthlySummaries = 'finance_monthly_summaries';
  static const String keyInstallments = 'finance_installments';
  static const String keyPersonalFoodDict = 'personalFoodDict';
  static const String kThemeMode = 'themeMode';

  //  User Stats
  Future<void> saveUserStats(UserStats stats);
  Future<UserStats> loadUserStats();

  //  Fasting State ─
  Future<void> saveState({
    required bool isFasting,
    DateTime? startTime,
    DateTime? eatingStartTime,
    required int elapsedSeconds,
    required int fastingGoalHours,
    required List<FastingLog> history,
    DateTime? lastPenaltyCheckDate,
  });
  Future<Map<String, dynamic>> loadState();

  //  Quests ─
  Future<void> saveQuests(List<Quest> quests);
  Future<List<Quest>> loadQuests();
  Future<void> saveRoutines(List<HabitRoutine> routines);
  Future<List<HabitRoutine>> loadRoutines();
  Future<void> saveAchievements(List<QuestAchievement> achievements);
  Future<List<QuestAchievement>> loadAchievements();
  Future<void> saveQuestPenaltyCheckDate(DateTime date);
  Future<DateTime?> loadQuestPenaltyCheckDate();

  //  Nutrition
  Future<void> saveNutritionLog(DailyNutritionLog log);
  Future<DailyNutritionLog> loadTodayNutritionLog();
  Future<DailyNutritionLog> loadNutritionLogForDate(String dateKey);
  Future<List<DailyNutritionLog>> loadNutritionHistory();
  Future<void> saveNutritionGoals(NutritionGoals goals);
  Future<NutritionGoals> loadNutritionGoals();
  Future<void> saveNutritionStreak(int streak);
  Future<int> loadNutritionStreak();
  Future<void> saveNutritionGoalMetDate(String date);
  Future<String?> loadNutritionGoalMetDate();
  Future<void> saveTdeeProfile(TdeeProfile profile);
  Future<TdeeProfile?> loadTdeeProfile();
  Future<void> saveFoodLibrary(List<FoodTemplate> templates);
  Future<List<FoodTemplate>> loadFoodLibrary();
  Future<void> saveLogStreak(int streak);
  Future<int> loadLogStreak();
  Future<void> saveLogStreakDate(String date);
  Future<String?> loadLogStreakDate();

  // ─ Activity
  Future<void> saveActivityLog(ActivityLog log);
  Future<ActivityLog> loadTodayActivityLog();
  Future<List<ActivityLog>> loadActivityHistory();
  Future<Set<String>> loadActivityLogKeys();
  Future<void> clearActivityHistory();
  Future<void> saveActivityLogs(List<ActivityLog> logs);
  Future<void> saveActivityGoals(ActivityGoals goals);
  Future<ActivityGoals> loadActivityGoals();
  Future<String?> loadPreferredStepsSource();
  Future<void> savePreferredStepsSource(String? sourceId);
  Future<void> saveActivityGoalMetDate(String date);
  Future<String?> loadActivityGoalMetDate();
  Future<void> saveActivityStreak(int streak);
  Future<int> loadActivityStreak();

  //  Chat ─
  Future<void> saveChatMessages(String date, List<dynamic> messages);
  Future<List<Map<String, dynamic>>> loadChatMessagesRaw(String date);

  //  Finance ─
  Future<void> saveAccounts(List<FinancialAccount> accounts);
  Future<List<FinancialAccount>> loadAccounts();
  Future<void> saveTransactions(List<TransactionRecord> transactions);
  Future<List<TransactionRecord>> loadTransactions();
  Future<void> saveFinanceCategories(List<FinanceCategory> categories);
  Future<List<FinanceCategory>> loadFinanceCategories();
  Future<void> saveBudgets(List<Budget> budgets);
  Future<List<Budget>> loadBudgets();
  Future<void> saveBudgetedExpenses(List<BudgetedExpense> expenses);
  Future<List<BudgetedExpense>> loadBudgetedExpenses();
  Future<void> saveBills(List<Bill> bills);
  Future<List<Bill>> loadBills();
  Future<void> saveReceivables(List<Receivable> receivables);
  Future<List<Receivable>> loadReceivables();
  Future<void> saveInstallments(List<Installment> installments);
  Future<List<Installment>> loadInstallments();
  Future<void> saveMonthlySummaries(List<MonthlySummary> summaries);
  Future<List<MonthlySummary>> loadMonthlySummaries();

  //  Personal Food Dictionary
  Future<void> savePersonalDict(List<PersonalFoodEntry> entries);
  Future<List<PersonalFoodEntry>> loadPersonalDict();

  //  Theme
  Future<void> saveThemeMode(String mode);
  Future<String?> loadThemeMode();

  //  Export / Import ─
  Future<String> exportAllData();
  Future<void> importAllData(String jsonString);
}

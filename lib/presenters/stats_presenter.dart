import 'package:flutter/material.dart';
import '../models/user_stats.dart';
import '../services/storage_service.dart';

class StatsPresenter extends ChangeNotifier {
  final StorageService _storageService;
  UserStats _stats = UserStats.initial();
  bool showLevelUpDialog = false;

  StatsPresenter(this._storageService) {
    _init();
  }

  UserStats get stats => _stats;

  Future<void> _init() async {
    await loadStats();
  }

  Future<void> loadStats() async {
    _stats = await _storageService.loadUserStats();
    notifyListeners();
  }

  void dismissLevelUp() {
    showLevelUpDialog = false;
    notifyListeners();
  }

  // --- Getters ---

  int get maxHp => 100 + (_stats.attributes.vit * 10);

  int get nextLevelXp => (_stats.level * _stats.level) * 100;

  String get rank {
    if (_stats.level <= 10) return 'E';
    if (_stats.level <= 20) return 'D';
    if (_stats.level <= 30) return 'C';
    if (_stats.level <= 40) return 'B';
    if (_stats.level <= 50) return 'A';
    return 'S';
  }

  String get jobTitle {
    if (_stats.level < 10) return 'None';
    if (_stats.level < 30) return 'Fasting Novice';
    if (_stats.level < 50) return 'Shadow Faster';
    return 'Shadow Monarch';
  }

  // --- Actions ---

  Future<void> updateName(String newName) async {
    _stats = _stats.copyWith(name: newName);
    notifyListeners();
    await _storageService.saveUserStats(_stats);
  }

  Future<void> addXp(int amount) async {
    // Apply STR bonus to XP gain (e.g., 1% per STR point)
    final bonusMultiplier = 1 + (_stats.attributes.str * 0.01);
    final adjustedXp = (amount * bonusMultiplier).round();

    int newXp = _stats.currentXp + adjustedXp;
    int newLevel = _stats.level;
    int newStatPoints = _stats.statPoints;
    int newHp = _stats.currentHp;

    // Level Up Logic
    int requiredXp = (newLevel * newLevel) * 100;
    while (newXp >= requiredXp) {
      newXp -= requiredXp;
      newLevel++;
      newStatPoints += 3; // 3 points per level
      newHp = 100 + (_stats.attributes.vit * 10); // Full heal on level up
      requiredXp = (newLevel * newLevel) * 100;
      showLevelUpDialog = true;
    }

    _stats = _stats.copyWith(
      currentXp: newXp,
      level: newLevel,
      statPoints: newStatPoints,
      currentHp: newHp,
    );

    notifyListeners();
    await _storageService.saveUserStats(_stats);
  }

  Future<void> modifyHp(int amount) async {
    int newHp = _stats.currentHp + amount;
    if (newHp > maxHp) newHp = maxHp;
    if (newHp < 0) newHp = 0;

    _stats = _stats.copyWith(currentHp: newHp);
    notifyListeners();
    await _storageService.saveUserStats(_stats);
  }

  Future<void> allocatePoint(String stat) async {
    if (_stats.statPoints <= 0) return;

    int str = _stats.attributes.str;
    int vit = _stats.attributes.vit;
    int agi = _stats.attributes.agi;
    int intl = _stats.attributes.intl;
    int sen = _stats.attributes.sen;

    switch (stat.toLowerCase()) {
      case 'str':
        str++;
        break;
      case 'vit':
        vit++;
        break;
      case 'agi':
        agi++;
        break;
      case 'int':
        intl++;
        break;
      case 'sen':
        sen++;
        break;
    }

    _stats = _stats.copyWith(
      statPoints: _stats.statPoints - 1,
      attributes: (str: str, vit: vit, agi: agi, intl: intl, sen: sen),
    );

    // If VIT increased, current HP stays same but max increases (handled by getter)
    // Optionally heal slightly? No, keep it strict.

    notifyListeners();
    await _storageService.saveUserStats(_stats);
  }

  Future<void> incrementStreak() async {
    _stats = _stats.copyWith(streak: _stats.streak + 1);
    notifyListeners();
    await _storageService.saveUserStats(_stats);
  }

  Future<void> resetStreak() async {
    _stats = _stats.copyWith(streak: 0);
    notifyListeners();
    await _storageService.saveUserStats(_stats);
  }

  /// Awards a stat point directly (RPG system reward, not user-allocated).
  Future<void> awardStat(String stat) async {
    int str = _stats.attributes.str;
    int vit = _stats.attributes.vit;
    int agi = _stats.attributes.agi;
    int intl = _stats.attributes.intl;
    int sen = _stats.attributes.sen;

    switch (stat.toLowerCase()) {
      case 'str':
        str++;
        break;
      case 'vit':
        vit++;
        break;
      case 'agi':
        agi++;
        break;
      case 'int':
        intl++;
        break;
      case 'sen':
        sen++;
        break;
      default:
        return;
    }

    _stats = _stats.copyWith(
      attributes: (str: str, vit: vit, agi: agi, intl: intl, sen: sen),
    );
    notifyListeners();
    await _storageService.saveUserStats(_stats);
  }
}

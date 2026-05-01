/// Rule-based exercise text parser.
///
/// Detects common activities from natural language, extracts distance or
/// duration, and estimates calories burned using MET values.
///
/// Calories formula: MET × weight_kg × duration_hours
///
/// Distance-based activities derive duration from assumed average speed.
class ExerciseNlpParser {
  ExerciseNlpParser._();

  // ── Detection keywords ────────────────────────────────────────────────────

  static const _keywords = {
    'walk',
    'walked',
    'walking',
    'run',
    'ran',
    'running',
    'jog',
    'jogged',
    'jogging',
    'cycle',
    'cycled',
    'cycling',
    'bike',
    'biked',
    'biking',
    'swim',
    'swam',
    'swimming',
    'hike',
    'hiked',
    'hiking',
    'yoga',
    'pilates',
    'hiit',
    'cardio',
    'gym',
    'workout',
    'worked out',
    'weight',
    'weights',
    'lifting',
    'strength training',
    'dance',
    'danced',
    'dancing',
    'zumba',
    'elliptical',
    'rowing',
    'rowed',
    'jump rope',
    'skipping',
    'basketball',
    'football',
    'soccer',
    'tennis',
    'exercise',
    'exercised',
    'training',
    'trained',
    'pushup',
    'push-up',
    'pull-up',
    'pullup',
    'squat',
    'lunge',
    'plank',
    'treadmill',
    'stairmaster',
  };

  // ── MET values (energy per kg per hour) ──────────────────────────────────

  static const _met = {
    'walk': 3.5,
    'run': 10.0,
    'jog': 7.0,
    'cycle': 7.5,
    'bike': 7.5,
    'swim': 8.0,
    'hike': 5.5,
    'yoga': 3.0,
    'pilates': 4.0,
    'hiit': 10.0,
    'cardio': 7.0,
    'gym': 5.0,
    'workout': 5.0,
    'weight': 5.0,
    'weights': 5.0,
    'lifting': 5.0,
    'strength': 5.0,
    'dance': 6.0,
    'zumba': 6.0,
    'elliptical': 5.0,
    'rowing': 7.0,
    'jump rope': 12.0,
    'skipping': 12.0,
    'basketball': 7.0,
    'football': 7.5,
    'soccer': 7.5,
    'tennis': 7.0,
    'exercise': 5.0,
    'training': 5.0,
    'treadmill': 6.0,
    'stairmaster': 9.0,
    'pushup': 5.0,
    'pull-up': 5.0,
    'squat': 5.0,
    'plank': 4.0,
  };

  // Average speeds used to convert distance → duration for distance activities.
  static const _speedKmh = {
    'walk': 5.0,
    'run': 10.0,
    'jog': 8.0,
    'cycle': 15.0,
    'bike': 15.0,
    'swim': 2.0,
    'hike': 4.0,
  };

  static final _distanceRe = RegExp(
    r'(\d+(?:\.\d+)?)\s*(km|kilometer|kilometres?|miles?|mi\b)',
    caseSensitive: false,
  );
  static final _durationRe = RegExp(
    r'(\d+)\s*(hours?|hr|h\b|minutes?|min|mins)',
    caseSensitive: false,
  );

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns true if [text] likely describes physical activity.
  static bool looksLikeExercise(String text) {
    final lower = text.toLowerCase();
    return _keywords.any(lower.contains);
  }

  /// Parse [text] into an [ExerciseParseResult].
  ///
  /// Returns null if no known activity keyword is found.
  /// [weightKg] is used for calorie estimation (default 70 kg).
  static ExerciseParseResult? parse(String text, {double weightKg = 70}) {
    final lower = text.toLowerCase();

    // Find the best-matching activity key (prefer longer matches first).
    final sortedKeys = _met.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    String? activityKey;
    for (final key in sortedKeys) {
      if (lower.contains(key)) {
        activityKey = key;
        break;
      }
    }
    if (activityKey == null) return null;

    final met = _met[activityKey]!;

    final distanceMatch = _distanceRe.firstMatch(text);
    final durationMatch = _durationRe.firstMatch(text);

    double? distanceKm;
    int? durationMinutes;
    int calories;
    bool isEstimated = false;

    if (distanceMatch != null) {
      final qty = double.parse(distanceMatch.group(1)!);
      final unit = distanceMatch.group(2)!.toLowerCase();
      distanceKm = unit.startsWith('mi') ? qty * 1.60934 : qty;
      final speed = _speedKmh[activityKey] ?? 5.0;
      final hours = distanceKm / speed;
      durationMinutes = (hours * 60).round().clamp(1, 1440);
      calories = (met * weightKg * hours).round();
    } else if (durationMatch != null) {
      final qty = int.parse(durationMatch.group(1)!);
      final unit = durationMatch.group(2)!.toLowerCase();
      final isHours =
          unit.startsWith('h') && !unit.startsWith('hours') || unit == 'hr';
      durationMinutes =
          (isHours || unit == 'hours' || unit == 'hour') ? qty * 60 : qty;
      final hours = durationMinutes / 60.0;
      calories = (met * weightKg * hours).round();
    } else {
      // No distance or duration found — assume 30-minute session.
      isEstimated = true;
      durationMinutes = 30;
      calories = (met * weightKg * 0.5).round();
    }

    return ExerciseParseResult(
      activityName: _displayName(activityKey),
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      caloriesBurned: calories.clamp(10, 2000),
      isEstimated: isEstimated,
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static String _displayName(String key) => switch (key) {
        'walk' => 'Walking',
        'run' => 'Running',
        'jog' => 'Jogging',
        'cycle' || 'bike' => 'Cycling',
        'swim' => 'Swimming',
        'hike' => 'Hiking',
        'yoga' => 'Yoga',
        'pilates' => 'Pilates',
        'hiit' => 'HIIT',
        'cardio' => 'Cardio',
        'gym' || 'workout' => 'Workout',
        'weight' || 'weights' || 'lifting' || 'strength' => 'Weight Training',
        'dance' || 'zumba' => 'Dancing',
        'elliptical' => 'Elliptical',
        'rowing' => 'Rowing',
        'jump rope' || 'skipping' => 'Jump Rope',
        'basketball' => 'Basketball',
        'football' || 'soccer' => 'Football',
        'tennis' => 'Tennis',
        'treadmill' => 'Treadmill',
        'stairmaster' => 'StairMaster',
        _ => key[0].toUpperCase() + key.substring(1),
      };
}

class ExerciseParseResult {
  final String activityName;
  final double? distanceKm;
  final int? durationMinutes;
  final int caloriesBurned;
  final bool isEstimated;

  const ExerciseParseResult({
    required this.activityName,
    this.distanceKm,
    this.durationMinutes,
    required this.caloriesBurned,
    this.isEstimated = false,
  });
}

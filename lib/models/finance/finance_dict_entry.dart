/// One row in the finance personal dictionary — a learned mapping from a
/// lowercased word/phrase the user typed to a category they confirmed.
///
/// e.g. token "hamburger" → categoryId "food".
class FinanceDictEntry {
  final String token;
  final String categoryId;
  final int hits;
  final DateTime lastUsedAt;

  const FinanceDictEntry({
    required this.token,
    required this.categoryId,
    this.hits = 1,
    required this.lastUsedAt,
  });

  factory FinanceDictEntry.fromJson(Map<String, dynamic> json) =>
      FinanceDictEntry(
        token: json['token'] as String,
        categoryId: json['categoryId'] as String,
        hits: json['hits'] as int? ?? 1,
        lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'categoryId': categoryId,
        'hits': hits,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };
}

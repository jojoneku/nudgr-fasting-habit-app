/// A single food item normalized by the AI pipeline.
///
/// Produced by [AiCoachService.normalizeFoodInput] — contains a clean,
/// USDA-friendly name and a gram weight (volumes converted using food density).
class AiParsedFood {
  final String name;
  final double grams;

  const AiParsedFood({required this.name, required this.grams});
}

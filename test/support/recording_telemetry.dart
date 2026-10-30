import 'package:intermittent_fasting/services/advisor_telemetry.dart';

/// One event an [AdvisorTelemetry] was asked to record.
class RecordedEvent {
  const RecordedEvent(this.name, this.traceId, this.fields);

  final String name;
  final String? traceId;
  final Map<String, Object> fields;
}

/// An [AdvisorTelemetry] that keeps every event, in order.
class RecordingTelemetry implements AdvisorTelemetry {
  final List<RecordedEvent> events = [];

  List<String> get names => [for (final e in events) e.name];

  RecordedEvent named(String name) => events.singleWhere((e) => e.name == name);

  @override
  void record(
    String event, {
    String? traceId,
    Map<String, Object> fields = const {},
  }) =>
      events.add(RecordedEvent(event, traceId, fields));
}

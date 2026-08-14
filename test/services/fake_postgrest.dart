import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// An in-memory stand-in for PostgREST, injected into a **real**
/// `SupabaseClient` via its `httpClient` parameter.
///
/// Why not a `Fake` over `SupabaseClient`: the sync code's behaviour lives in
/// how it *composes queries* — filters, ordering, `offset`/`limit` paging,
/// upsert bodies. Stubbing the builder chain would assert against the stubs
/// rather than the requests, and the existing throw-everything fake can only
/// prove the failure paths. Speaking HTTP means the real query builder runs and
/// the request it produces is what gets answered, so a wrong filter or a
/// mis-paged select fails the test instead of passing silently.
///
/// Supports exactly what `SyncService` uses: `select` with `eq` / `in` filters,
/// `order`, `offset`+`limit`, and `upsert` of a single row or a list.
class FakePostgrest extends http.BaseClient {
  /// Rows per table, in insertion order.
  final Map<String, List<Map<String, dynamic>>> tables = {};

  /// Primary key columns per table, used to make upserts idempotent the way
  /// the real `PRIMARY KEY (...)` constraints do.
  static const Map<String, List<String>> primaryKeys = {
    'user_profile': ['user_id'],
    'user_collections': ['user_id'],
    'fasting_state': ['user_id'],
    'user_quests': ['user_id'],
    'advisor_state': ['user_id'],
    'nutrition_logs': ['user_id', 'date'],
    'activity_logs': ['user_id', 'date'],
    'finance_records': ['user_id', 'table_name', 'record_id'],
  };

  /// Every request seen, for asserting that a push did or did not happen.
  final List<({String method, String table, Object? body})> requests = [];

  /// When set, the next matching request fails with a 500 instead of being
  /// served. Cleared once it fires.
  String? failNextPostTo;

  /// Whether the schema has migration 054's `client_edited_at` column. When
  /// false, any request naming it is rejected the way PostgREST rejects an
  /// unknown column — which is what makes the client's capability probe
  /// meaningful rather than decorative.
  bool hasEditTimeColumn = true;

  /// Whether migration 054's trigger is in place, stamping `updated_at` with
  /// the server's clock and ignoring whatever the client sent.
  bool applyUpdatedAtTrigger = true;

  /// How far this fake server's clock sits from the test process's clock.
  /// Non-zero simulates the skew Phase 5 exists to cancel.
  Duration serverClockSkew = Duration.zero;

  DateTime get serverNow => DateTime.now().toUtc().add(serverClockSkew);

  int postCountFor(String table) =>
      requests.where((r) => r.method == 'POST' && r.table == table).length;

  /// Seeds [row] into [table] without going through the request path.
  ///
  /// Goes through the same primary-key merge as a real upsert: appending blindly
  /// would let a test build a duplicate-PK state the database forbids, and then
  /// assert against whichever copy it happened to read first.
  /// Seeded rows keep the `updated_at` the test supplied — seeding stands in
  /// for "another device wrote this at time X", not for a live write.
  void seed(String table, Map<String, dynamic> row) => _upsert(table, row);

  List<Map<String, dynamic>> rowsOf(String table) =>
      List.unmodifiable(tables[table] ?? const []);

  /// The single row of [table] matching [where], or null.
  Map<String, dynamic>? rowWhere(String table, Map<String, dynamic> where) {
    for (final row in tables[table] ?? const <Map<String, dynamic>>[]) {
      if (where.entries.every((e) => row[e.key] == e.value)) return row;
    }
    return null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final segments = request.url.pathSegments;
    // .../rest/v1/<table>
    final table = segments.isEmpty ? '' : segments.last;
    final method = request.method;

    Object? body;
    if (request is http.Request && request.body.isNotEmpty) {
      body = jsonDecode(request.body);
    }
    requests.add((method: method, table: table, body: body));

    if (!hasEditTimeColumn && _mentionsEditTime(request.url, body)) {
      return _json(
        {
          'message':
              'column "client_edited_at" of relation "$table" does not exist',
          'code': '42703',
        },
        status: 400,
        request: request,
      );
    }

    if (method == 'POST' && failNextPostTo == table) {
      failNextPostTo = null;
      return _json(
        {'message': 'simulated failure', 'code': '500'},
        status: 500,
        request: request,
      );
    }

    return switch (method) {
      'GET' => _json(_select(table, request.url), request: request),
      'POST' =>
        _json(_upsert(table, body, stampServerTime: true), request: request),
      _ => _json(const [], status: 405, request: request),
    };
  }

  bool _mentionsEditTime(Uri url, Object? body) {
    if ((url.queryParameters['select'] ?? '').contains('client_edited_at')) {
      return true;
    }
    final rows = body is List ? body : [if (body != null) body];
    return rows.any((r) => r is Map && r.containsKey('client_edited_at'));
  }

  // ── select ────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _select(String table, Uri url) {
    var rows = [
      for (final row in tables[table] ?? const <Map<String, dynamic>>[])
        Map<String, dynamic>.of(row),
    ];

    final params = url.queryParametersAll;
    for (final entry in params.entries) {
      if (const {'select', 'order', 'offset', 'limit', 'on_conflict'}
          .contains(entry.key)) {
        continue;
      }
      for (final raw in entry.value) {
        rows = rows.where((r) => _matches(r[entry.key], raw)).toList();
      }
    }

    // Ordering matters for correctness, not neatness: `collectPages` walks
    // `offset`/`limit` windows and assumes a stable sort, so an unordered fake
    // would let a paging bug pass.
    final orderCols = [
      for (final o in params['order'] ?? const <String>[])
        ...o.split(',').where((s) => s.isNotEmpty),
    ];
    if (orderCols.isNotEmpty) {
      rows.sort((a, b) {
        for (final spec in orderCols) {
          final parts = spec.split('.');
          final col = parts.first;
          final desc = parts.contains('desc');
          final cmp = _compare(a[col], b[col]) * (desc ? -1 : 1);
          if (cmp != 0) return cmp;
        }
        return 0;
      });
    }

    final offset = int.tryParse(url.queryParameters['offset'] ?? '') ?? 0;
    final limit = int.tryParse(url.queryParameters['limit'] ?? '');
    if (offset > 0) {
      rows = offset >= rows.length ? [] : rows.sublist(offset);
    }
    if (limit != null && limit < rows.length) rows = rows.sublist(0, limit);
    return rows;
  }

  /// Handles the filter grammar SyncService produces: `eq.<v>` and `in.(...)`.
  bool _matches(Object? value, String filter) {
    if (filter.startsWith('eq.')) return '$value' == filter.substring(3);
    if (filter.startsWith('in.(') && filter.endsWith(')')) {
      final inner = filter.substring(4, filter.length - 1);
      final wanted =
          inner.split(',').map((s) => s.trim().replaceAll('"', '')).toSet();
      return wanted.contains('$value');
    }
    throw UnsupportedError('FakePostgrest: unhandled filter "$filter"');
  }

  int _compare(Object? a, Object? b) {
    if (a is Comparable && b is Comparable) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  // ── upsert ────────────────────────────────────────────────────────────────

  /// [stampServerTime] mirrors migration 054's `BEFORE INSERT OR UPDATE`
  /// trigger: the server overwrites `updated_at` with its own clock, whatever
  /// the client sent. Returns the stored rows, which is what
  /// `.select('updated_at')` on an upsert reads back.
  List<Map<String, dynamic>> _upsert(String table, Object? body,
      {bool stampServerTime = false}) {
    final incoming = <Map<String, dynamic>>[
      if (body is List)
        for (final r in body) Map<String, dynamic>.of(r as Map<String, dynamic>)
      else if (body is Map<String, dynamic>)
        Map<String, dynamic>.of(body),
    ];
    if (stampServerTime && applyUpdatedAtTrigger) {
      for (final row in incoming) {
        row['updated_at'] = serverNow.toIso8601String();
      }
    }
    final rows = tables.putIfAbsent(table, () => []);
    final keyCols = primaryKeys[table];
    for (final row in incoming) {
      final existing = keyCols == null
          ? -1
          : rows.indexWhere(
              (r) => keyCols.every((c) => r[c] == row[c]),
            );
      if (existing >= 0) {
        rows[existing] = row;
      } else {
        rows.add(row);
      }
    }
    return incoming;
  }

  http.StreamedResponse _json(
    Object? payload, {
    int status = 200,
    required http.BaseRequest request,
  }) {
    final bytes = utf8.encode(jsonEncode(payload));
    // `request` is required: postgrest dereferences `response.request!` when
    // parsing, so a response without it throws before any assertion runs.
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
      contentLength: bytes.length,
      request: request,
    );
  }
}

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

  int postCountFor(String table) =>
      requests.where((r) => r.method == 'POST' && r.table == table).length;

  /// Seeds [row] into [table] without going through the request path.
  ///
  /// Goes through the same primary-key merge as a real upsert: appending blindly
  /// would let a test build a duplicate-PK state the database forbids, and then
  /// assert against whichever copy it happened to read first.
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
      'POST' => _json(_upsert(table, body), request: request),
      _ => _json(const [], status: 405, request: request),
    };
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

  List<Map<String, dynamic>> _upsert(String table, Object? body) {
    final incoming = <Map<String, dynamic>>[
      if (body is List)
        for (final r in body) Map<String, dynamic>.of(r as Map<String, dynamic>)
      else if (body is Map<String, dynamic>)
        Map<String, dynamic>.of(body),
    ];
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

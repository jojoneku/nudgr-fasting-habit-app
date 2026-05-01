import 'package:flutter/foundation.dart';
import '../services/sync_service.dart';
import 'auth_presenter.dart';

class SyncPresenter extends ChangeNotifier {
  final SyncService _sync;
  final AuthPresenter _auth;

  SyncPresenter(this._sync, this._auth) {
    _sync.setOnStateChange(_onSyncStateChanged);
    _auth.addListener(_onAuthChanged);
  }

  bool get isSyncing => _sync.isSyncing;
  DateTime? get lastSyncedAt => _sync.lastSyncedAt;
  int get pendingCount => _sync.pendingCount;

  String get statusLabel {
    if (!_auth.isSignedIn) return 'Sign in to sync';
    if (_sync.isSyncing) return 'Syncing…';
    final pending = _sync.pendingCount;
    if (pending > 0) return '$pending change${pending == 1 ? '' : 's'} pending';
    final last = _sync.lastSyncedAt;
    if (last == null) return 'Not synced yet';
    return 'Synced ${_timeAgo(last)}';
  }

  Future<void> forceSync() => _sync.forceSync();

  void _onSyncStateChanged() => notifyListeners();
  void _onAuthChanged() => notifyListeners();

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}

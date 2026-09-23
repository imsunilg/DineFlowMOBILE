import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../auth_controller.dart';
import '../config.dart';
import '../token_store.dart';

enum RealtimeStatus { disconnected, connecting, connected, reconnecting }

/// A real-time event pushed by the API's hub. Mirrors DineFlow.Application.Realtime.RealtimeEnvelope on the server
/// and the RealtimeEnvelope the web app's SignalrService decodes from the same wire format.
class RealtimeEnvelope {
  RealtimeEnvelope.fromJson(Map<String, dynamic> j)
      : eventId = j['eventId'] as String? ?? '',
        eventType = j['eventType'] as String? ?? '',
        tenantId = j['tenantId'] as String? ?? '',
        entityType = j['entityType'] as String? ?? '',
        entityId = j['entityId'] as String? ?? '',
        data = (j['data'] is Map) ? (j['data'] as Map).cast<String, dynamic>() : const {};

  final String eventId;
  final String eventType;
  final String tenantId;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> data;
}

typedef RealtimeHandler = void Function(RealtimeEnvelope event);

/// One managed SignalR connection for the whole signed-in session: connects after sign-in, disconnects on
/// sign-out, and reconnects automatically. Mirrors DineFlowWEB's SignalrService; tenant/permission group
/// membership is derived server-side from the JWT on every connect (including a reconnect), so there is
/// nothing to explicitly "rejoin" here.
class SignalrService with WidgetsBindingObserver {
  SignalrService({required this.auth, required this.tokens, required this.config}) {
    WidgetsBinding.instance.addObserver(this);
    auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthController auth;
  final TokenStore tokens;
  final AppConfig config;

  HubConnection? _connection;
  final Map<String, List<RealtimeHandler>> _handlers = {};
  final List<VoidCallback> _reconnectHandlers = [];
  final ValueNotifier<RealtimeStatus> _status = ValueNotifier(RealtimeStatus.disconnected);
  ValueListenable<RealtimeStatus> get status => _status;

  /// Bounded ring of recently-applied event ids, so a duplicate delivery (retry, reconnect race) is a no-op.
  final List<String> _seenEventIds = [];
  final Set<String> _seenEventIdSet = {};
  static const _seenLimit = 500;

  /// Subscribe to one event type (see the API's RealtimeEvents constants for the full list). Returns an
  /// unsubscribe callback; call it from the screen's dispose().
  VoidCallback on(String eventType, RealtimeHandler handler) {
    (_handlers[eventType] ??= []).add(handler);
    return () => _handlers[eventType]?.remove(handler);
  }

  /// Fires after every reconnect (not the first connect). Screens use this to re-sync via REST: events raised
  /// while disconnected are not replayed, so the only authoritative recovery is re-fetching current state.
  VoidCallback onReconnected(VoidCallback handler) {
    _reconnectHandlers.add(handler);
    return () => _reconnectHandlers.remove(handler);
  }

  bool _alreadyApplied(String eventId) {
    if (_seenEventIdSet.contains(eventId)) return true;
    _seenEventIdSet.add(eventId);
    _seenEventIds.add(eventId);
    if (_seenEventIds.length > _seenLimit) _seenEventIdSet.remove(_seenEventIds.removeAt(0));
    return false;
  }

  void _onAuthChanged() {
    if (auth.status == AuthStatus.signedIn) {
      unawaited(_connect());
    } else {
      _disconnect();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS can suspend sockets while the app is backgrounded; check on resume rather than assume it's alive.
    if (state == AppLifecycleState.resumed && auth.status == AuthStatus.signedIn) {
      if (_connection == null || _connection!.state != HubConnectionState.Connected) unawaited(_connect());
    }
  }

  String get _hubUrl => '${config.baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '')}/hubs/realtime';

  Future<void> _connect() async {
    if (_connection != null) return; // one connection per session; a refreshed access token needs no new socket
    final connection = HubConnectionBuilder()
        .withUrl(_hubUrl, options: HttpConnectionOptions(accessTokenFactory: () async => (await tokens.read())?.access ?? ''))
        .withAutomaticReconnect(retryDelays: [0, 2000, 5000, 10000, 30000])
        .build();

    connection.on('RealtimeEvent', (args) {
      if (args == null || args.isEmpty || args[0] is! Map) return;
      final envelope = RealtimeEnvelope.fromJson((args[0] as Map).cast<String, dynamic>());
      if (_alreadyApplied(envelope.eventId)) return;
      for (final handler in List<RealtimeHandler>.of(_handlers[envelope.eventType] ?? const [])) {
        handler(envelope);
      }
    });
    connection.onreconnecting(({error}) => _status.value = RealtimeStatus.reconnecting);
    connection.onreconnected(({connectionId}) {
      _status.value = RealtimeStatus.connected;
      for (final handler in List<VoidCallback>.of(_reconnectHandlers)) {
        handler();
      }
    });
    connection.onclose(({error}) {
      _status.value = RealtimeStatus.disconnected;
      if (identical(_connection, connection)) _connection = null;
    });

    _connection = connection;
    _status.value = RealtimeStatus.connecting;
    try {
      await connection.start();
      _status.value = RealtimeStatus.connected;
    } catch (_) {
      _status.value = RealtimeStatus.disconnected;
      if (identical(_connection, connection)) _connection = null;
    }
  }

  void _disconnect() {
    final c = _connection;
    _connection = null;
    _status.value = RealtimeStatus.disconnected;
    c?.stop();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    auth.removeListener(_onAuthChanged);
    _disconnect();
  }
}

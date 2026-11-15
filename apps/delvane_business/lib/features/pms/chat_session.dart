import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../workspace/workspace_models.dart';

enum ChatChange { history, submitted, replied, failed }

class ChatEntry {
  ChatEntry({
    required this.id,
    required this.role,
    required this.content,
    this.serverId,
    this.requestId,
    this.metadata = const {},
  });
  final String id, role, content;
  String? serverId;
  final String? requestId;
  final Map<String, dynamic> metadata;
}

class ChatTurn {
  ChatTurn(this.id, this.text, this.language, this.conversationId);
  final String id, text, language;
  final String? conversationId;
  bool complete = false, failed = false;
}

/// Authenticated-session state outlives the chat widget. Retrying reuses one
/// server-recognized turn ID, including after a response was lost in transit.
class PmsChatSession extends ChangeNotifier {
  PmsChatSession(this.api, this.onChanged, {this.canRead});
  final ApiClient api;
  final VoidCallback onChanged;
  final bool Function()? canRead;
  final List<ChatEntry> _messages = [];
  List<ChatEntry> get messages => List.unmodifiable(_messages);
  String? conversationId;
  ChatTurn? turn;
  bool busy = false, initialized = false, _disposed = false;
  int _epoch = 0;
  int revision = 0;
  ChatChange change = ChatChange.history;
  String? latestAnswerId;
  double scrollOffset = 0;
  bool followLatest = true;

  void _emit(ChatChange value) {
    if (_disposed) return;
    change = value;
    revision++;
    notifyListeners();
    onChanged();
  }

  void syncHistory(Map<String, dynamic> snapshot, {bool notify = true}) {
    if (_disposed) return;
    final conv = snapshot['conversation'];
    if (conv is Map && conv['id'] is String) conversationId = conv['id'];
    final old = List<ChatEntry>.of(_messages), used = <String>{};
    final merged = <ChatEntry>[];
    for (final value in (snapshot['messages'] as List? ?? [])) {
      final row = jsonObject(value);
      final metadata = row['metadata'] is Map
          ? jsonObject(row['metadata'])
          : <String, dynamic>{};
      final serverId = row['id'] as String?;
      final requestId = metadata['client_request_id'] as String?;
      final role = row['role'].toString(), content = row['content'].toString();
      ChatEntry? existing;
      for (final entry in old) {
        if (used.contains(entry.id)) continue;
        if ((serverId != null && entry.serverId == serverId) ||
            (requestId != null &&
                entry.requestId == requestId &&
                entry.role == role)) {
          existing = entry;
          break;
        }
      }
      existing ??= old
          .where(
            (e) =>
                !used.contains(e.id) && e.role == role && e.content == content,
          )
          .firstOrNull;
      final entry = ChatEntry(
        id: existing?.id ?? 'history-${serverId ?? merged.length}',
        serverId: serverId,
        requestId: requestId ?? existing?.requestId,
        role: role,
        content: content,
        metadata: metadata,
      );
      used.add(entry.id);
      merged.add(entry);
    }
    // An in-flight/failed optimistic turn must not disappear on background refresh.
    merged.addAll(
      old.where((e) => !used.contains(e.id) && e.requestId != null),
    );
    _messages
      ..clear()
      ..addAll(merged);
    initialized = true;
    if (turn != null &&
        merged.any((e) => e.requestId == turn!.id && e.role != 'user')) {
      turn!
        ..complete = true
        ..failed = false;
    }
    if (notify) _emit(ChatChange.history);
  }

  Future<bool> send(String text, String language) async {
    if (busy || text.trim().isEmpty || _disposed || canRead?.call() == false) {
      return false;
    }
    if (turn?.failed == true && turn!.text == text) return retry();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    turn = ChatTurn(id, text, language, conversationId);
    _messages.add(
      ChatEntry(id: 'user-$id', requestId: id, role: 'user', content: text),
    );
    initialized = true;
    return _post(turn!);
  }

  Future<bool> retry() async {
    if (busy ||
        turn == null ||
        turn!.complete ||
        _disposed ||
        canRead?.call() == false) {
      return false;
    }
    return _post(turn!);
  }

  Future<bool> _post(ChatTurn pending) async {
    final epoch = _epoch;
    busy = true;
    pending.failed = false;
    _emit(ChatChange.submitted);
    try {
      final reply = jsonObject(
        await api.post('/api/rosa/chat', {
          'message': pending.text,
          'language': pending.language,
          'client_request_id': pending.id,
          if (pending.conversationId != null)
            'conversation_id': pending.conversationId,
        }),
      );
      if (_disposed || epoch != _epoch || canRead?.call() == false) {
        return false;
      }
      if (reply['answer'] is! String) {
        throw const ApiException('Invalid assistant response.');
      }
      conversationId = reply['conversation_id'] as String? ?? conversationId;
      final user = _messages
          .where((e) => e.requestId == pending.id && e.role == 'user')
          .firstOrNull;
      user?.serverId = reply['user_message_id'] as String?;
      if (!_messages.any(
        (e) => e.requestId == pending.id && e.role != 'user',
      )) {
        final answer = ChatEntry(
          id: 'answer-${pending.id}',
          requestId: pending.id,
          serverId: reply['assistant_message_id'] as String?,
          role: 'rosa',
          content: reply['answer'] as String,
          metadata: {'read_only': reply['read_only'] == true},
        );
        _messages.add(answer);
        latestAnswerId = answer.id;
      }
      pending.complete = true;
      busy = false;
      _emit(ChatChange.replied);
      return true;
    } catch (_) {
      if (_disposed || epoch != _epoch || canRead?.call() == false) {
        return false;
      }
      busy = false;
      if (pending.complete) {
        _emit(ChatChange.replied);
        return true;
      }
      pending.failed = true;
      _emit(ChatChange.failed);
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _messages.clear();
    super.dispose();
  }

  void invalidateAccess() {
    _epoch++;
    busy = false;
    _messages.clear();
    turn = null;
    conversationId = null;
    initialized = false;
    latestAnswerId = null;
    scrollOffset = 0;
  }
}

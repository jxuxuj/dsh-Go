import 'package:dsh_client/dsh_client.dart';

/// One Codex thread as the Host's `thread/list` reports it.
///
/// The Host sanitises the App Server response to exactly these fields, so a
/// missing field means the Host did not have it — never guess a default that
/// looks like real content.
class CodexThread {
  const CodexThread({required this.id, this.name, this.preview, this.cwd, this.updatedAt, this.projectId});

  final String id;
  final String? name;
  final String? preview;
  final String? cwd;
  final int? updatedAt;
  final String? projectId;

  /// A title worth showing: the user's name, else the first line of the
  /// preview, else the id so an entry is never blank.
  String get title {
    final named = name?.trim();
    if (named != null && named.isNotEmpty) return named;
    final previewed = preview?.trim();
    if (previewed != null && previewed.isNotEmpty) return previewed.split('\n').first;
    return id;
  }

  static List<CodexThread> parseList(Object? result) {
    if (result is! Map) return const <CodexThread>[];
    final data = result['data'];
    if (data is! List) return const <CodexThread>[];
    final threads = <CodexThread>[];
    for (final item in data) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || id.isEmpty) continue;
      threads.add(
        CodexThread(
          id: id,
          name: item['name'] as String?,
          preview: item['preview'] as String?,
          cwd: item['cwd'] as String?,
          updatedAt: item['updatedAt'] is num ? (item['updatedAt'] as num).toInt() : null,
          projectId: item['projectId'] as String?,
        ),
      );
    }
    return threads;
  }
}

/// One Codex project (the Host's "workspace") and the directories it covers.
class CodexProject {
  const CodexProject({required this.id, required this.name, this.root});

  final String id;
  final String name;
  final String? root;

  static List<CodexProject> parseList(Object? result) {
    if (result is! Map) return const <CodexProject>[];
    final data = result['data'];
    if (data is! List) return const <CodexProject>[];
    final projects = <CodexProject>[];
    for (final item in data) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is! String || name is! String) continue;
      String? root;
      final roots = item['roots'];
      if (roots is List) {
        for (final entry in roots) {
          if (entry is Map && entry['path'] is String) {
            root = entry['path'] as String;
            break;
          }
        }
      }
      projects.add(CodexProject(id: id, name: name, root: root));
    }
    return projects;
  }
}

/// Minimal Codex client over an already-authenticated Remote carrier.
///
/// Calls go out as `codex.app.call` with `{method, params}`; the Host runs
/// them against its own `codex app-server` and answers on the same encrypted
/// session. Only the methods in the Host's fixed allow-list are accepted.
class CodexClient {
  CodexClient(this.carrier);

  final DshCarrier carrier;

  Future<Object?> _call(String method, Map<String, Object?> params) =>
      carrier.rawCall('codex.app.call', <String, Object?>{'method': method, 'params': params});

  /// Codex projects (the Host's workspaces).
  Future<List<CodexProject>> listProjects({int limit = 100}) async {
    final result = await _call('project/list', <String, Object?>{'limit': limit});
    return CodexProject.parseList(result);
  }

  /// Codex threads, newest first by default.
  Future<List<CodexThread>> listThreads({int limit = 50, bool archived = false, String? searchTerm}) async {
    final params = <String, Object?>{
      'limit': limit,
      'sortKey': 'recency_at',
      'sortDirection': 'desc',
      'archived': archived,
      if (searchTerm != null && searchTerm.trim().isNotEmpty) 'searchTerm': searchTerm.trim(),
    };
    return CodexThread.parseList(await _call('thread/list', params));
  }

  /// One page of a thread's history, oldest first.
  ///
  /// The Host answers `dsh/sessionHistory` with a bounded page of DSH-shaped
  /// records (`header`, `cursor`, `nextTurn`, `records`, `hasMore`). The exact
  /// event payloads are the Host's projection of Codex turns, so the text is
  /// pulled tolerantly instead of pinning one shape that would break on the
  /// next Host version.
  Future<CodexHistory> readHistory(String threadId, {int maxMessages = 60}) async {
    final result = await _call('dsh/sessionHistory', <String, Object?>{
      'threadId': threadId,
      'maxMessages': maxMessages,
    });
    return CodexHistory.parse(result);
  }

  /// Sends a text prompt to [threadId] and starts a turn.
  Future<void> sendText(String threadId, String text) async {
    await _call('turn/start', <String, Object?>{
      'threadId': threadId,
      'input': [
        {'type': 'text', 'text': text},
      ],
    });
  }

  /// Stops the running turn.
  Future<void> interrupt(String threadId, String turnId) =>
      _call('turn/interrupt', <String, Object?>{'threadId': threadId, 'turnId': turnId});

  /// Branches [threadId] into a new thread that keeps its earlier turns.
  Future<String?> fork(String threadId) async {
    final result = await _call('thread/fork', <String, Object?>{'threadId': threadId});
    if (result is Map) {
      final thread = result['thread'];
      if (thread is Map && thread['id'] is String) return thread['id'] as String;
      if (result['id'] is String) return result['id'] as String;
    }
    return null;
  }
}

/// One readable line of a thread.
class CodexMessage {
  const CodexMessage({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

/// A page of thread history with the paging hints the Host returned.
class CodexHistory {
  const CodexHistory({required this.messages, required this.hasMore, this.cursor, this.activeTurnId});

  final List<CodexMessage> messages;
  final bool hasMore;
  final int? cursor;
  final String? activeTurnId;

  static CodexHistory parse(Object? result) {
    if (result is! Map) return const CodexHistory(messages: <CodexMessage>[], hasMore: false);
    final records = result['records'];
    final messages = <CodexMessage>[];
    if (records is List) {
      for (final record in records) {
        final message = _messageOf(record);
        if (message != null) messages.add(message);
      }
    }
    final cursor = result['cursor'];
    final activeTurnId = result['activeTurnId'];
    return CodexHistory(
      messages: messages,
      hasMore: result['hasMore'] == true,
      cursor: cursor is num ? cursor.toInt() : null,
      activeTurnId: activeTurnId is String ? activeTurnId : null,
    );
  }

  static CodexMessage? _messageOf(Object? record) {
    if (record is! Map) return null;
    final event = record['event'];
    if (event is! Map) return null;
    final type = event['type'];
    if (type is! String) return null;
    final fromUser = type.startsWith('user/');
    final isAssistant = type.startsWith('assistant/') || type.startsWith('reasoning');
    if (!fromUser && !isAssistant) return null;
    final text = _collectText(event['data']).trim();
    if (text.isEmpty) return null;
    return CodexMessage(fromUser: fromUser, text: text);
  }

  /// Only content-bearing keys are walked, so ids and roles never leak into
  /// the text; everything under them is joined in document order.
  static const _textKeys = ['text', 'content', 'message', 'parts', 'items', 'data'];

  static String _collectText(Object? value, [int depth = 0]) {
    if (depth > 8 || value == null) return '';
    if (value is String) return value.trim();
    if (value is List) {
      final parts = value.map((item) => _collectText(item, depth + 1)).where((part) => part.isNotEmpty).toList();
      return parts.join('\n').trim();
    }
    if (value is Map) {
      final parts = <String>[];
      for (final key in _textKeys) {
        final part = _collectText(value[key], depth + 1);
        if (part.isNotEmpty) parts.add(part);
      }
      return parts.join('\n').trim();
    }
    return '';
  }
}

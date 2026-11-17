import 'package:dsh_client/dsh_client.dart';

/// One Codex thread as the Host's `thread/list` reports it.
///
/// The Host sanitises the App Server response to exactly these fields, so a
/// missing field means the Host did not have it — never guess a default that
/// looks like real content.
class CodexThread {
  const CodexThread({required this.id, this.name, this.preview, this.cwd, this.updatedAt});

  final String id;
  final String? name;
  final String? preview;
  final String? cwd;
  final int? updatedAt;

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
        ),
      );
    }
    return threads;
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
}

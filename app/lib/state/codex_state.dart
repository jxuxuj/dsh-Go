import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../remote/codex/codex_client.dart';
import 'connection_state.dart';

/// Codex threads on the connected Host, newest first.
///
/// Rebuilt whenever the connection changes: a new Host is a different Codex
/// installation and its threads must not be mixed with the previous one's.
final codexThreadsProvider = FutureProvider.autoDispose<List<CodexThread>>((ref) async {
  final client = ref.watch(activeConnectionProvider).value?.client;
  if (client == null) return const <CodexThread>[];
  return CodexClient(client.carrier).listThreads();
});

/// One Codex project with the threads that belong to it.
class CodexWorkspace {
  const CodexWorkspace({required this.name, required this.threads, this.id, this.root});

  final String? id;
  final String name;
  final String? root;
  final List<CodexThread> threads;
}

/// Codex projects and their threads, in the shape the drawer needs.
///
/// Threads whose `projectId` matches no listed project fall into one trailing
/// group so nothing is silently dropped: a Host that does not report projects
/// still yields a usable list.
final codexWorkspaceProvider = FutureProvider.autoDispose<List<CodexWorkspace>>((ref) async {
  final client = ref.watch(activeConnectionProvider).value?.client;
  if (client == null) return const <CodexWorkspace>[];
  final codex = CodexClient(client.carrier);
  final projects = await codex.listProjects();
  final threads = await codex.listThreads(limit: 100);
  final byProject = <String, List<CodexThread>>{};
  final orphans = <CodexThread>[];
  for (final thread in threads) {
    final projectId = thread.projectId;
    if (projectId == null) {
      orphans.add(thread);
    } else {
      byProject.putIfAbsent(projectId, () => <CodexThread>[]).add(thread);
    }
  }
  final workspaces = <CodexWorkspace>[
    for (final project in projects)
      CodexWorkspace(
        id: project.id,
        name: project.name,
        root: project.root,
        threads: byProject.remove(project.id) ?? const <CodexThread>[],
      ),
  ];
  // Leftovers: a thread whose project is not in the catalog (archived project,
  // or a Host that only lists threads).
  final leftover = <CodexThread>[...byProject.values.expand((list) => list), ...orphans];
  if (leftover.isNotEmpty) {
    workspaces.add(CodexWorkspace(name: '其他', threads: leftover));
  }
  return workspaces;
});

/// One thread's history on the connected Host.
final codexHistoryProvider = FutureProvider.autoDispose.family<CodexHistory, String>((ref, threadId) async {
  final client = ref.watch(activeConnectionProvider).value?.client;
  if (client == null) return const CodexHistory(messages: <CodexMessage>[], hasMore: false);
  return CodexClient(client.carrier).readHistory(threadId);
});

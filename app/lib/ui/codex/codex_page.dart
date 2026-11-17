import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../remote/codex/codex_client.dart';
import '../../state/codex_state.dart';
import 'codex_thread_page.dart';

/// Codex threads on the connected Host.
///
/// This is the first vertical slice of the Codex backend: it proves the client
/// can reach `codex.app.call` over the existing Remote session and that the
/// thread list renders. Opening a thread, sending prompts, media and approvals
/// come next and are not wired yet.
class CodexPage extends ConsumerWidget {
  const CodexPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(codexThreadsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Codex'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(codexThreadsProvider),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: threads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('读取 Codex 线程失败\n\n$error'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('这台主机上还没有 Codex 线程')));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(codexThreadsProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _ThreadTile(thread: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});

  final CodexThread thread;

  @override
  Widget build(BuildContext context) {
    final subtitle = thread.cwd ?? '';
    return ListTile(
      leading: const Icon(Icons.terminal),
      title: Text(thread.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CodexThreadPage(threadId: thread.id, title: thread.title),
        ),
      ),
    );
  }
}

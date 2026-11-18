import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/codex_state.dart';
import '../shell/drawer/session_tile.dart';
import 'codex_thread_page.dart';

/// The drawer's conversation list, showing Codex workspaces and threads.
///
/// It reuses the app's own row widgets ([SessionTile] / [DrawerEyebrow]) so the
/// Codex side looks exactly like the DeepSeek side; only the data source and
/// the tap target differ.
class CodexDrawerList extends ConsumerWidget {
  const CodexDrawerList({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(codexWorkspaceProvider);
    return workspaces.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText('Codex 读取失败\n\n$error'),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('这台主机上没有 Codex 工作区'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(codexWorkspaceProvider),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final group in groups) ...[
                DrawerEyebrow(group.name),
                if (group.threads.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 2, 20, 6),
                    child: Text('（没有线程）', style: TextStyle(fontSize: 12)),
                  ),
                for (final thread in group.threads)
                  SessionTile(
                    title: thread.title,
                    running: false,
                    current: false,
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CodexThreadPage(threadId: thread.id, title: thread.title),
                        ),
                      );
                      onClose();
                    },
                    onLongPress: null,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

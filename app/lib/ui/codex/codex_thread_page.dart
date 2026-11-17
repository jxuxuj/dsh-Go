import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../remote/codex/codex_client.dart';
import '../../state/codex_state.dart';

/// One Codex thread: its history, read over the same Remote session.
///
/// Read-only for now — sending, streaming, media and approvals are the next
/// slices. The point of this page is to prove history comes through intact.
class CodexThreadPage extends ConsumerWidget {
  const CodexThreadPage({super.key, required this.threadId, this.title});

  final String threadId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(codexHistoryProvider(threadId));
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'Codex 线程'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(codexHistoryProvider(threadId)),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('读取历史失败\n\n$error'),
          ),
        ),
        data: (page) {
          if (page.messages.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('这个线程还没有可显示的消息')));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: page.messages.length,
            itemBuilder: (context, index) => _Bubble(message: page.messages[index]),
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final CodexMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fromUser = message.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: fromUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(message.text),
      ),
    );
  }
}

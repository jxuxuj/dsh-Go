import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../remote/codex/codex_client.dart';
import '../../state/codex_state.dart';
import '../../state/connection_state.dart';

/// One Codex thread: history, a composer, stop and branch.
///
/// Live updates use a short poll of `dsh/sessionHistory` while a turn is
/// running. The Host's push stream (`codex.app.*` events) is not wired yet; a
/// poll is slower but works on the same allow-listed call and cannot desync
/// the transcript.
class CodexThreadPage extends ConsumerStatefulWidget {
  const CodexThreadPage({super.key, required this.threadId, this.title});

  final String threadId;
  final String? title;

  @override
  ConsumerState<CodexThreadPage> createState() => _CodexThreadPageState();
}

class _CodexThreadPageState extends ConsumerState<CodexThreadPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  CodexClient? get _client {
    final client = ref.read(activeConnectionProvider).value?.client;
    return client == null ? null : CodexClient(client.carrier);
  }

  void _startPolling() {
    _poll?.cancel();
    var ticks = 0;
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || ++ticks > 150) {
        timer.cancel();
        return;
      }
      ref.invalidate(codexHistoryProvider(widget.threadId));
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final client = _client;
    if (text.isEmpty || client == null || _sending) return;
    setState(() => _sending = true);
    try {
      await client.sendText(widget.threadId, text);
      _controller.clear();
      ref.invalidate(codexHistoryProvider(widget.threadId));
      _startPolling();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stop(CodexHistory page) async {
    final client = _client;
    final turnId = page.activeTurnId;
    if (client == null || turnId == null) return;
    try {
      await client.interrupt(widget.threadId, turnId);
      ref.invalidate(codexHistoryProvider(widget.threadId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('中断失败：$error')));
      }
    }
  }

  Future<void> _fork() async {
    final client = _client;
    if (client == null) return;
    try {
      final id = await client.fork(widget.threadId);
      if (!mounted) return;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分支已创建，但主机没有返回新线程 ID')));
        return;
      }
      ref.invalidate(codexThreadsProvider);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => CodexThreadPage(threadId: id, title: '分支')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分支失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(codexHistoryProvider(widget.threadId));
    final page = history.value;
    final running = page?.activeTurnId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Codex 线程'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(codexHistoryProvider(widget.threadId)),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
          IconButton(
            onPressed: _fork,
            icon: const Icon(Icons.call_split),
            tooltip: '创建分支',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _Body(history: history)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (running)
                    IconButton.filledTonal(
                      onPressed: page == null ? null : () => _stop(page),
                      icon: const Icon(Icons.stop),
                      tooltip: '停止',
                    ),
                  if (running) const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '给 Codex 发消息…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    tooltip: '发送',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.history});

  final AsyncValue<CodexHistory> history;

  @override
  Widget build(BuildContext context) {
    return history.when(
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

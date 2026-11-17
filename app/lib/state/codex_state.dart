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

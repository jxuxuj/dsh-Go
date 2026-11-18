import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which backend the drawer and the conversation list speak to.
///
/// The Remote session is shared: only the calls and the rows change. Kept in
/// memory (not persisted) so a launch always lands on DeepSeek, the backend
/// that is always there.
enum ChatBackend {
  deepseek,
  codex;

  String get label => this == ChatBackend.codex ? 'Codex' : 'DeepSeek';
}

class BackendController extends Notifier<ChatBackend> {
  @override
  ChatBackend build() => ChatBackend.deepseek;

  void toggle() => state = state == ChatBackend.deepseek ? ChatBackend.codex : ChatBackend.deepseek;

  void set(ChatBackend backend) => state = backend;
}

final backendProvider = NotifierProvider<BackendController, ChatBackend>(BackendController.new);

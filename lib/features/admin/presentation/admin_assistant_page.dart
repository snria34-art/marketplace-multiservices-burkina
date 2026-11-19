import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';

class AdminAssistantPage extends ConsumerStatefulWidget {
  const AdminAssistantPage({super.key});

  @override
  ConsumerState<AdminAssistantPage> createState() => _AdminAssistantPageState();
}

class _AdminAssistantPageState extends ConsumerState<AdminAssistantPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _sending) return;
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      _showError('Connectez-vous avec un compte administrateur.');
      return;
    }

    setState(() {
      _messages.add({'role': 'user', 'text': question});
      _controller.clear();
      _sending = true;
    });

    try {
      final result = await client.functions.invoke(
        'platform-assistant',
        body: {'question': question},
      );
      final payload = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};
      if (result.status < 200 || result.status >= 300 || payload['ok'] != true) {
        throw StateError(
          payload['message']?.toString() ??
              payload['error']?.toString() ??
              'Assistant indisponible.',
        );
      }
      if (!mounted) return;
      setState(() => _messages.add({
        'role': 'assistant',
        'text': payload['answer']?.toString() ?? 'Aucune réponse reçue.',
      }));
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add({
        'role': 'assistant',
        'text': safeBackendErrorMessage(
          error,
          fallback: 'Je ne peux pas répondre pour le moment. Réessayez.',
        ),
      }));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant de l’administration')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Assistant technique en lecture seule : il peut diagnostiquer et proposer des solutions. Toute modification doit être validée séparément.',
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (_sending && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final item = _messages[index];
                final mine = item['role'] == 'user';
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(item['text'] ?? ''),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      enabled: !_sending,
                      decoration: const InputDecoration(
                        hintText: 'Décris le problème à diagnostiquer…',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                    tooltip: 'Envoyer',
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
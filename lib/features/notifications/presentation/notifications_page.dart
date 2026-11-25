import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/backend_error_message.dart';
import '../../../core/providers/repository_providers.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() =>
      _NotificationsPageState();
}

class _NotificationsPageState
    extends ConsumerState<NotificationsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _notificationsChannel;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _startRealtime();
  }

  void _startRealtime() {
    final client = ref.read(marketplaceNotificationClientProvider);
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;

    try {
      _notificationsChannel = client
          .channel('notifications-${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: user.id,
            ),
            callback: (_) {
              if (!mounted) return;
              setState(() => _future = _load());
            },
          )
          .subscribe();
    } catch (_) {
      // The user can still refresh notifications manually if Realtime setup
      // fails; initialization must not break the screen.
      _notificationsChannel = null;
    }
  }

  Future<void> _removeChannelSafely(
    SupabaseClient client,
    RealtimeChannel channel,
  ) async {
    try {
      await client.removeChannel(channel);
    } catch (_) {
      // Channel cleanup is best-effort during navigation/disposal.
    }
  }

  @override
  void dispose() {
    final client = ref.read(marketplaceNotificationClientProvider);
    final channel = _notificationsChannel;
    _notificationsChannel = null;
    if (client != null && channel != null) {
      unawaited(_removeChannelSafely(client, channel));
    }
    super.dispose();
  }


  Future<List<Map<String, dynamic>>> _load() async {
    final repository = ref.read(notificationRepositoryProvider);
    if (repository == null) return const [];
    return repository.list();
  }

  Future<void> _markRead(String id) async {
    final repository = ref.read(notificationRepositoryProvider);
    if (repository == null) return;

    try {
      await repository.markRead(id);

      if (!mounted) return;
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeBackendErrorMessage(
              error,
              fallback: 'Lecture de la notification impossible. Réessayez.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(marketplaceNotificationClientProvider)?.auth.currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Connectez-vous pour voir vos notifications.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            onPressed: () => context.push('/notifications/preferences'),
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'Préférences',
          ),
          IconButton(
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Impossible de charger les notifications.'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final items =
              snapshot.data ?? const <Map<String, dynamic>>[];

          if (items.isEmpty) {
            return const Center(
              child: Text('Aucune notification.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final item = items[index];
              final unread = item['read_at'] == null;

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      unread
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none_outlined,
                    ),
                  ),
                  title: Text(
                    item['title']?.toString() ?? 'Notification',
                    style: TextStyle(
                      fontWeight:
                          unread ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    '${item['body']?.toString() ?? ''}\n${item['created_at']?.toString() ?? ''}',
                  ),
                  onTap: unread
                      ? () => _markRead(item['id'].toString())
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

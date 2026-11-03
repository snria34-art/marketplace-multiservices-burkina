import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/providers/repository_providers.dart';

class AdminReviewModerationPage extends ConsumerStatefulWidget {
  const AdminReviewModerationPage({super.key});

  @override
  ConsumerState<AdminReviewModerationPage> createState() =>
      _AdminReviewModerationPageState();
}

class _AdminReviewModerationPageState
    extends ConsumerState<AdminReviewModerationPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification administrateur requise.');
    }
    final raw = await client.rpc(
      'admin_get_review_moderation_queue',
      params: {'p_limit': 100},
    );
    final result = <Map<String, dynamic>>[];
    for (final rawRow in (raw is List ? raw : const [])) {
      final row = Map<String, dynamic>.from(rawRow as Map);
      final media = row['media'] is List ? row['media'] as List : const [];
      final signed = <Map<String, dynamic>>[];
      for (final rawMedia in media) {
        final item = Map<String, dynamic>.from(rawMedia as Map);
        final path = item['storage_path']?.toString();
        if (path != null && path.isNotEmpty) {
          try {
            item['signed_url'] = await client.storage
                .from('order-feedback-media')
                .createSignedUrl(path, 300);
          } catch (_) {}
        }
        signed.add(item);
      }
      row['media'] = signed;
      result.add(row);
    }
    return result;
  }

  Future<void> _decide(Map<String, dynamic> review, String decision) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(decision == 'PUBLISHED' ? 'Publier cet avis' : 'Refuser cet avis'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motif de la décision',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 3) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) throw StateError('Service indisponible.');
      await client.rpc('admin_decide_review', params: {
        'p_review_id': review['review_id'],
        'p_decision': decision,
        'p_note': note,
      });
      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Décision enregistrée.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Décision impossible : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modération des avis'),
        actions: [
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
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Accès impossible : ${snapshot.error}\n\n'
                  'Un compte administrateur actif est nécessaire.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('Aucun avis en attente.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final media = row['media'] as List? ?? const [];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['product_name']?.toString() ?? 'Produit',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Boutique : ${row['shop_name'] ?? '-'}'),
                      Text('Client : ${row['customer_name'] ?? '-'}'),
                      Text('Note : ${row['rating'] ?? '-'} / 5'),
                      const SizedBox(height: 8),
                      Text(row['body']?.toString() ?? ''),
                      if (media.isNotEmpty) ...[
                        const Divider(),
                        const Text('Photos et vidéos jointes'),
                        ...media.map((rawMedia) {
                          final item = Map<String, dynamic>.from(rawMedia as Map);
                          final url = item['signed_url']?.toString();
                          if (url == null || url.isEmpty) {
                            return const Text('Média indisponible.');
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _ReviewMediaPreview(
                              url: url,
                              isVideo: item['media_type'] == 'VIDEO',
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () => _decide(row, 'PUBLISHED'),
                            child: const Text('Publier'),
                          ),
                          FilledButton(
                            onPressed: () => _decide(row, 'HIDDEN'),
                            child: const Text('Refuser'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReviewMediaPreview extends StatefulWidget {
  const _ReviewMediaPreview({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  @override
  State<_ReviewMediaPreview> createState() => _ReviewMediaPreviewState();
}

class _ReviewMediaPreviewState extends State<_ReviewMediaPreview> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVideo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          widget.url,
          height: 180,
          width: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('Photo indisponible.'),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(),
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              controller.value.isPlaying ? controller.pause() : controller.play();
            });
          },
          icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
        ),
      ],
    );
  }
}

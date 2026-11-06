import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/providers/repository_providers.dart';

class AdminCatalogModerationPage extends ConsumerStatefulWidget {
  const AdminCatalogModerationPage({super.key});

  @override
  ConsumerState<AdminCatalogModerationPage> createState() =>
      _AdminCatalogModerationPageState();
}

class _AdminCatalogModerationPageState
    extends ConsumerState<AdminCatalogModerationPage> {
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
      'admin_get_catalog_moderation_queue',
      params: {'p_limit': 100},
    );
    final rows = raw is List ? raw : const [];
    final result = <Map<String, dynamic>>[];
    for (final rawRow in rows) {
      final row = Map<String, dynamic>.from(rawRow as Map);
      final images = row['images'] is List ? row['images'] as List : const [];
      final signedImages = <String>[];
      for (final rawImage in images) {
        final image = Map<String, dynamic>.from(rawImage as Map);
        final path = image['storage_path']?.toString();
        if (path == null || path.isEmpty) continue;
        try {
          final signed = await client.storage
              .from('product-media')
              .createSignedUrl(path, 300);
          signedImages.add(signed);
        } catch (_) {
          // The finding remains visible even if a media URL cannot be signed.
        }
      }
      row['signed_images'] = signedImages;
      final response = row['latest_seller_response'];
      if (response is Map) {
        final path = response['media_storage_path']?.toString();
        if (path != null && path.isNotEmpty) {
          try {
            row['seller_response_media_url'] = await client.storage
                .from('order-feedback-media')
                .createSignedUrl(path, 300);
          } catch (_) {}
        }
      }
      result.add(row);
    }
    return result;
  }

  Future<void> _decide(
    Map<String, dynamic> finding,
    String decision,
  ) async {
    final controller = TextEditingController();
    final title = switch (decision) {
      'REQUEST_INFO' => 'Demander des explications au vendeur',
      'CLEAR' => 'Autoriser cette annonce',
      _ => 'Refuser cette annonce',
    };
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Motif ou explication à transmettre',
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
    if (!mounted || note == null) return;

    try {
      final client = ref.read(supabaseProvider);
      if (client == null) throw StateError('Service indisponible.');
      await client.rpc('admin_decide_catalog_finding', params: {
        'p_finding_id': finding['finding_id'],
        'p_decision': decision,
        'p_note': note,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Décision enregistrée.')),
      );
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Décision refusée : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modération des annonces'),
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
                  'Vérifiez que votre compte possède un rôle administrateur actif.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('Aucune annonce à examiner.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final row = rows[index];
              final product = row['product'] is Map
                  ? Map<String, dynamic>.from(row['product'] as Map)
                  : const <String, dynamic>{};
              final shop = row['shop'] is Map
                  ? Map<String, dynamic>.from(row['shop'] as Map)
                  : const <String, dynamic>{};
              final images = row['signed_images'] is List
                  ? (row['signed_images'] as List).whereType<String>().toList()
                  : const <String>[];
              final response = row['latest_seller_response'] is Map
                  ? Map<String, dynamic>.from(row['latest_seller_response'] as Map)
                  : null;
              final ai = row['ai_analysis'] is Map
                  ? Map<String, dynamic>.from(row['ai_analysis'] as Map)
                  : null;
              final restriction = row['active_listing_restriction'] is Map
                  ? Map<String, dynamic>.from(row['active_listing_restriction'] as Map)
                  : null;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name']?.toString() ?? 'Annonce',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('Boutique : ${shop['name'] ?? '-'}'),
                      Text('Vendeur : ${shop['seller_name'] ?? '-'}'),
                      Text('Règle : ${row['rule_code'] ?? '-'} • Niveau : ${row['severity'] ?? '-'}'),
                      if (restriction != null)
                        Text(
                          'Restriction active : ${restriction['reason'] ?? restriction['restriction_type'] ?? 'Annonce temporairement masquée'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      Text('Éléments détectés : ${(row['matched_terms'] as List? ?? const []).join(', ')}'),
                      if (row['ai_model'] != null)
                        Text('Analyse IA : ${row['ai_model']} • confiance ${row['ai_confidence'] ?? '-'}'),
                      if (ai != null) ...[
                        Text('Correspondance image/description : ${ai['image_description_match'] == true ? 'Oui' : 'À vérifier'}'),
                        Text('Emballage visible : ${ai['packaging_observed'] == true ? 'Oui' : 'Non / illisible'}'),
                      ] else
                        const Text('Analyse IA : en attente ou non configurée.'),
                      if ((product['description']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(product['description'].toString()),
                      ],
                      if (images.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 112,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: images.map((url) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  width: 112,
                                  height: 112,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(
                                    width: 112,
                                    child: Center(child: Icon(Icons.broken_image_outlined)),
                                  ),
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                      ],
                      if (response != null) ...[
                        const Divider(height: 20),
                        const Text('Réponse du vendeur', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(response['response_text']?.toString() ?? ''),
                        if (row['seller_response_media_url'] is String)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _ModerationMediaPreview(
                              url: row['seller_response_media_url'].toString(),
                              isVideo: response['media_type'] == 'VIDEO',
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _decide(row, 'REQUEST_INFO'),
                            child: const Text('Demander explications'),
                          ),
                          FilledButton.tonal(
                            onPressed: () => _decide(row, 'CLEAR'),
                            child: const Text('Autoriser'),
                          ),
                          FilledButton(
                            onPressed: () => _decide(row, 'REJECT'),
                            child: const Text('Refuser / retirer'),
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


class _ModerationMediaPreview extends StatefulWidget {
  const _ModerationMediaPreview({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  @override
  State<_ModerationMediaPreview> createState() => _ModerationMediaPreviewState();
}

class _ModerationMediaPreviewState extends State<_ModerationMediaPreview> {
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
          height: 160,
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

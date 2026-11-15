import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/providers/repository_providers.dart';

class SellerReviewsPage extends ConsumerStatefulWidget {
  const SellerReviewsPage({super.key});

  @override
  ConsumerState<SellerReviewsPage> createState() => _SellerReviewsPageState();
}

class _SellerReviewsPageState extends ConsumerState<SellerReviewsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(supabaseProvider);
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Authentification requise.');
    }

    final sellers = await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .limit(1);
    if ((sellers as List).isEmpty) throw StateError('Vendeur introuvable.');

    final sellerId = (sellers.first as Map)['id'].toString();
    final shops = await client
        .from('shops')
        .select('id')
        .eq('seller_id', sellerId);

    final shopIds = (shops as List)
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .toList();
    if (shopIds.isEmpty) return const [];

    final rows = await client
        .from('reviews')
        .select(
          'id,rating,body,issue_codes,created_at,product_id,products(name),shop_id',
        )
        .inFilter('shop_id', shopIds)
        .order('created_at', ascending: false)
        .limit(200);

    final result = <Map<String, dynamic>>[];
    for (final rawRow in rows as List) {
      final row = Map<String, dynamic>.from(rawRow as Map);
      final mediaRaw = await client.rpc(
        'get_public_review_media',
        params: {'p_review_id': row['id']},
      );
      final media = <Map<String, dynamic>>[];
      for (final rawMedia in (mediaRaw is List ? mediaRaw : const [])) {
        final item = Map<String, dynamic>.from(rawMedia as Map);
        final path = item['storage_path']?.toString();
        if (path != null && path.isNotEmpty) {
          try {
            item['signed_url'] = await client.storage
                .from('order-feedback-media')
                .createSignedUrl(path, 300);
          } catch (_) {}
        }
        media.add(item);
      }
      row['media'] = media;
      result.add(row);
    }
    return result;
  }

  String _issueLabel(dynamic code) {
    const labels = {
      'NOT_AS_DESCRIBED': 'Différent de l’image',
      'DAMAGED': 'Endommagé',
      'WRONG_ITEM': 'Mauvais article',
      'MISSING_PARTS': 'Pièce manquante',
      'QUALITY_ISSUE': 'Qualité insuffisante',
      'PACKAGING_ISSUE': 'Emballage abîmé',
      'OTHER': 'Autre',
    };
    return labels[code.toString()] ?? code.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avis clients'),
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
            return Center(child: Text('Erreur : ' + snapshot.error.toString()));
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return const Center(child: Text('Aucun avis publié pour vos boutiques.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final row = rows[index];
              final product = row['products'] is Map
                  ? Map<String, dynamic>.from(row['products'] as Map)
                  : const <String, dynamic>{};
              final media = row['media'] as List? ?? const [];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            child: Text(row['rating']?.toString() ?? '-'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              product['name']?.toString() ?? 'Produit',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(row['body']?.toString() ?? ''),
                      if ((row['issue_codes'] as List? ?? const []).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Problèmes signalés : ${(row['issue_codes'] as List).map(_issueLabel).join(', ')}',
                          ),
                        ),
                      if (media.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Médias joints par le client'),
                        ...media.map((rawMedia) {
                          final item = Map<String, dynamic>.from(rawMedia as Map);
                          final url = item['signed_url']?.toString();
                          if (url == null || url.isEmpty) {
                            return const Text('Média indisponible.');
                          }
                          return _SellerReviewMedia(
                            url: url,
                            isVideo: item['media_type'] == 'VIDEO',
                          );
                        }),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          row['created_at']?.toString() ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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


class _SellerReviewMedia extends StatefulWidget {
  const _SellerReviewMedia({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  @override
  State<_SellerReviewMedia> createState() => _SellerReviewMediaState();
}

class _SellerReviewMediaState extends State<_SellerReviewMedia> {
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
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            widget.url,
            height: 160,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text('Photo indisponible.'),
          ),
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

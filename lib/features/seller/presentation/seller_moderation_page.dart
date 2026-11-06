import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/providers/repository_providers.dart';

class SellerModerationPage extends ConsumerStatefulWidget {
  const SellerModerationPage({super.key});

  @override
  ConsumerState<SellerModerationPage> createState() => _SellerModerationPageState();
}

class _SellerModerationPageState extends ConsumerState<SellerModerationPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Authentification requise.');
    }
    final raw = await client.rpc('get_seller_catalog_findings');
    return (raw is List ? raw : const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _respond(Map<String, dynamic> finding) async {
    final controller = TextEditingController();
    XFile? media;
    String? mediaType;
    num? durationSeconds;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Répondre à l’administration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                onChanged: (_) => setDialogState(() {}),
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Expliquez pourquoi le produit est proposé',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final picked = await ImagePicker().pickImage(
                          source: ImageSource.camera,
                          imageQuality: 75,
                          maxWidth: 1600,
                        );
                        if (picked != null && context.mounted) {
                          setDialogState(() {
                            media = picked;
                            mediaType = 'IMAGE';
                            durationSeconds = null;
                          });
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Capture photo impossible : $error',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final picked = await ImagePicker().pickVideo(
                          source: ImageSource.gallery,
                          maxDuration: const Duration(seconds: 10),
                        );
                        if (picked == null || !context.mounted) return;

                        final videoController =
                            VideoPlayerController.file(File(picked.path));
                        try {
                          await videoController.initialize();
                          final seconds =
                              videoController.value.duration.inMilliseconds /
                                  1000;
                          if (seconds <= 0 || seconds > 10) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'La vidéo doit durer 10 secondes maximum.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          if (!context.mounted) return;
                          setDialogState(() {
                            media = picked;
                            mediaType = 'VIDEO';
                            durationSeconds = seconds;
                          });
                        } finally {
                          await videoController.dispose();
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Lecture de la vidéo impossible : $error',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Vidéo (10 s)'),
                  ),
                ],
              ),
              if (media != null) Text(media!.name),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: controller.text.trim().length >= 5
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Envoyer la réponse'),
            ),
          ],
        ),
      ),
    );
    final message = controller.text.trim();
    controller.dispose();
    if (!mounted || result != true) return;

    String? mediaPath;
    SupabaseClient? uploadClient;
    try {
      final client = ref.read(supabaseProvider);
      uploadClient = client;
      final user = client?.auth.currentUser;
      if (client == null || user == null) throw StateError('Session indisponible.');
      if (media != null) {
        final maxBytes = mediaType == 'VIDEO' ? 20 * 1024 * 1024 : 5 * 1024 * 1024;
        final fileSize = await media!.length();
        if (fileSize <= 0 || fileSize > maxBytes) {
          throw StateError(mediaType == 'VIDEO'
              ? 'La vidéo doit faire au maximum 20 Mo.'
              : 'La photo doit faire au maximum 5 Mo.');
        }
        final bytes = await media!.readAsBytes();
        if (bytes.isEmpty || bytes.length > maxBytes) {
          throw StateError(mediaType == 'VIDEO'
              ? 'La vidéo doit faire au maximum 20 Mo.'
              : 'La photo doit faire au maximum 5 Mo.');
        }
        final sourceExtension = media!.name.contains('.')
            ? media!.name.split('.').last.toLowerCase()
            : '';
        const mimeByExtension = {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'webp': 'image/webp',
          'heic': 'image/heic',
          'mp4': 'video/mp4',
          'mov': 'video/quicktime',
        };
        const extensionByMime = {
          'image/jpeg': 'jpg',
          'image/png': 'png',
          'image/webp': 'webp',
          'image/heic': 'heic',
          'video/mp4': 'mp4',
          'video/quicktime': 'mov',
        };
        final mime =
            media!.mimeType?.toLowerCase() ?? mimeByExtension[sourceExtension];
        final allowedMimes = mediaType == 'VIDEO'
            ? const {'video/mp4', 'video/quicktime'}
            : const {
                'image/jpeg',
                'image/png',
                'image/webp',
                'image/heic',
              };
        if (mime == null || !allowedMimes.contains(mime)) {
          throw StateError('Format du média non pris en charge.');
        }
        final extension = extensionByMime[mime]!;
        mediaPath = '${user.id}/moderation/${finding['finding_id']}_${DateTime.now().microsecondsSinceEpoch}.$extension';
        await client.storage.from('order-feedback-media').uploadBinary(
          mediaPath,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
      }
      await client.rpc('seller_respond_to_catalog_finding', params: {
        'p_finding_id': finding['finding_id'],
        'p_response_text': message,
        'p_media_storage_path': mediaPath,
        'p_media_type': mediaType,
        'p_duration_seconds': durationSeconds,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Réponse envoyée à l’administration.')),
      );
      setState(() => _future = _load());
    } catch (error) {
      if (mediaPath != null && uploadClient != null) {
        try {
          await uploadClient.storage
              .from('order-feedback-media')
              .remove([mediaPath]);
        } catch (_) {
          // Best-effort cleanup; preserve the original submission error.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Envoi impossible : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrôle de mes annonces'),
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
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('Aucune demande d’explication en cours.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final status = row['status']?.toString() ?? '';
              final responses = row['seller_responses'] is List
                  ? row['seller_responses'] as List
                  : const [];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['product_name']?.toString() ?? 'Annonce',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Boutique : ${row['shop_name'] ?? '-'}'),
                      Text('Motif : ${row['explanation'] ?? '-'}'),
                      Text('État : $status'),
                      if (responses.isNotEmpty) ...[
                        const Divider(),
                        const Text('Votre dernière réponse :'),
                        Text((responses.first as Map)['response_text']?.toString() ?? ''),
                      ],
                      if (status == 'UNDER_REVIEW')
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () => _respond(row),
                            icon: const Icon(Icons.reply_outlined),
                            label: const Text('Répondre avec explication'),
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

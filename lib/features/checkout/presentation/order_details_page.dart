import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/video_preview_controller_factory.dart';
import '../../../core/providers/repository_providers.dart';

class OrderDetailsPage extends ConsumerStatefulWidget {
  const OrderDetailsPage({required this.orderId, super.key});

  final String orderId;

  @override
  ConsumerState<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends ConsumerState<OrderDetailsPage> {
  late Future<_OrderDetails> _future;
  RealtimeChannel? _orderChannel;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _startRealtime();
  }

  Future<void> _startRealtime() async {
    final client = ref.read(supabaseProvider);
    if (client == null || client.auth.currentUser == null) return;

    // Packages are linked to an order through order_groups. Resolve the group
    // IDs once so package events can be scoped to this order, not every order
    // visible to the current customer.
    final orderGroupIds = <String>[];
    try {
      final rows = await client
          .from('order_groups')
          .select('id')
          .eq('order_id', widget.orderId);
      for (final row in rows as List) {
        final id = (row as Map)['id']?.toString();
        if (id != null && id.isNotEmpty) orderGroupIds.add(id);
      }
    } catch (_) {
      // The order and payment subscriptions below remain useful even if the
      // optional package subscription cannot be prepared.
    }

    if (!mounted) return;

    try {
      var channel = client
          .channel('order-payment-' + widget.orderId)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'order_id',
              value: widget.orderId,
            ),
            callback: (_) {
              if (!mounted) return;
              setState(() => _future = _load());
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.orderId,
            ),
            callback: (_) {
              if (!mounted) return;
              setState(() => _future = _load());
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_groups',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'order_id',
              value: widget.orderId,
            ),
            callback: (_) {
              if (!mounted) return;
              setState(() => _future = _load());
            },
          );

      for (final groupId in orderGroupIds) {
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_packages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_group_id',
            value: groupId,
          ),
          callback: (_) {
            if (!mounted) return;
            setState(() => _future = _load());
          },
        );
      }

      _orderChannel = channel.subscribe();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Actualisation instantanée indisponible : $error. Utilisez Actualiser pour vérifier l’état.',
          ),
        ),
      );
    }
  }

  Future<void> _removeOrderChannelSafely(
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
    final client = ref.read(supabaseProvider);
    final channel = _orderChannel;
    _orderChannel = null;
    if (client != null && channel != null) {
      unawaited(_removeOrderChannelSafely(client, channel));
    }
    super.dispose();
  }

  Future<_OrderDetails> _load() async {
    final client = ref.read(supabaseProvider);
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Authentification requise.');
    }

    final order = await client
        .from('orders')
        .select(
          'id,status,subtotal,delivery_fee,discount_total,total,currency,delivery_address,created_at,review_deadline_at,completed_at',
        )
        .eq('id', widget.orderId)
        .eq('customer_id', user.id)
        .single();

    final groups = await client
        .from('order_groups')
        .select(
          'id,shop_id,status,subtotal,shops(name),order_items(id,product_id,product_name,quantity,unit_price,total_price)',
        )
        .eq('order_id', widget.orderId)
        .order('created_at');

    final returns = await client
        .from('returns')
        .select('id,order_item_id,reason,status,resolution,created_at')
        .eq('order_id', widget.orderId)
        .order('created_at', ascending: false);

    final disputes = await client
        .from('disputes')
        .select('id,reason,status,resolution,created_at,resolved_at')
        .eq('order_id', widget.orderId)
        .order('created_at', ascending: false);

    final refundRows = await client.rpc(
      'get_customer_refunds',
      params: {'p_order_id': widget.orderId},
    );

    final refunds = refundRows is List
        ? refundRows
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList()
        : const <Map<String, dynamic>>[];

    final paymentRows = await client.rpc(
      'get_customer_payment_status',
      params: {'p_order_id': widget.orderId},
    );

    final payment = paymentRows is List && paymentRows.isNotEmpty
        ? Map<String, dynamic>.from(paymentRows.first as Map)
        : null;

    final evidenceRaw = await client.rpc(
      'get_customer_delivery_evidence',
      params: {'p_order_id': widget.orderId},
    );
    final deliveryEvidence = <Map<String, dynamic>>[];
    if (evidenceRaw is List) {
      for (final rawEvidence in evidenceRaw) {
        final evidence = Map<String, dynamic>.from(rawEvidence as Map);
        final path = evidence['storage_path']?.toString();
        if (path != null && path.isNotEmpty) {
          try {
            evidence['signed_url'] = await client.storage
                .from('order-feedback-media')
                .createSignedUrl(path, 300);
          } catch (_) {}
        }
        deliveryEvidence.add(evidence);
      }
    }

    return _OrderDetails(
      order: Map<String, dynamic>.from(order),
      groups: (groups as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
      returns: (returns as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
      disputes: (disputes as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
      refunds: refunds,
      payment: payment,
      deliveryEvidence: deliveryEvidence,
    );
  }

  Future<void> _resumePayment(Map<String, dynamic>? payment) async {
    final provider = payment?['provider']?.toString();
    final selected = provider == 'WAVE' || provider == 'CINETPAY'
        ? provider
        : await showDialog<String>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: const Text('Choisir le paiement'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, 'CINETPAY'),
                  child: const Text('Orange Money / Moov Money'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, 'WAVE'),
                  child: const Text('Wave'),
                ),
              ],
            ),
          );
    if (!mounted || selected == null) return;

    try {
      final repo = ref.read(checkoutRepositoryProvider);
      if (repo == null) throw StateError('Service de paiement indisponible.');
      final session = await repo.createPaymentSession(
        orderId: widget.orderId,
        provider: selected,
      );
      if (!mounted) return;

      final url = session['checkout_url']?.toString().trim();
      if (url == null || url.isEmpty) {
        throw StateError('Lien de paiement indisponible.');
      }
      final paymentUri = Uri.tryParse(url);
      if (paymentUri == null ||
          paymentUri.scheme.toLowerCase() != 'https' ||
          paymentUri.host.isEmpty ||
          paymentUri.userInfo.isNotEmpty) {
        throw StateError(
          'Adresse de paiement invalide : une URL HTTPS sécurisée est requise.',
        );
      }
      final opened = await launchUrl(
        paymentUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Impossible d’ouvrir le guichet.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guichet de paiement ouvert.')),
      );
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paiement impossible : ' + error.toString())),
      );
    }
  }
  Future<void> _requestRefund(num maxAmount) async {
    final amountController = TextEditingController(text: maxAmount.toString());
    final reasonController = TextEditingController();
    final values = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Demander un remboursement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant (XOF)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Motif'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    final amount = num.tryParse(amountController.text.trim());
    final reason = reasonController.text.trim();
    amountController.dispose();
    reasonController.dispose();
    if (!mounted || values != true || amount == null || amount <= 0 || amount > maxAmount) return;

    try {
      final client = ref.read(supabaseProvider);
      if (client == null) throw StateError('Service indisponible.');
      await client.rpc('request_refund', params: {
        'p_order_id': widget.orderId,
        'p_amount': amount,
        'p_reason': reason.isEmpty ? null : reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande de remboursement envoyée.')),
      );
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remboursement refusé : ' + error.toString())),
      );
    }
  }
  Future<void> _openDispute() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ouvrir un litige'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Motif',
            hintText: 'Expliquez le problème rencontré...',
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
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || reason == null) return;

    try {
      final client = ref.read(supabaseProvider);
      if (client == null) throw StateError('Service indisponible.');
      final id = await client.rpc(
        'open_dispute',
        params: {
          'p_order_id': widget.orderId,
          'p_reason': reason,
          'p_against_user_id': null,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Litige créé : ' + id.toString())),
      );
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Litige refusé : ' + error.toString())));
    }
  }

  Future<void> _openReturn(String itemId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Demander un retour'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Motif du retour',
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
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || reason == null) return;

    try {
      final client = ref.read(supabaseProvider);
      if (client == null) throw StateError('Service indisponible.');
      final id = await client.rpc(
        'open_return',
        params: {
          'p_order_id': widget.orderId,
          'p_order_item_id': itemId,
          'p_reason': reason,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retour demandé : ' + id.toString())),
      );
      setState(() => _future = _load());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Retour refusé : ' + error.toString())));
    }
  }

  Future<void> _review(String productId, String shopId) async {
    final form = await showDialog<_ReviewForm>(
      context: context,
      builder: (_) => const _ReviewDialog(),
    );
    if (!mounted || form == null) return;

    final client = ref.read(supabaseProvider);
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      _showReviewMessage('Session indisponible. Votre avis n’a pas été envoyé.');
      return;
    }

    Uint8List? mediaBytes;
    if (form.media != null) {
      final maxBytes = form.mediaType == 'VIDEO'
          ? 20 * 1024 * 1024
          : 5 * 1024 * 1024;
      final fileSize = await form.media!.length();
      if (fileSize <= 0 || fileSize > maxBytes) {
        _showReviewMessage(
          form.mediaType == 'VIDEO'
              ? 'La vidéo doit faire au maximum 20 Mo.'
              : 'La photo doit faire au maximum 5 Mo.',
        );
        return;
      }
      mediaBytes = await form.media!.readAsBytes();
      if (mediaBytes.isEmpty || mediaBytes.length > maxBytes) {
        _showReviewMessage(
          form.mediaType == 'VIDEO'
              ? 'La vidéo doit faire au maximum 20 Mo.'
              : 'La photo doit faire au maximum 5 Mo.',
        );
        return;
      }
    }

    dynamic createdReviewId;
    String? uploadedPath;
    try {
      createdReviewId = await client.rpc(
        'create_review',
        params: {
          'p_product_id': productId,
          'p_shop_id': shopId,
          'p_rating': form.rating,
          'p_body': form.body,
          'p_issue_codes': form.issueCodes,
        },
      );

      if (form.media != null && mediaBytes != null) {
        final sourceExtension = form.media!.name.contains('.')
            ? form.media!.name.split('.').last.toLowerCase()
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
        final mime = form.media!.mimeType?.toLowerCase() ??
            mimeByExtension[sourceExtension];
        final allowedMimes = form.mediaType == 'VIDEO'
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
        uploadedPath =
            user.id + '/reviews/' + createdReviewId.toString() + '_' +
            DateTime.now().microsecondsSinceEpoch.toString() + '.' + extension;
        await client.storage.from('order-feedback-media').uploadBinary(
          uploadedPath,
          mediaBytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
        await client.rpc('attach_review_media', params: {
          'p_review_id': createdReviewId.toString(),
          'p_storage_path': uploadedPath,
          'p_media_type': form.mediaType,
          'p_duration_seconds': form.durationSeconds,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Avis envoyé pour modération' +
                (form.media == null ? '.' : ' avec média.'),
          ),
        ),
      );
    } catch (error) {
      if (uploadedPath != null) {
        try {
          await client.storage.from('order-feedback-media').remove([uploadedPath]);
        } catch (_) {}
      }
      if (!mounted) return;
      final message = createdReviewId != null
          ? 'Avis enregistré, mais le média n’a pas pu être associé. Contactez le support si nécessaire.'
          : 'Avis non envoyé : ' + error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _statusLabel(String? raw) {
    switch (raw) {
      case 'PENDING_PAYMENT':
        return 'Paiement en attente';
      case 'PAID':
        return 'Paiement confirmé';
      case 'CONFIRMED':
        return 'Commande confirmée';
      case 'PREPARING':
        return 'En cours de préparation';
      case 'READY_FOR_PICKUP':
        return 'Prête à être récupérée';
      case 'PARTIALLY_FULFILLED':
        return 'Commande partiellement traitée';
      case 'IN_TRANSIT':
        return 'En cours de livraison';
      case 'DELIVERED':
        return 'Livrée';
      case 'CANCELLED':
        return 'Annulée';
      case 'REFUNDED':
        return 'Remboursée';
      case 'DISPUTED':
        return 'En litige';
      default:
        return (raw ?? 'Statut inconnu').replaceAll('_', ' ');
    }
  }

  void _showReviewMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de la commande'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_OrderDetails>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Erreur : ' + snapshot.error.toString()),
              ),
            );
          }

          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();

          final order = data.order;
          final status = order['status']?.toString() ?? '-';
          final delivered = status == 'DELIVERED';
          final reviewDeadline = DateTime.tryParse(order['review_deadline_at']?.toString() ?? '');
          final reviewOpen = delivered && reviewDeadline != null && DateTime.now().isBefore(reviewDeadline);
          final displayStatus = order['completed_at'] != null ? 'Commande terminée' : _statusLabel(status);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.receipt_long_outlined),
                  ),
                  title: Text(widget.orderId),
                  subtitle: Text(
                    displayStatus + ' • ' + (order['created_at']?.toString() ?? ''),
                  ),
                  trailing: Text(
                    (order['total']?.toString() ?? '0') +
                        ' ' +
                        (order['currency']?.toString() ?? 'XOF'),
                  ),
                ),
              ),
              if (data.payment != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payment_outlined),
                    title: const Text('Paiement'),
                    subtitle: Text(
                      (data.payment!['provider']?.toString() ?? '-') +
                          ' • ' +
                          (data.payment!['status']?.toString() ?? '-'),
                    ),
                    trailing: Text(
                      (data.payment!['amount']?.toString() ?? '0') +
                          ' ' +
                          (data.payment!['currency']?.toString() ?? 'XOF'),
                    ),
                  ),
                ),
              if (status == 'PENDING_PAYMENT') ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _resumePayment(data.payment),
                  icon: const Icon(Icons.payment_outlined),
                  label: const Text('Reprendre le paiement'),
                ),
              ],
              if ((order['delivery_address'] as dynamic) != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Adresse de livraison'),
                    subtitle: Text(order['delivery_address'].toString()),
                  ),
                ),
              for (final group in data.groups) ...[
                const SizedBox(height: 8),
                Card(
                  child: ExpansionTile(
                    title: Text(
                      group['shops'] is Map
                          ? (group['shops']['name']?.toString() ?? 'Boutique')
                          : 'Boutique',
                    ),
                    subtitle: Text(
                      _statusLabel(group['status']?.toString()) +
                          ' • ' + (group['subtotal']?.toString() ?? '0') + ' XOF',
                    ),
                    children: [
                      ..._items(
                        group: group,
                        delivered: group['status']?.toString() == 'DELIVERED',
                        reviewOpen: reviewOpen,
                        onReturn: _openReturn,
                        onReview: _review,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (status != 'CANCELLED' &&
                  status != 'REFUNDED' &&
                  status != 'PENDING_PAYMENT')
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/delivery/' + widget.orderId),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Suivre la livraison'),
                ),
              if (reviewDeadline != null && delivered) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: Text(reviewOpen ? 'Avis possible jusqu’au' : 'Délai d’avis terminé'),
                    subtitle: Text(reviewDeadline.toLocal().toString()),
                  ),
                ),
              ],
              if (data.deliveryEvidence.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Preuve de remise du colis',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...data.deliveryEvidence.map((evidence) {
                  final url = evidence['signed_url']?.toString();
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Photo du colis livré'),
                          if (url != null && url.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Text('Photo indisponible.'),
                              ),
                            )
                          else
                            const Text('Photo indisponible.'),
                          Text(evidence['created_at']?.toString() ?? ''),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              if (delivered) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openDispute,
                  icon: const Icon(Icons.gavel_outlined),
                  label: const Text('Ouvrir un litige'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _requestRefund(
                    num.tryParse(order['total']?.toString() ?? '0') ?? 0,
                  ),
                  icon: const Icon(Icons.currency_exchange_outlined),
                  label: const Text('Demander un remboursement'),
                ),
              ],
              if (data.returns.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Retours',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...data.returns.map(
                  (row) => ListTile(
                    leading: const Icon(Icons.assignment_return_outlined),
                    title: Text(row['reason']?.toString() ?? '-'),
                    subtitle: Text(row['status']?.toString() ?? '-'),
                  ),
                ),
              ],
              if (data.refunds.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Remboursements',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...data.refunds.map(
                  (row) => ListTile(
                    leading: const Icon(Icons.currency_exchange_outlined),
                    title: Text(
                      (row['amount']?.toString() ?? '0') +
                          ' ' +
                          (row['currency']?.toString() ?? 'XOF'),
                    ),
                    subtitle: Text(
                      (row['status']?.toString() ?? '-') +
                          ' • ' +
                          (row['reason']?.toString() ?? ''),
                    ),
                  ),
                ),
              ],
              if (data.disputes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Litiges',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...data.disputes.map(
                  (row) => ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: Text(row['reason']?.toString() ?? '-'),
                    subtitle: Text(row['status']?.toString() ?? '-'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _items({
    required Map<String, dynamic> group,
    required bool delivered,
    required bool reviewOpen,
    required Future<void> Function(String itemId) onReturn,
    required Future<void> Function(String productId, String shopId) onReview,
  }) {
    final raw = group['order_items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : const <Map<String, dynamic>>[];

    final shopId = group['shop_id']?.toString() ?? '';

    return items.map((item) {
      final itemId = item['id']?.toString() ?? '';
      final productId = item['product_id']?.toString() ?? '';

      return ListTile(
        title: Text(item['product_name']?.toString() ?? 'Article'),
        subtitle: Text(
          'Quantité : ' +
              (item['quantity']?.toString() ?? '0') +
              ' • ' +
              (item['total_price']?.toString() ?? '0') +
              ' XOF',
        ),
        trailing: delivered
            ? Wrap(
                spacing: 4,
                children: [
                  if (reviewOpen)
                    TextButton.icon(
                      onPressed: productId.isNotEmpty && shopId.isNotEmpty
                          ? () => onReview(productId, shopId)
                          : null,
                      icon: const Icon(Icons.star_outline, size: 18),
                      label: const Text('Noter'),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'return' && itemId.isNotEmpty) {
                        onReturn(itemId);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'return',
                        child: Text('Demander un retour'),
                      ),
                    ],
                  ),
                ],
              )
            : null,
      );
    }).toList();
  }
}

class _OrderDetails {
  const _OrderDetails({
    required this.order,
    required this.groups,
    required this.returns,
    required this.disputes,
    required this.payment,
    required this.refunds,
    required this.deliveryEvidence,
  });

  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> returns;
  final List<Map<String, dynamic>> disputes;
  final Map<String, dynamic>? payment;
  final List<Map<String, dynamic>> refunds;
  final List<Map<String, dynamic>> deliveryEvidence;
}

class _ReviewForm {
  const _ReviewForm({
    required this.rating,
    required this.body,
    this.media,
    this.mediaType,
    this.durationSeconds,
    required this.issueCodes,
  });

  final int rating;
  final String body;
  final List<String> issueCodes;
  final XFile? media;
  final String? mediaType;
  final num? durationSeconds;
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int rating = 5;
  final body = TextEditingController();
  XFile? media;
  String? mediaType;
  num? durationSeconds;
  final Set<String> issueCodes = {};

  void _toggleIssue(String code, bool selected) {
    if (selected && issueCodes.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous pouvez signaler au maximum 5 problèmes.')),
      );
      return;
    }
    setState(() {
      selected ? issueCodes.add(code) : issueCodes.remove(code);
    });
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (!mounted || picked == null) return;
      setState(() {
        media = picked;
        mediaType = 'IMAGE';
        durationSeconds = null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sélection de la photo impossible : $error')),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 10),
      );
      if (!mounted || picked == null) return;

      final videoController = createVideoPreviewController(picked);
      try {
        await videoController.initialize();
        if (!mounted) return;
        final seconds =
            videoController.value.duration.inMilliseconds / 1000;
        if (seconds <= 0 || seconds > 10) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La vidéo doit durer 10 secondes maximum.'),
            ),
          );
          return;
        }
        setState(() {
          media = picked;
          mediaType = 'VIDEO';
          durationSeconds = seconds;
        });
      } finally {
        await videoController.dispose();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sélection de la vidéo impossible : $error')),
      );
    }
  }

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Votre avis'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: rating,
            items: const [
              DropdownMenuItem(value: 5, child: Text('5 étoiles')),
              DropdownMenuItem(value: 4, child: Text('4 étoiles')),
              DropdownMenuItem(value: 3, child: Text('3 étoiles')),
              DropdownMenuItem(value: 2, child: Text('2 étoiles')),
              DropdownMenuItem(value: 1, child: Text('1 étoile')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => rating = value);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Les avis honnêtes, même négatifs, sont autorisés. Les insultes, menaces et données personnelles ne le sont pas.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Signaler un problème (facultatif)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('Différent de l’image'),
                selected: issueCodes.contains('NOT_AS_DESCRIBED'),
                onSelected: (selected) => _toggleIssue('NOT_AS_DESCRIBED', selected),
              ),
              FilterChip(
                label: const Text('Endommagé'),
                selected: issueCodes.contains('DAMAGED'),
                onSelected: (selected) => _toggleIssue('DAMAGED', selected),
              ),
              FilterChip(
                label: const Text('Mauvais article'),
                selected: issueCodes.contains('WRONG_ITEM'),
                onSelected: (selected) => _toggleIssue('WRONG_ITEM', selected),
              ),
              FilterChip(
                label: const Text('Pièce manquante'),
                selected: issueCodes.contains('MISSING_PARTS'),
                onSelected: (selected) => _toggleIssue('MISSING_PARTS', selected),
              ),
              FilterChip(
                label: const Text('Qualité insuffisante'),
                selected: issueCodes.contains('QUALITY_ISSUE'),
                onSelected: (selected) => _toggleIssue('QUALITY_ISSUE', selected),
              ),
              FilterChip(
                label: const Text('Emballage abîmé'),
                selected: issueCodes.contains('PACKAGING_ISSUE'),
                onSelected: (selected) => _toggleIssue('PACKAGING_ISSUE', selected),
              ),
              FilterChip(
                label: const Text('Autre'),
                selected: issueCodes.contains('OTHER'),
                onSelected: (selected) => _toggleIssue('OTHER', selected),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: body,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Commentaire (optionnel)',
              helperText: 'Critiquez le produit sans insultes ni propos haineux.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Photo'),
              ),
              OutlinedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Vidéo (10 s max.)'),
              ),
            ],
          ),
          if (media != null)
            Text('Média sélectionné : ${media!.name}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ReviewForm(
              rating: rating,
              body: body.text.trim(),
              media: media,
              mediaType: mediaType,
              durationSeconds: durationSeconds,
              issueCodes: issueCodes.toList(),
            ),
          ),
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}

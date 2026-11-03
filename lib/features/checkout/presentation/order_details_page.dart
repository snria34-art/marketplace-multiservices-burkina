import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/repository_providers.dart';
import '../data/checkout_repository.dart';

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

  void _startRealtime() {
    final client = ref.read(supabaseProvider);
    if (client?.auth.currentUser == null) return;

    _orderChannel = client!
        .channel('order-payment-' + widget.orderId)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          callback: (_) {
            if (!mounted) return;
            setState(() => _future = _load());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (!mounted) return;
            setState(() => _future = _load());
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final client = ref.read(supabaseProvider);
    final channel = _orderChannel;
    if (client != null && channel != null) {
      client.removeChannel(channel);
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
          'id,status,subtotal,delivery_fee,discount_total,total,currency,delivery_address,created_at',
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
    if (selected == null) return;

    try {
      final repo = ref.read(checkoutRepositoryProvider);
      if (repo == null) throw StateError('Service de paiement indisponible.');
      final session = await repo.createPaymentSession(
        orderId: widget.orderId,
        provider: selected,
      );
      final url = session['checkout_url']?.toString();
      if (url == null || url.isEmpty) {
        throw StateError('Lien de paiement indisponible.');
      }
      final opened = await launchUrl(
        Uri.parse(url),
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
    if (values != true || amount == null || amount <= 0 || amount > maxAmount) return;

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
    if (reason == null) return;

    try {
      final client = ref.read(supabaseProvider);
      final id = await client?.rpc(
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
    if (reason == null) return;

    try {
      final client = ref.read(supabaseProvider);
      final id = await client?.rpc(
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
    if (form == null) return;

    try {
      final client = ref.read(supabaseProvider);
      final id = await client?.rpc(
        'create_review',
        params: {
          'p_product_id': productId,
          'p_shop_id': shopId,
          'p_rating': form.rating,
          'p_body': form.body,
        },
      );
      final media = form.media;
      if (media != null) {
        final clientUser = client?.auth.currentUser;
        if (client == null || clientUser == null || id == null) {
          throw StateError('Avis créé, mais média non associé : session indisponible.');
        }
        final bytes = await media.readAsBytes();
        if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
          throw StateError('Avis créé, mais le média dépasse la limite de 5 Mo.');
        }
        final extension = media.name.contains('.')
            ? media.name.split('.').last.toLowerCase()
            : (form.mediaType == 'VIDEO' ? 'mp4' : 'jpg');
        final storagePath = '${clientUser.id}/reviews/${id}_${DateTime.now().microsecondsSinceEpoch}.$extension';
        final mime = media.mimeType ??
            (form.mediaType == 'VIDEO' ? 'video/mp4' : 'image/jpeg');
        await client.storage.from('order-feedback-media').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
        await client.rpc('attach_review_media', params: {
          'p_review_id': id.toString(),
          'p_storage_path': storagePath,
          'p_media_type': form.mediaType,
          'p_duration_seconds': form.durationSeconds,
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Avis envoyé pour modération' + (media == null ? '.' : ' avec média.'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Avis refusé : ' + error.toString())));
    }
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
                    status + ' • ' + (order['created_at']?.toString() ?? ''),
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
                      (group['subtotal']?.toString() ?? '0') + ' XOF',
                    ),
                    children: [
                      ..._items(
                        group: group,
                        delivered: group['status']?.toString() == 'DELIVERED',
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
  });

  final int rating;
  final String body;
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

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() {
      media = picked;
      mediaType = 'IMAGE';
      durationSeconds = null;
    });
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 10),
    );
    if (picked == null) return;
    final controller = VideoPlayerController.file(File(picked.path));
    try {
      await controller.initialize();
      final seconds = controller.value.duration.inMilliseconds / 1000;
      if (seconds <= 0 || seconds > 10) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La vidéo doit durer 10 secondes maximum.')),
          );
        }
        return;
      }
      setState(() {
        media = picked;
        mediaType = 'VIDEO';
        durationSeconds = seconds;
      });
    } finally {
      await controller.dispose();
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
            ),
          ),
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}

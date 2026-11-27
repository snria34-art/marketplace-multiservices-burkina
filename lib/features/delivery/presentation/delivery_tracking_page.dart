import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../data/delivery_repository.dart';

final deliveryRepositoryProvider = Provider<DeliveryRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : DeliveryRepository(client);
});

class DeliveryTrackingPage extends ConsumerStatefulWidget {
  const DeliveryTrackingPage({
    super.key,
    required this.orderId,
  });

  final String orderId;

  @override
  ConsumerState<DeliveryTrackingPage> createState() =>
      _DeliveryTrackingPageState();
}

class _DeliveryTrackingPageState
    extends ConsumerState<DeliveryTrackingPage> {
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _channel;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _future = _load();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscribeRealtime();

      _timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          if (!mounted) return;
          setState(() => _future = _load());
        },
      );
    });
  }

  Future<void> _subscribeRealtime() async {
    final client = ref.read(supabaseProvider);
    final repo = ref.read(deliveryRepositoryProvider);
    if (client == null || repo == null) return;

    try {
      final channel = await repo.watchOrder(
        widget.orderId,
        () {
          if (!mounted) return;
          setState(() => _future = _load());
        },
      );

      if (!mounted) {
        await client.removeChannel(channel);
        return;
      }
      _channel = channel;
    } catch (_) {
      // The existing periodic refresh remains as a fallback if Realtime
      // subscription setup is temporarily unavailable.
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    final repo = ref.read(deliveryRepositoryProvider);
    if (repo == null) return Future.value(const []);
    return repo.packagesForOrder(widget.orderId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_removeChannelSafely(channel));
    }
    super.dispose();
  }

  Future<void> _removeChannelSafely(RealtimeChannel channel) async {
    try {
      await ref.read(supabaseProvider)?.removeChannel(channel);
    } catch (_) {
      // Disposal is best-effort; no unhandled async error should escape.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi de livraison'),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_off_outlined, size: 40),
                    const SizedBox(height: 8),
                    const Text('Le suivi de livraison est momentanément indisponible.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final packages =
              snapshot.data ?? const <Map<String, dynamic>>[];

          if (packages.isEmpty) {
            return const Center(
              child: Text('Aucun colis de livraison trouvé.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: packages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final package = packages[index];
              final assignment = package['assignment'] is Map
                  ? Map<String, dynamic>.from(package['assignment'] as Map)
                  : null;
              final location = package['latest_location'] is Map
                  ? Map<String, dynamic>.from(
                      package['latest_location'] as Map,
                    )
                  : null;
              final point = location == null
                  ? null
                  : _parsePoint(location['location']);
              final packageStatus =
                  package['status']?.toString().toUpperCase() ?? '';
              final rawEvents = package['events'];
              final events = rawEvents is List
                  ? rawEvents
                      .whereType<Map>()
                      .map((event) => Map<String, dynamic>.from(event))
                      .toList()
                  : const <Map<String, dynamic>>[];

              return Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.local_shipping_outlined, size: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  package['shop_name']?.toString() ?? 'Boutique',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Colis #${_shortId(package['id']?.toString() ?? '')}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(
                                _statusIcon(packageStatus),
                                size: 16,
                              ),
                              label: Text(
                                _statusLabel(packageStatus),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: _progress(packageStatus),
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      if (assignment != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.delivery_dining_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Un livreur est affecté à votre colis.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              _statusLabel(
                                assignment['status']?.toString().toUpperCase() ?? '',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                      const Divider(height: 28),
                      Text(
                        'Historique de livraison',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (events.isEmpty)
                        _DeliveryEventRow(
                          status: packageStatus,
                          createdAt: package['updated_at']?.toString(),
                          isLatest: true,
                        )
                      else
                        for (var eventIndex = 0;
                            eventIndex < events.length;
                            eventIndex++)
                          _DeliveryEventRow(
                            status: events[eventIndex]['status']
                                    ?.toString()
                                    .toUpperCase() ??
                                '',
                            createdAt:
                                events[eventIndex]['created_at']?.toString(),
                            isLatest: eventIndex == events.length - 1,
                          ),
                      if (location != null && point != null) ...[
                        const Divider(height: 28),
                        Row(
                          children: [
                            const Icon(Icons.my_location_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Position du livreur',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            Text(
                              _formatDateTime(
                                location['recorded_at']?.toString(),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 220,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: point,
                                initialZoom: 14,
                                minZoom: 5,
                                maxZoom: 19,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'marketplace_multiservices_burkina',
                                  maxZoom: 19,
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: point,
                                      width: 48,
                                      height: 48,
                                      child: const Icon(
                                        Icons.delivery_dining,
                                        size: 42,
                                      ),
                                    ),
                                  ],
                                ),
                                SimpleAttributionWidget(
                                  source: const Text(
                                    'OpenStreetMap contributors',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'La position affichée est la dernière position transmise pendant la livraison.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (location == null &&
                          const {
                            'ASSIGNED',
                            'ACCEPTED',
                            'PICKED_UP',
                            'IN_TRANSIT',
                          }.contains(packageStatus)) ...[
                        const Divider(height: 28),
                        const Row(
                          children: [
                            Icon(Icons.location_searching_outlined),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'La position du livreur sera affichée dès sa prochaine mise à jour.',
                              ),
                            ),
                          ],
                        ),
                      ],
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

  String _shortId(String id) {
    if (id.isEmpty) return '-';
    return id.length <= 8 ? id.toUpperCase() : id.substring(0, 8).toUpperCase();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'CREATED':
        return 'Colis créé';
      case 'READY_FOR_PICKUP':
        return 'Prêt à récupérer';
      case 'ASSIGNED':
        return 'Livreur affecté';
      case 'ACCEPTED':
        return 'Prise en charge acceptée';
      case 'PICKED_UP':
        return 'Colis récupéré';
      case 'IN_TRANSIT':
        return 'En cours de livraison';
      case 'DELIVERED':
        return 'Livré';
      case 'RETURNED':
        return 'Retourné';
      case 'DAMAGED':
        return 'Colis endommagé';
      case 'LOST':
        return 'Colis introuvable';
      case 'CANCELLED':
        return 'Livraison annulée';
      default:
        return status.isEmpty ? 'Statut indisponible' : status.replaceAll('_', ' ');
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'DELIVERED':
        return Icons.check_circle_outline;
      case 'IN_TRANSIT':
      case 'PICKED_UP':
        return Icons.local_shipping_outlined;
      case 'DAMAGED':
      case 'LOST':
        return Icons.warning_amber_outlined;
      case 'RETURNED':
      case 'CANCELLED':
        return Icons.info_outline;
      default:
        return Icons.radio_button_checked;
    }
  }

  String _formatDateTime(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) return 'Mise à jour en attente';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} à $hour:$minute';
  }

  LatLng? _parsePoint(dynamic raw) {
    if (raw is Map) {
      final lat = num.tryParse(
        (raw['latitude'] ?? raw['lat']).toString(),
      );
      final lng = num.tryParse(
        (raw['longitude'] ?? raw['lng'] ?? raw['lon']).toString(),
      );
      if (lat != null &&
          lng != null &&
          _valid(lat.toDouble(), lng.toDouble())) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    if (raw is List && raw.length >= 2) {
      final lng = num.tryParse(raw[0].toString());
      final lat = num.tryParse(raw[1].toString());
      if (lat != null &&
          lng != null &&
          _valid(lat.toDouble(), lng.toDouble())) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    if (raw is String) {
      final normalized = raw
          .replaceFirst(
            RegExp(r'^SRID=[^;]+;', caseSensitive: false),
            '',
          )
          .trim();

      final match = RegExp(
        r'^POINT\s*\(\s*([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s*\)$',
        caseSensitive: false,
      ).firstMatch(normalized);

      if (match != null) {
        final lng = double.tryParse(match.group(1)!);
        final lat = double.tryParse(match.group(2)!);
        if (lat != null && lng != null && _valid(lat, lng)) {
          return LatLng(lat, lng);
        }
      }
    }

    return null;
  }

  bool _valid(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  double _progress(String? status) {
    switch (status) {
      case 'CREATED':
        return 0.15;
      case 'READY_FOR_PICKUP':
        return 0.25;
      case 'ASSIGNED':
        return 0.35;
      case 'ACCEPTED':
        return 0.45;
      case 'PICKED_UP':
        return 0.6;
      case 'IN_TRANSIT':
        return 0.8;
      case 'DELIVERED':
        return 1;
      default:
        return 0.1;
    }
  }
}


class _DeliveryEventRow extends StatelessWidget {
  const _DeliveryEventRow({
    required this.status,
    required this.createdAt,
    required this.isLatest,
  });

  final String status;
  final String? createdAt;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(createdAt ?? '');
    final local = date?.toLocal();
    final day = local == null
        ? null
        : local.day.toString().padLeft(2, '0');
    final month = local == null
        ? null
        : local.month.toString().padLeft(2, '0');
    final hour = local == null
        ? null
        : local.hour.toString().padLeft(2, '0');
    final minute = local == null
        ? null
        : local.minute.toString().padLeft(2, '0');
    final timestamp = local == null
        ? 'Date non disponible'
        : '$day/$month/${local.year} à $hour:$minute';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isLatest ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: isLatest
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _deliveryStatusLabel(status),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isLatest ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  timestamp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (isLatest)
            const Text(
              'Dernière étape',
              style: TextStyle(fontSize: 11),
            ),
        ],
      ),
    );
  }

  static String _deliveryStatusLabel(String status) {
    switch (status) {
      case 'CREATED':
        return 'Commande de livraison créée';
      case 'READY_FOR_PICKUP':
        return 'Colis prêt à être récupéré';
      case 'ASSIGNED':
        return 'Un livreur a été affecté';
      case 'ACCEPTED':
        return 'Le livreur a accepté la course';
      case 'PICKED_UP':
        return 'Le colis a été récupéré';
      case 'IN_TRANSIT':
        return 'Le colis est en route';
      case 'DELIVERED':
        return 'Colis livré';
      case 'RETURNED':
        return 'Colis retourné';
      case 'DAMAGED':
        return 'Incident : colis endommagé';
      case 'LOST':
        return 'Incident : colis introuvable';
      case 'CANCELLED':
        return 'Livraison annulée';
      default:
        return status.isEmpty ? 'Étape de livraison' : status.replaceAll('_', ' ');
    }
  }
}

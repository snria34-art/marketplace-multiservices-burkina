import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../domain/marketplace_module.dart';

final enabledModulesProvider =
    FutureProvider<List<MarketplaceModule>>((ref) async {
  final engine = ref.watch(marketplaceEngineProvider);
  final client = engine.clientFor(MarketplaceCapability.discoverModules);
  if (client == null) return const [];

  final rows = await engine.read(() async => await client
      .from('marketplace_modules')
      .select('key,label,route,icon_name,enabled,sort_order,config')
      .eq('enabled', true)
      .order('sort_order')
      .limit(100));

  return (rows as List)
      .map(
        (row) => MarketplaceModule.fromMap(
          Map<String, dynamic>.from(row as Map),
        ),
      )
      .toList();
});

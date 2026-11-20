import 'dart:convert';

import 'package:flutter/services.dart';

/// Offline, verified administrative location directory for Burkina Faso.
///
/// Commune/region names come from the INSD Annuaire statistique national 2024
/// (December 2025). Urban sectors and attached villages are only listed for
/// Ouagadougou and Bobo-Dioulasso where the annuaire publishes those tables.
/// A free-text neighbourhood/address must always remain available to users.
class BurkinaLocationDirectory {
  BurkinaLocationDirectory._({
    required this.regions,
    required this.urbanSubdivisions,
  });

  static const assetPath = 'assets/data/burkina_locations.json';

  final List<Map<String, dynamic>> regions;
  final Map<String, dynamic> urbanSubdivisions;

  static Future<BurkinaLocationDirectory> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Répertoire géographique invalide.');
    }

    final regionsRaw = decoded['regions'];
    final urbanRaw = decoded['urbanSubdivisions'];
    if (regionsRaw is! List || urbanRaw is! Map) {
      throw const FormatException('Répertoire géographique incomplet.');
    }

    return BurkinaLocationDirectory._(
      regions: _mapList(regionsRaw),
      urbanSubdivisions: Map<String, dynamic>.from(urbanRaw),
    );
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  List<String> get regionNames => regions
      .map((region) => region['name']?.toString() ?? '')
      .where((name) => name.isNotEmpty)
      .toList(growable: false);

  List<String> provincesFor(String? regionName) {
    final region = _findRegion(regionName);
    if (region == null) return const [];
    return _mapList(region['provinces'])
        .map((province) => province['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  List<String> communesFor(String? regionName, String? provinceName) {
    final region = _findRegion(regionName);
    if (region == null) return const [];
    final province = _mapList(region['provinces']).where(
      (item) => item['name']?.toString() == provinceName,
    );
    if (province.isEmpty) return const [];
    final communes = province.first['communes'];
    if (communes is! List) return const [];

    // INSD table 1.1.01 lists the 12 Ouagadougou and 7 Bobo-Dioulasso
    // arrondissements as commune-level administrative units. The address
    // form offers each city as a parent selection so that its arrondissement
    // and sector can be selected in the next fields.
    final names = communes.map((value) => value.toString()).toList();
    if (regionName == 'Kadiogo' && provinceName == 'Kadiogo') {
      names.removeWhere((name) => name.startsWith('Arrondissement n°'));
      names.insert(0, 'Ouagadougou');
    } else if (regionName == 'Guiriko' && provinceName == 'Houet') {
      names.removeWhere((name) => name.startsWith('Arrondissement n°'));
      names.insert(0, 'Bobo-Dioulasso');
    }
    return names.toList(growable: false);
  }

  List<int> arrondissementsFor(String? communeName) {
    final city = _urbanCity(communeName);
    if (city == null) return const [];
    final rows = _mapList(city['arrondissements']);
    return rows
        .map((row) => int.tryParse(row['number']?.toString() ?? ''))
        .whereType<int>()
        .toList(growable: false);
  }

  List<int> sectorsFor(String? communeName, int? arrondissement) {
    final row = _urbanArrondissement(communeName, arrondissement);
    if (row == null || row['sectors'] is! List) return const [];
    return (row['sectors'] as List)
        .map((value) => int.tryParse(value.toString()))
        .whereType<int>()
        .toList(growable: false);
  }

  List<String> attachedVillagesFor(
    String? communeName,
    int? arrondissement,
  ) {
    final row = _urbanArrondissement(communeName, arrondissement);
    if (row == null || row['villages'] is! List) return const [];
    return (row['villages'] as List)
        .map((value) => value.toString())
        .toList(growable: false);
  }

  bool hasPublishedUrbanSectors(String? communeName) {
    return _urbanCity(communeName) != null;
  }

  Map<String, dynamic>? _findRegion(String? regionName) {
    if (regionName == null || regionName.isEmpty) return null;
    for (final region in regions) {
      if (region['name']?.toString() == regionName) return region;
    }
    return null;
  }

  Map<String, dynamic>? _urbanCity(String? communeName) {
    final normalized = _normalize(communeName);
    if (normalized == 'ouagadougou') {
      final city = urbanSubdivisions['Ouagadougou'];
      return city is Map ? Map<String, dynamic>.from(city) : null;
    }
    if (normalized == 'bobo-dioulasso' || normalized == 'bobodioulasso') {
      final city = urbanSubdivisions['BoboDioulasso'];
      return city is Map ? Map<String, dynamic>.from(city) : null;
    }
    return null;
  }

  Map<String, dynamic>? _urbanArrondissement(
    String? communeName,
    int? arrondissement,
  ) {
    if (arrondissement == null) return null;
    final city = _urbanCity(communeName);
    if (city == null) return null;
    final rows = _mapList(city['arrondissements']);
    for (final row in rows) {
      if (int.tryParse(row['number']?.toString() ?? '') == arrondissement) {
        return row;
      }
    }
    return null;
  }

  String _normalize(String? value) {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('–', '-')
        .replaceAll('—', '-');
  }
}

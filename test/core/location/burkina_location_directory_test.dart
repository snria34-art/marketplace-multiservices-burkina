import 'package:flutter_test/flutter_test.dart';

import 'package:marketplace_multiservices_burkina/core/location/burkina_location_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BurkinaLocationDirectory directory;

  setUpAll(() async {
    directory = await BurkinaLocationDirectory.load();
  });

  test('loads the 17 administrative regions and 47 provinces', () {
    expect(directory.regionNames, hasLength(17));
    final provinceCount = directory.regions.fold<int>(
      0,
      (total, region) =>
          total + (region['provinces'] as List<dynamic>).length,
    );
    expect(provinceCount, 47);
    expect(directory.regionNames, contains('Koulsé'));
    expect(directory.regionNames, contains('Tannouny'));
  });

  test('offers Ouagadougou as the parent city and all 12 arrondissements', () {
    final communes = directory.communesFor('Kadiogo', 'Kadiogo');
    expect(communes, contains('Ouagadougou'));
    expect(communes, isNot(contains('Arrondissement n°1')));
    expect(directory.arrondissementsFor('Ouagadougou'), hasLength(12));
    expect(directory.sectorsFor('Ouagadougou', 12), [52, 53, 54, 55]);
    expect(directory.sectorsFor('Ouagadougou', 1), [1, 2, 3, 4, 5, 6]);
  });

  test('offers Bobo-Dioulasso and its INSD sectors and attached villages', () {
    final communes = directory.communesFor('Guiriko', 'Houet');
    expect(communes, contains('Bobo-Dioulasso'));
    expect(directory.arrondissementsFor('Bobo-Dioulasso'), hasLength(7));
    expect(directory.sectorsFor('Bobo-Dioulasso', 4), [15, 16, 24, 32, 33]);
    expect(
      directory.attachedVillagesFor('Bobo-Dioulasso', 2),
      contains('Dafinso'),
    );
    expect(directory.attachedVillagesFor('Bobo-Dioulasso', 7), contains('Nasso'));
  });

  test('does not invent urban sector records for unlisted cities', () {
    expect(directory.hasPublishedUrbanSectors('Gaoua'), isFalse);
    expect(directory.sectorsFor('Gaoua', 1), isEmpty);
    expect(directory.attachedVillagesFor('Ouagadougou', 1), isEmpty);
  });
}

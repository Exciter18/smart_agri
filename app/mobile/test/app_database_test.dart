import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:smart_agri/data/app_database.dart';
import 'package:smart_agri/models/farm_profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'smart_agri_database_test_',
    );
    database = AppDatabase(
      databasePath: path.join(temporaryDirectory.path, 'test.db'),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('saves and reloads a farm profile', () async {
    const profile = FarmProfile(
      name: 'North Field',
      riceVariety: 'IR64',
      growthStage: 'Tillering',
      areaHa: 1.25,
    );

    await database.saveFarmProfile(profile);

    final storedProfile = await database.getFarmProfile();
    expect(storedProfile.name, profile.name);
    expect(storedProfile.riceVariety, profile.riceVariety);
    expect(storedProfile.growthStage, profile.growthStage);
    expect(storedProfile.areaHa, profile.areaHa);
  });

  test('stores diagnosis image and returns history newest first', () async {
    final image = Uint8List.fromList([1, 2, 3, 4]);
    final earlier = DateTime.utc(2026, 10, 1, 8);
    final later = DateTime.utc(2026, 10, 2, 9);
    final earlierId = await database.saveDiagnosis(
      disease: 'Leaf Blast',
      confidence: 82.5,
      createdAt: earlier,
      imageBytes: image,
    );
    await database.saveDiagnosis(
      disease: 'Brown Spot',
      confidence: 91,
      createdAt: later,
      imageBytes: image,
    );

    final diagnoses = await database.getDiagnoses();

    expect(diagnoses.map((record) => record.disease), [
      'Brown Spot',
      'Leaf Blast',
    ]);
    expect(diagnoses.last.id, earlierId);
    expect(diagnoses.last.confidence, 82.5);
    expect(diagnoses.last.createdAt.toUtc(), earlier);
    expect(diagnoses.last.imageBytes, image);
  });

  test(
    'updating the farm profile preserves linked diagnosis history',
    () async {
      await database.saveDiagnosis(
        disease: 'Leaf Blast',
        confidence: 82.5,
        createdAt: DateTime.utc(2026, 10, 1),
        imageBytes: Uint8List.fromList([1]),
      );

      await database.saveFarmProfile(const FarmProfile(name: 'Updated Farm'));

      expect((await database.getDiagnoses()), hasLength(1));
      expect((await database.getFarmProfile()).name, 'Updated Farm');
    },
  );

  test('deletes a diagnosis from history', () async {
    final id = await database.saveDiagnosis(
      disease: 'Leaf Blast',
      confidence: 82.5,
      createdAt: DateTime.utc(2026, 10, 1),
      imageBytes: Uint8List.fromList([1]),
    );

    await database.deleteDiagnosis(id);

    expect(await database.getDiagnoses(), isEmpty);
  });

  test('persists farm data and history after closing and reopening', () async {
    await database.saveFarmProfile(const FarmProfile(name: 'Persisted Farm'));
    await database.saveDiagnosis(
      disease: 'Brown Spot',
      confidence: 94,
      createdAt: DateTime.utc(2026, 10, 1),
      imageBytes: Uint8List.fromList([4, 5, 6]),
    );
    await database.close();
    database = AppDatabase(
      databasePath: path.join(temporaryDirectory.path, 'test.db'),
    );

    expect((await database.getFarmProfile()).name, 'Persisted Farm');
    expect((await database.getDiagnoses()).single.disease, 'Brown Spot');
  });

  test('fails explicitly when asked to delete a missing diagnosis', () async {
    await expectLater(
      database.deleteDiagnosis(404),
      throwsA(isA<StateError>()),
    );
  });
}

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
      ageDays: 35,
      recentWeather: 'rainy_humid',
      waterCondition: 'adequate',
      nitrogenUse: 'balanced',
      previousAction: 'Applied fertilizer',
    );

    await database.saveFarmProfile(profile);

    final storedProfile = await database.getFarmProfile();
    expect(storedProfile.name, profile.name);
    expect(storedProfile.riceVariety, profile.riceVariety);
    expect(storedProfile.growthStage, profile.growthStage);
    expect(storedProfile.areaHa, profile.areaHa);
    expect(storedProfile.ageDays, profile.ageDays);
    expect(storedProfile.recentWeather, profile.recentWeather);
    expect(storedProfile.waterCondition, profile.waterCondition);
    expect(storedProfile.nitrogenUse, profile.nitrogenUse);
    expect(storedProfile.previousAction, profile.previousAction);
    expect(profile.agentContext, {
      'rice_variety': 'IR64',
      'age_days': 35,
      'growth_stage': 'tillering',
      'recent_weather': 'rainy_humid',
      'water_condition': 'adequate',
      'nitrogen_use': 'balanced',
      'previous_action': 'Applied fertilizer',
    });
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
      farmContext: const {'age_days': 35},
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
    expect(diagnoses.last.farmContext, {'age_days': 35});
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

  test('migrates version 1 farm data and history without losing records', () async {
    final oldDatabasePath = path.join(temporaryDirectory.path, 'legacy.db');
    final oldDatabase = await databaseFactory.openDatabase(
      oldDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE farms (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              name TEXT NOT NULL DEFAULT '',
              rice_variety TEXT NOT NULL DEFAULT '',
              growth_stage TEXT NOT NULL DEFAULT '',
              area REAL
            )
          ''');
          await db.insert('farms', {
            'id': 1,
            'name': 'Legacy field',
            'rice_variety': 'IR64',
            'growth_stage': 'Tillering',
            'area': 0.75,
          });
          await db.execute('''
            CREATE TABLE diagnoses (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              farm_id INTEGER NOT NULL DEFAULT 1,
              disease TEXT NOT NULL,
              confidence REAL NOT NULL,
              created_at TEXT NOT NULL,
              image BLOB NOT NULL,
              FOREIGN KEY (farm_id) REFERENCES farms(id) ON DELETE CASCADE
            )
          ''');
          await db.insert('diagnoses', {
            'disease': 'Leaf Blast',
            'confidence': 82.5,
            'created_at': DateTime.utc(2026, 10, 1).toIso8601String(),
            'image': Uint8List.fromList([7, 8, 9]),
          });
          await db.execute(
            'CREATE INDEX diagnoses_created_at_idx ON diagnoses(created_at DESC)',
          );
        },
      ),
    );
    await oldDatabase.close();

    database = AppDatabase(databasePath: oldDatabasePath);
    final profile = await database.getFarmProfile();
    final diagnosis = (await database.getDiagnoses()).single;

    expect(profile.name, 'Legacy field');
    expect(profile.riceVariety, 'IR64');
    expect(profile.ageDays, isNull);
    expect(profile.recentWeather, isEmpty);
    expect(diagnosis.disease, 'Leaf Blast');
    expect(diagnosis.farmContext, isEmpty);
  });

  test('fails explicitly when asked to delete a missing diagnosis', () async {
    await expectLater(
      database.deleteDiagnosis(404),
      throwsA(isA<StateError>()),
    );
  });
}

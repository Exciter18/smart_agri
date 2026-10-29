import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/diagnosis_record.dart';
import '../models/farm_profile.dart';

class AppDatabase {
  AppDatabase({this.databasePath});

  static const _databaseName = 'smart_agri.db';
  static const _databaseVersion = 2;
  final String? databasePath;

  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final resolvedPath =
        databasePath ?? path.join(await getDatabasesPath(), _databaseName);
    _database = await openDatabase(
      resolvedPath,
      version: _databaseVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE farms (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            name TEXT NOT NULL DEFAULT '',
            rice_variety TEXT NOT NULL DEFAULT '',
            growth_stage TEXT NOT NULL DEFAULT '',
            area REAL,
            age_days INTEGER,
            recent_weather TEXT NOT NULL DEFAULT '',
            water_condition TEXT NOT NULL DEFAULT '',
            nitrogen_use TEXT NOT NULL DEFAULT '',
            previous_action TEXT NOT NULL DEFAULT ''
          )
        ''');
        await database.insert('farms', const {'id': 1});
        await database.execute('''
          CREATE TABLE diagnoses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            farm_id INTEGER NOT NULL DEFAULT 1,
            disease TEXT NOT NULL,
            confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 100),
            created_at TEXT NOT NULL,
            image BLOB NOT NULL,
            farm_context TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY (farm_id) REFERENCES farms(id) ON DELETE CASCADE
          )
        ''');
        await database.execute(
          'CREATE INDEX diagnoses_created_at_idx ON diagnoses(created_at DESC)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('ALTER TABLE farms ADD COLUMN age_days INTEGER');
          await database.execute(
            "ALTER TABLE farms ADD COLUMN recent_weather TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE farms ADD COLUMN water_condition TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE farms ADD COLUMN nitrogen_use TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE farms ADD COLUMN previous_action TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            "ALTER TABLE diagnoses ADD COLUMN farm_context TEXT NOT NULL DEFAULT '{}'",
          );
        }
      },
    );
    return _database!;
  }

  Future<FarmProfile> getFarmProfile() async {
    final database = await _db;
    final rows = await database.query('farms', where: 'id = ?', whereArgs: [1]);
    final row = rows.single;
    return FarmProfile(
      name: row['name']! as String,
      riceVariety: row['rice_variety']! as String,
      growthStage: row['growth_stage']! as String,
      areaHa: (row['area'] as num?)?.toDouble(),
      ageDays: (row['age_days'] as num?)?.toInt(),
      recentWeather: row['recent_weather']! as String,
      waterCondition: row['water_condition']! as String,
      nitrogenUse: row['nitrogen_use']! as String,
      previousAction: row['previous_action']! as String,
    );
  }

  Future<void> saveFarmProfile(FarmProfile profile) async {
    final database = await _db;
    final values = {
      'name': profile.name,
      'rice_variety': profile.riceVariety,
      'growth_stage': profile.growthStage,
      'area': profile.areaHa,
      'age_days': profile.ageDays,
      'recent_weather': profile.recentWeather,
      'water_condition': profile.waterCondition,
      'nitrogen_use': profile.nitrogenUse,
      'previous_action': profile.previousAction,
    };
    final updated = await database.update(
      'farms',
      values,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (updated == 0) {
      await database.insert('farms', {'id': 1, ...values});
    }
  }

  Future<int> saveDiagnosis({
    required String disease,
    required double confidence,
    required DateTime createdAt,
    required Uint8List imageBytes,
    Map<String, Object> farmContext = const {},
  }) async {
    final database = await _db;
    return database.insert('diagnoses', {
      'farm_id': 1,
      'disease': disease,
      'confidence': confidence,
      'created_at': createdAt.toUtc().toIso8601String(),
      'image': imageBytes,
      'farm_context': jsonEncode(farmContext),
    });
  }

  Future<List<DiagnosisRecord>> getDiagnoses() async {
    final database = await _db;
    final rows = await database.query(
      'diagnoses',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(DiagnosisRecord.fromMap).toList();
  }

  Future<void> deleteDiagnosis(int id) async {
    final database = await _db;
    final deleted = await database.delete(
      'diagnoses',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted == 0) {
      throw StateError('Diagnosis record $id was not found.');
    }
  }

  Future<void> close() async {
    final database = _database;
    if (database == null) return;
    await database.close();
    _database = null;
  }
}

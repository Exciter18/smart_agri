import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_agri/data/app_database.dart';
import 'package:smart_agri/models/diagnosis_record.dart';
import 'package:smart_agri/models/farm_profile.dart';
import 'package:smart_agri/main.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = _FakeAppDatabase();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await SharedPreferences.getInstance();
    await tester.pumpWidget(SmartAgriApp(database: database));
    await tester.pumpAndSettle();
  }

  Future<void> pumpAfterDatabaseAction(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  testWidgets('guides users from home into analysis and farm profile', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Welcome to Smart Agri'), findsOneWidget);
    expect(find.text('Crop disease analysis'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Irrigation planning'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Irrigation planning'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crop disease analysis'));
    await tester.pumpAndSettle();
    expect(find.text('Rice leaf analysis'), findsOneWidget);
    expect(find.byTooltip('Go back'), findsOneWidget);

    await tester.tap(find.byTooltip('Go back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Smart Agri'), findsOneWidget);

    await tester.tap(find.text('My Farm'));
    await tester.pumpAndSettle();
    expect(find.text('Growth stage'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Field A');
    await tester.scrollUntilVisible(
      find.text('Save profile'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextFormField).last, '-1');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an area greater than zero.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, '1,5');
    await tester.tap(find.text('Save profile'));
    await pumpAfterDatabaseAction(tester);
    expect(find.text('Farm profile saved on this device.'), findsOneWidget);
    expect((await database.getFarmProfile()).name, 'Field A');
    expect((await database.getFarmProfile()).areaHa, 1.5);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Field A'), findsOneWidget);
  });

  testWidgets('shows the empty history state', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('History'));
    await pumpAfterDatabaseAction(tester);

    expect(find.text('Analysis history'), findsOneWidget);
    expect(find.text('No saved analyses'), findsOneWidget);
  });

  testWidgets('farm profile dropdowns fit on a narrow phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);
    await tester.tap(find.text('My Farm'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Recent fertilizer'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Recent fertilizer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently applied a lot of nitrogen/urea'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'irrigation planning is visibly disabled without a coming soon label',
    (tester) async {
      await pumpApp(tester);

      await tester.scrollUntilVisible(
        find.text('Irrigation planning'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Irrigation planning'), findsOneWidget);
      expect(find.text('Start analysis'), findsOneWidget);
    },
  );

  testWidgets('does not expose backend configuration on the home screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'diagnosis_api_endpoint': 'http://192.168.1.25:8000/predict',
    });
    await pumpApp(tester);

    final preferences = await SharedPreferences.getInstance();
    expect(find.text('Analysis server'), findsNothing);
    expect(find.text('API URL'), findsNothing);
    expect(preferences.getString('diagnosis_api_endpoint'), isNull);
  });

  testWidgets('shows and deletes saved diagnosis history', (tester) async {
    await database.saveDiagnosis(
      disease: 'Leaf Blast',
      confidence: 87.4,
      createdAt: DateTime.utc(2026, 10, 1, 8),
      imageBytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/XioAAAAASUVORK5CYII=',
      ),
    );
    await pumpApp(tester);

    await tester.tap(find.text('History'));
    await pumpAfterDatabaseAction(tester);
    expect(find.text('Leaf Blast'), findsOneWidget);
    expect(find.textContaining('87.4% confidence'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete analysis'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpAfterDatabaseAction(tester);

    expect(find.text('No saved analyses'), findsOneWidget);
    expect(await database.getDiagnoses(), isEmpty);
  });

  test('converts previously saved Vietnamese growth stages', () {
    final profile = FarmProfile.fromJson(
      '{"name":"Field A","riceVariety":"","growthStage":"Đẻ nhánh","area":""}',
    );

    expect(profile.growthStage, 'Tillering');
  });
}

class _FakeAppDatabase extends AppDatabase {
  FarmProfile _profile = const FarmProfile();
  final List<DiagnosisRecord> _diagnoses = [];
  var _nextId = 1;

  @override
  Future<FarmProfile> getFarmProfile() async => _profile;

  @override
  Future<void> saveFarmProfile(FarmProfile profile) async {
    _profile = profile;
  }

  @override
  Future<int> saveDiagnosis({
    required String disease,
    required double confidence,
    required DateTime createdAt,
    required Uint8List imageBytes,
    Map<String, Object> farmContext = const {},
  }) async {
    final id = _nextId++;
    _diagnoses.add(
      DiagnosisRecord(
        id: id,
        disease: disease,
        confidence: confidence,
        createdAt: createdAt,
        imageBytes: imageBytes,
        farmContext: farmContext,
      ),
    );
    return id;
  }

  @override
  Future<List<DiagnosisRecord>> getDiagnoses() async {
    return _diagnoses.reversed.toList();
  }

  @override
  Future<void> deleteDiagnosis(int id) async {
    _diagnoses.removeWhere((record) => record.id == id);
  }
}

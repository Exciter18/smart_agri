import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_agri/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('guides users from home into analysis and farm profile', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartAgriApp());

    expect(find.text('Welcome to Smart Agri'), findsOneWidget);
    expect(find.text('Crop disease analysis'), findsOneWidget);
    expect(find.text('Irrigation planning'), findsOneWidget);

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
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.text('Farm profile saved on this device.'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Field A'), findsOneWidget);
  });

  testWidgets('shows the empty history state', (tester) async {
    await tester.pumpWidget(const SmartAgriApp());

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Analysis history'), findsOneWidget);
    expect(find.text('No saved analyses'), findsOneWidget);
  });

  test('converts previously saved Vietnamese growth stages', () {
    final profile = FarmProfile.fromJson(
      '{"name":"Field A","riceVariety":"","growthStage":"Đẻ nhánh","area":""}',
    );

    expect(profile.growthStage, 'Tillering');
  });
}

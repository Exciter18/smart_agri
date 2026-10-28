import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'data/app_database.dart';

void main() {
  runApp(SmartAgriApp());
}

class SmartAgriApp extends StatelessWidget {
  SmartAgriApp({super.key, AppDatabase? database})
    : database = database ?? AppDatabase();

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Agri',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: MainNavigator(database: database),
    );
  }

  ThemeData _buildTheme() {
    const forest = Color(0xFF245C3A);
    const canvas = Color(0xFFF5F7F1);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: forest, surface: canvas),
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: Color(0xFF193D29),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE7EDE3)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE2F0E4),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
    );
  }
}

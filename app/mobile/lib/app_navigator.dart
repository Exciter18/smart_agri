import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_database.dart';
import 'models/diagnosis_record.dart';
import 'models/farm_profile.dart';
import 'screens/farm_profile_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/vision_screen.dart';

class MainNavigator extends StatefulWidget {
  const MainNavigator({required this.database, super.key});

  final AppDatabase database;

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;
  FarmProfile _farmProfile = const FarmProfile();
  List<DiagnosisRecord> _diagnoses = const [];
  bool _isInitializing = true;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      var profile = await widget.database.getFarmProfile();
      final preferences = await SharedPreferences.getInstance();
      final storedProfile = preferences.getString('farm_profile');
      if (storedProfile != null) {
        profile = FarmProfile.fromJson(storedProfile);
        await widget.database.saveFarmProfile(profile);
        await preferences.remove('farm_profile');
      }

      final diagnoses = await widget.database.getDiagnoses();
      if (!mounted) return;
      setState(() {
        _farmProfile = profile;
        _diagnoses = diagnoses;
        _storageError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to initialize local database: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _storageError = 'Local data could not be loaded. Check available device storage and try again.';
      });
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _saveFarmProfile(FarmProfile profile) async {
    await widget.database.saveFarmProfile(profile);
    if (!mounted) return;
    setState(() => _farmProfile = profile);
  }

  Future<void> _refreshDiagnoses() async {
    try {
      final diagnoses = await widget.database.getDiagnoses();
      if (!mounted) return;
      setState(() => _diagnoses = diagnoses);
    } catch (error, stackTrace) {
      debugPrint('Failed to load diagnosis history: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load saved analyses. Please try again.'),
        ),
      );
    }
  }

  Future<void> _deleteDiagnosis(int id) async {
    await widget.database.deleteDiagnosis(id);
    await _refreshDiagnoses();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    if (index == 1) _refreshDiagnoses();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: Text('Loading your farm data...')),
      );
    }

    if (_storageError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    size: 48,
                    color: Color(0xFF55735D),
                  ),
                  const SizedBox(height: 16),
                  Text(_storageError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() => _isInitializing = true);
                      _initialize();
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final screens = [
      HomeScreen(
        farmProfile: _farmProfile,
        onEditFarm: () => setState(() => _selectedIndex = 2),
        onCheckDisease: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VisionScreen(
                database: widget.database,
                onDiagnosisSaved: _refreshDiagnoses,
              ),
            ),
          );
        },
      ),
      HistoryScreen(diagnoses: _diagnoses, onDelete: _deleteDiagnosis),
      FarmProfileScreen(profile: _farmProfile, onSave: _saveFarmProfile),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.agriculture_outlined),
            selectedIcon: Icon(Icons.agriculture_rounded),
            label: 'My Farm',
          ),
        ],
      ),
    );
  }
}

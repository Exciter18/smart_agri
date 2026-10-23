import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  runApp(const SmartAgriApp());
}

class SmartAgriApp extends StatelessWidget {
  const SmartAgriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Agri',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const MainNavigator(),
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

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;
  FarmProfile _farmProfile = const FarmProfile();

  @override
  void initState() {
    super.initState();
    _loadFarmProfile();
  }

  Future<void> _loadFarmProfile() async {
    final preferences = await SharedPreferences.getInstance();
    final storedProfile = preferences.getString('farm_profile');
    if (storedProfile == null || !mounted) return;

    setState(() {
      _farmProfile = FarmProfile.fromJson(storedProfile);
    });
  }

  Future<void> _saveFarmProfile(FarmProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('farm_profile', profile.toJson());
    if (!mounted) return;

    setState(() {
      _farmProfile = profile;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        farmProfile: _farmProfile,
        onEditFarm: () => setState(() => _selectedIndex = 2),
        onCheckDisease: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const VisionScreen()));
        },
      ),
      const HistoryScreen(),
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

class FarmProfile {
  const FarmProfile({
    this.name = '',
    this.riceVariety = '',
    this.growthStage = '',
    this.area = '',
  });

  final String name;
  final String riceVariety;
  final String growthStage;
  final String area;

  String toJson() => json.encode({
    'name': name,
    'riceVariety': riceVariety,
    'growthStage': growthStage,
    'area': area,
  });

  factory FarmProfile.fromJson(String value) {
    final data = json.decode(value) as Map<String, dynamic>;
    return FarmProfile(
      name: data['name'] as String? ?? '',
      riceVariety: data['riceVariety'] as String? ?? '',
      growthStage: switch (data['growthStage'] as String? ?? '') {
        'Mới gieo' => 'Seedling',
        'Đẻ nhánh' => 'Tillering',
        'Làm đòng' => 'Panicle initiation',
        'Trổ bông' => 'Heading',
        'Chín' => 'Ripening',
        final stage => stage,
      },
      area: data['area'] as String? ?? '',
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.farmProfile,
    required this.onEditFarm,
    required this.onCheckDisease,
    super.key,
  });

  final FarmProfile farmProfile;
  final VoidCallback onEditFarm;
  final VoidCallback onCheckDisease;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const _PageHeader(
              eyebrow: 'SMART AGRI',
              title: 'Welcome to Smart Agri',
              subtitle: 'Your crop management workspace.',
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _FarmSummaryCard(profile: farmProfile, onTap: onEditFarm),
                  const SizedBox(height: 24),
                  Text(
                    'Available services',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF193D29),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ActionCard(
                    icon: Icons.document_scanner_rounded,
                    title: 'Crop disease analysis',
                    description: 'Analyze a rice leaf image for potential disease symptoms.',
                    actionLabel: 'Start analysis',
                    onTap: onCheckDisease,
                  ),
                  const SizedBox(height: 12),
                  const _ActionCard(
                    icon: Icons.water_drop_outlined,
                    title: 'Irrigation planning',
                    description:
                        'Planning tools based on field and environmental data.',
                    actionLabel: 'Coming soon',
                  ),
                  const SizedBox(height: 20),
                  const _InfoBanner(
                    icon: Icons.touch_app_outlined,
                    text: 'Select a service to get started. Guided workflows will help you review each step.',
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmSummaryCard extends StatelessWidget {
  const _FarmSummaryCard({required this.profile, required this.onTap});

  final FarmProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasDetails =
        profile.name.isNotEmpty ||
        profile.riceVariety.isNotEmpty ||
        profile.growthStage.isNotEmpty ||
        profile.area.isNotEmpty;
    final details = <String>[
      if (profile.riceVariety.isNotEmpty) profile.riceVariety,
      if (profile.growthStage.isNotEmpty) profile.growthStage,
      if (profile.area.isNotEmpty) '${profile.area} ha',
    ];

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              const _IconTile(icon: Icons.agriculture_outlined, size: 50),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.isEmpty ? 'Farm profile' : profile.name,
                      style: const TextStyle(
                        color: Color(0xFF25422E),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasDetails
                          ? details.join('  •  ')
                          : 'Add details to personalize your workspace.',
                      style: const TextStyle(
                        color: Color(0xFF718075),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit_outlined, color: Color(0xFF55735D)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _IconTile(icon: icon, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF25422E),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF718075),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      actionLabel,
                      style: TextStyle(
                        color: enabled
                            ? const Color(0xFF245C3A)
                            : const Color(0xFF788276),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                enabled ? Icons.arrow_forward_rounded : Icons.schedule_rounded,
                color: const Color(0xFF55735D),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FarmProfileScreen extends StatefulWidget {
  const FarmProfileScreen({
    required this.profile,
    required this.onSave,
    super.key,
  });

  final FarmProfile profile;
  final Future<void> Function(FarmProfile profile) onSave;

  @override
  State<FarmProfileScreen> createState() => _FarmProfileScreenState();
}

class _FarmProfileScreenState extends State<FarmProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _varietyController;
  late final TextEditingController _areaController;
  late String _growthStage;
  bool _isSaving = false;

  static const _growthStages = [
    'Seedling',
    'Tillering',
    'Panicle initiation',
    'Heading',
    'Ripening',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _varietyController = TextEditingController(
      text: widget.profile.riceVariety,
    );
    _areaController = TextEditingController(text: widget.profile.area);
    _growthStage = widget.profile.growthStage;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _varietyController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        FarmProfile(
          name: _nameController.text.trim(),
          riceVariety: _varietyController.text.trim(),
          growthStage: _growthStage,
          area: _areaController.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Farm profile saved on this device.')),
      );
    } catch (error) {
      debugPrint('Failed to save farm profile: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save changes. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const _PageHeader(
              eyebrow: 'FARM DETAILS',
              title: 'My Farm',
              subtitle:
                  'Add or update your farm details. All fields are optional.',
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _ProfileTextField(
                    controller: _nameController,
                    label: 'Farm name',
                    hint: 'e.g., Field A',
                    icon: Icons.grass_outlined,
                  ),
                  const SizedBox(height: 14),
                  _ProfileTextField(
                    controller: _varietyController,
                    label: 'Rice variety',
                    hint: 'Enter variety (optional)',
                    icon: Icons.eco_outlined,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _growthStages.contains(_growthStage)
                        ? _growthStage
                        : null,
                    decoration: _profileInputDecoration(
                      'Growth stage',
                      Icons.calendar_view_week_outlined,
                    ),
                    hint: const Text('Select a growth stage'),
                    items: _growthStages
                        .map(
                          (stage) => DropdownMenuItem(
                            value: stage,
                            child: Text(stage),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _growthStage = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  _ProfileTextField(
                    controller: _areaController,
                    label: 'Area (ha)',
                    hint: 'e.g., 0.5',
                    icon: Icons.square_foot_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _InfoBanner(
                    icon: Icons.lock_outline,
                    text: 'Your details are stored on this device only. They are not sent to a server or used by the AI model.',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Saving...' : 'Save profile'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF245C3A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      decoration: _profileInputDecoration(label, icon).copyWith(hintText: hint),
    );
  }
}

InputDecoration _profileInputDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: const Color(0xFF55735D)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE1E9DF)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE1E9DF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFF4C8B5F), width: 1.5),
    ),
  );
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const _PageHeader(
              eyebrow: 'SMART AGRI',
              title: 'Analysis history',
              subtitle: 'Review your previous crop analyses.',
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: _EmptyStateCard(
                  icon: Icons.history_rounded,
                  title: 'No saved analyses',
                  subtitle: 'Your analyses will appear here once history is available.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  File? _image;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  Map<String, dynamic>? _predictionResult;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      var bytes = await pickedFile.readAsBytes();
      setState(() {
        _image = File(pickedFile.path);
        _imageBytes = bytes;
        _predictionResult = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageBytes == null && _image == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var uri = Uri.parse(
        "https://jamison-noncollusive-tomasa.ngrok-free.dev/predict",
      );
      var request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = 'true';

      if (kIsWeb) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            _imageBytes!,
            filename: 'upload.jpg',
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('file', _image!.path),
        );
      }

      var response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final decoded = json.decode(responseData);
        if (decoded is! Map<String, dynamic> ||
            decoded['disease'] is! String ||
            decoded['confidence'] is! num) {
          throw const FormatException('Invalid prediction response');
        }

        setState(() {
          _predictionResult = decoded;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage =
              "The server returned an error (status code: ${response.statusCode}).";
        });
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'Unable to connect to the analysis service. Please try again later.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const _PageHeader(
              eyebrow: 'SMART AGRI  /  CROP HEALTH',
              title: 'Rice leaf analysis',
              subtitle: 'Capture or select an image to check for potential disease symptoms.',
              onBack: true,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _PhotoPickerCard(
                    imageBytes: _imageBytes,
                    imageFile: _image,
                    isLoading: _isLoading,
                    onCameraTap: () => _pickImage(ImageSource.camera),
                    onGalleryTap: () => _pickImage(ImageSource.gallery),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _imageBytes == null || _isLoading
                        ? null
                        : _analyzeImage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF245C3A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _isLoading ? 'Analyzing image...' : 'Analyze image',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _ErrorCard(message: _errorMessage!),
                  ],
                  if (_predictionResult != null) ...[
                    const SizedBox(height: 20),
                    _PredictionCard(result: _predictionResult!),
                  ],
                  const SizedBox(height: 20),
                  const _InfoBanner(
                    icon: Icons.tips_and_updates_outlined,
                    text: 'For best results, use a clear image of the affected leaf. AI results are intended as a decision-support tool.',
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.onBack = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final bool onBack;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onBack) ...[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Go back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF245C3A),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2F0E4),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.grass_rounded,
                    color: Color(0xFF245C3A),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: Color(0xFF55735D),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF193D29),
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: const Color(0xFF68766B), height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPickerCard extends StatelessWidget {
  const _PhotoPickerCard({
    required this.imageBytes,
    required this.imageFile,
    required this.isLoading,
    required this.onCameraTap,
    required this.onGalleryTap,
  });

  final Uint8List? imageBytes;
  final File? imageFile;
  final bool isLoading;
  final VoidCallback onCameraTap;
  final VoidCallback onGalleryTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 230,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4EC),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasImage
                  ? kIsWeb
                        ? Image.memory(imageBytes!, fit: BoxFit.cover)
                        : Image.file(imageFile!, fit: BoxFit.cover)
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 42,
                          color: Color(0xFF66816B),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Add a rice leaf image',
                          style: TextStyle(
                            color: Color(0xFF254B32),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Clear images may improve analysis quality.',
                          style: TextStyle(
                            color: Color(0xFF718075),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : onCameraTap,
                    icon: const Icon(Icons.camera_alt_outlined, size: 19),
                    label: const Text('Take photo'),
                    style: _pickerButtonStyle(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : onGalleryTap,
                    icon: const Icon(Icons.photo_library_outlined, size: 19),
                    label: const Text('Choose image'),
                    style: _pickerButtonStyle(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _pickerButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF245C3A),
      side: const BorderSide(color: Color(0xFFDCE6DB)),
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final confidence = (result['confidence'] as num).toDouble();
    final disease = result['disease'] as String;

    return Card(
      color: const Color(0xFFEAF3E9),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.fact_check_outlined, color: Color(0xFF245C3A)),
                SizedBox(width: 9),
                Text(
                  'ANALYSIS RESULT',
                  style: TextStyle(
                    color: Color(0xFF45664D),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              disease,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF193D29),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Model confidence',
                  style: TextStyle(color: Color(0xFF526758)),
                ),
                Text(
                  '${confidence.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Color(0xFF245C3A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (confidence / 100).clamp(0, 1),
                minHeight: 8,
                backgroundColor: Colors.white,
                color: const Color(0xFF4C8B5F),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Confidence is not an indicator of disease severity.',
              style: TextStyle(
                color: Color(0xFF68766B),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            const Divider(color: Color(0xFFD3E2D2)),
            const SizedBox(height: 14),
            Row(
              children: [
                const _IconTile(icon: Icons.healing_outlined, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NEXT STEP',
                        style: TextStyle(
                          color: Color(0xFF55735D),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Care guidance for $disease',
                        style: const TextStyle(
                          color: Color(0xFF25422E),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const _ComingSoonBadge(),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Care guidance is in development. No treatment recommendations are available at this time.',
              style: TextStyle(
                color: Color(0xFF68766B),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3EB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'COMING SOON',
        style: TextStyle(
          color: Color(0xFF72806F),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconTile(icon: icon, size: 58),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF25422E),
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF718075),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.size = 46});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3E9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: const Color(0xFF346B45)),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFE7),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF57745D)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF68766B),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFAA3939)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF873535), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/farm_profile.dart';
import '../widgets/app_widgets.dart';

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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _varietyController;
  late final TextEditingController _areaController;
  late final TextEditingController _ageController;
  late final TextEditingController _previousActionController;
  late String _growthStage;
  String _recentWeather = '';
  String _waterCondition = '';
  String _nitrogenUse = '';
  bool _isSaving = false;

  static const _growthStages = [
    'Seedling',
    'Tillering',
    'Panicle initiation',
    'Heading',
    'Ripening',
  ];

  static const _weatherOptions = {
    'rainy_humid': 'Rainy or humid',
    'normal': 'Mostly normal',
    'dry_hot': 'Dry or hot',
  };
  static const _waterOptions = {
    'waterlogged': 'Waterlogged',
    'adequate': 'Moist enough',
    'dry': 'Dry',
  };
  static const _nitrogenOptions = {
    'recent_heavy': 'Recently applied a lot of nitrogen/urea',
    'balanced': 'Applied fertilizer as planned',
    'none_recent': 'No recent fertilizer',
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _varietyController = TextEditingController(
      text: widget.profile.riceVariety,
    );
    _areaController = TextEditingController(
      text: widget.profile.areaHa?.toString() ?? '',
    );
    _ageController = TextEditingController(
      text: widget.profile.ageDays?.toString() ?? '',
    );
    _previousActionController = TextEditingController(
      text: widget.profile.previousAction,
    );
    _growthStage = widget.profile.growthStage;
    _recentWeather = widget.profile.recentWeather;
    _waterCondition = widget.profile.waterCondition;
    _nitrogenUse = widget.profile.nitrogenUse;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _varietyController.dispose();
    _areaController.dispose();
    _ageController.dispose();
    _previousActionController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        FarmProfile(
          name: _nameController.text.trim(),
          riceVariety: _varietyController.text.trim(),
          growthStage: _growthStage,
          areaHa: double.tryParse(
            _areaController.text.trim().replaceAll(',', '.'),
          ),
          ageDays: int.tryParse(_ageController.text.trim()),
          recentWeather: _recentWeather,
          waterCondition: _waterCondition,
          nitrogenUse: _nitrogenUse,
          previousAction: _previousActionController.text.trim(),
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
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            slivers: [
              const PageHeader(
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
                      maxLength: 80,
                    ),
                    const SizedBox(height: 14),
                    _ProfileTextField(
                      controller: _ageController,
                      label: 'Crop age (days)',
                      hint: 'Approximate age, e.g. 35',
                      icon: Icons.timelapse_outlined,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        if (input.isEmpty) return null;
                        final age = int.tryParse(input);
                        if (age == null || age < 1 || age > 250) {
                          return 'Enter a whole number from 1 to 250.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
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
                              child: Text(
                                stage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _growthStage = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    _ProfileDropdownField(
                      label: 'Recent weather',
                      icon: Icons.cloud_outlined,
                      value: _weatherOptions.containsKey(_recentWeather)
                          ? _recentWeather
                          : null,
                      options: _weatherOptions,
                      onChanged: (value) =>
                          setState(() => _recentWeather = value ?? ''),
                    ),
                    const SizedBox(height: 14),
                    _ProfileDropdownField(
                      label: 'Water around the roots',
                      icon: Icons.water_drop_outlined,
                      value: _waterOptions.containsKey(_waterCondition)
                          ? _waterCondition
                          : null,
                      options: _waterOptions,
                      onChanged: (value) =>
                          setState(() => _waterCondition = value ?? ''),
                    ),
                    const SizedBox(height: 14),
                    _ProfileDropdownField(
                      label: 'Recent fertilizer',
                      icon: Icons.science_outlined,
                      value: _nitrogenOptions.containsKey(_nitrogenUse)
                          ? _nitrogenUse
                          : null,
                      options: _nitrogenOptions,
                      onChanged: (value) =>
                          setState(() => _nitrogenUse = value ?? ''),
                    ),
                    const SizedBox(height: 14),
                    _ProfileTextField(
                      controller: _previousActionController,
                      label: 'Treatments already tried',
                      hint: 'Optional: fertilizer, spraying, or other actions',
                      icon: Icons.history_edu_outlined,
                      maxLength: 240,
                      minLines: 2,
                      maxLines: 3,
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
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        if (input.isEmpty) return null;
                        final area = double.tryParse(
                          input.replaceAll(',', '.'),
                        );
                        if (area == null || !area.isFinite || area <= 0) {
                          return 'Enter an area greater than zero.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    const InfoBanner(
                      icon: Icons.lock_outline,
                      text: 'Farm name and area stay on this device. Crop details and field conditions are sent with each image to the configured analysis service. Update crop age and field conditions when they change.',
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
    this.validator,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int? maxLength;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction: TextInputAction.next,
      validator: validator,
      decoration: _profileInputDecoration(label, icon).copyWith(hintText: hint),
    );
  }
}

class _ProfileDropdownField extends StatelessWidget {
  const _ProfileDropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: _profileInputDecoration(label, icon),
      hint: const Text('Select if known'),
      items: options.entries
          .map(
            (option) => DropdownMenuItem(
              value: option.key,
              child: Text(
                option.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
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

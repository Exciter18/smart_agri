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
    _areaController = TextEditingController(
      text: widget.profile.areaHa?.toString() ?? '',
    );
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
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      validator: validator,
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

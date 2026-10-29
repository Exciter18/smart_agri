import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../data/app_database.dart';
import '../models/farm_profile.dart';
import '../services/diagnosis_api.dart';
import '../widgets/app_widgets.dart';
import 'diagnosis_result_screen.dart';

class VisionScreen extends StatefulWidget {
  const VisionScreen({
    required this.database,
    required this.farmProfile,
    required this.apiEndpoint,
    required this.onDiagnosisSaved,
    super.key,
  });

  final AppDatabase database;
  final FarmProfile farmProfile;
  final Uri apiEndpoint;
  final Future<void> Function() onDiagnosisSaved;

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  late final DiagnosisApi _diagnosisApi;
  File? _image;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _diagnosisApi = DiagnosisApi(endpoint: widget.apiEndpoint);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (pickedFile == null || !mounted) return;
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _image = File(pickedFile.path);
        _imageBytes = bytes;
        _errorMessage = null;
      });
    } on PlatformException catch (error) {
      debugPrint('Image picker failed: $error');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to access the selected image. Check app permissions and try again.';
      });
    } on FileSystemException catch (error) {
      debugPrint('Reading selected image failed: $error');
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Unable to read the selected image. Please choose another image.';
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageBytes == null || _imageBytes!.isEmpty) {
      setState(() {
        _errorMessage = 'Choose a valid image before starting the analysis.';
      });
      return;
    }

    setState(() => _isLoading = true);
    final farmContext = widget.farmProfile.agentContext;
    try {
      final result = await _diagnosisApi.analyzeImage(
        _imageBytes!,
        farmContext: farmContext,
      );
      if (!mounted) return;
      final createdAt = DateTime.now();
      String? saveError;
      try {
        await widget.database.saveDiagnosis(
          disease: result.disease,
          confidence: result.confidence,
          createdAt: createdAt,
          imageBytes: _imageBytes!,
          farmContext: farmContext,
        );
        await widget.onDiagnosisSaved();
      } catch (error, stackTrace) {
        debugPrint('Failed to save diagnosis: $error\n$stackTrace');
        saveError =
            'Analysis is complete, but it could not be saved to history.';
      }
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
        _isLoading = false;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DiagnosisResultScreen(
            diagnosis: result,
            imageBytes: _imageBytes!,
            api: _diagnosisApi,
            saveError: saveError,
          ),
        ),
      );
    } on DiagnosisApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (error, stackTrace) {
      debugPrint('Unexpected diagnosis error: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const PageHeader(
              eyebrow: 'SMART AGRI  /  CROP HEALTH',
              title: 'Rice leaf analysis',
              subtitle: 'Capture or select an image to check for potential disease symptoms.',
              onBack: true,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  PhotoPickerCard(
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
                    ErrorCard(message: _errorMessage!),
                  ],
                  const SizedBox(height: 20),
                  const InfoBanner(
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

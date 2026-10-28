import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.onBack = false,
    super.key,
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

class PhotoPickerCard extends StatelessWidget {
  const PhotoPickerCard({
    required this.imageBytes,
    required this.imageFile,
    required this.isLoading,
    required this.onCameraTap,
    required this.onGalleryTap,
    super.key,
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

class PredictionCard extends StatelessWidget {
  const PredictionCard({required this.result, super.key});

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
          ],
        ),
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
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
              IconTile(icon: icon, size: 58),
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

class IconTile extends StatelessWidget {
  const IconTile({required this.icon, this.size = 46, super.key});

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

class InfoBanner extends StatelessWidget {
  const InfoBanner({required this.icon, required this.text, super.key});

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

class ErrorCard extends StatelessWidget {
  const ErrorCard({required this.message, super.key});

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

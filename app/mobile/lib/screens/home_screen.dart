import 'package:flutter/material.dart';

import '../models/farm_profile.dart';
import '../widgets/app_widgets.dart';

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
            const PageHeader(
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
                    'Explore',
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
                  ),
                  const SizedBox(height: 20),
                  const InfoBanner(
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
        profile.areaHa != null;
    final details = <String>[
      if (profile.riceVariety.isNotEmpty) profile.riceVariety,
      if (profile.growthStage.isNotEmpty) profile.growthStage,
      if (profile.areaHa != null) '${profile.areaHa} ha',
    ];

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              const IconTile(icon: Icons.agriculture_outlined, size: 50),
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
    this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Card(
      color: enabled ? null : const Color(0xFFF0F2EF),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                IconTile(icon: icon, size: 52),
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
                      if (actionLabel != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          actionLabel!,
                          style: const TextStyle(
                            color: Color(0xFF245C3A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (enabled)
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF55735D),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

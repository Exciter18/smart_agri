import 'package:flutter/material.dart';

import '../models/diagnosis_record.dart';
import '../widgets/app_widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    required this.diagnoses,
    required this.onDelete,
    super.key,
  });

  final List<DiagnosisRecord> diagnoses;
  final Future<void> Function(int id) onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const PageHeader(
              eyebrow: 'SMART AGRI',
              title: 'Analysis history',
              subtitle: 'Review and manage analyses saved on this device.',
            ),
            if (diagnoses.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: EmptyStateCard(
                    icon: Icons.history_rounded,
                    title: 'No saved analyses',
                    subtitle: 'Completed analyses will appear here so you can review them later.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final diagnosis = diagnoses[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              diagnosis.imageBytes,
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                            ),
                          ),
                          title: Text(
                            diagnosis.disease,
                            style: const TextStyle(
                              color: Color(0xFF25422E),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              '${diagnosis.confidence.toStringAsFixed(1)}% confidence\n${_formatDiagnosisDate(context, diagnosis.createdAt)}',
                            ),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Delete analysis',
                            onPressed: () => _confirmDelete(context, diagnosis),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFF8A4840),
                            ),
                          ),
                          onTap: () => _showDetails(context, diagnosis),
                        ),
                      ),
                    );
                  }, childCount: diagnoses.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDiagnosisDate(BuildContext context, DateTime date) {
    final localDate = date.toLocal();
    final dateText = MaterialLocalizations.of(context)
        .formatMediumDate(localDate);
    final timeText = TimeOfDay.fromDateTime(localDate).format(context);
    return '$dateText · $timeText';
  }

  Future<void> _showDetails(BuildContext context, DiagnosisRecord diagnosis) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(diagnosis.disease),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                diagnosis.imageBytes,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${diagnosis.confidence.toStringAsFixed(1)}% model confidence',
            ),
            const SizedBox(height: 4),
            Text(_formatDiagnosisDate(context, diagnosis.createdAt)),
            const SizedBox(height: 10),
            const Text(
              'Confidence is not an indicator of disease severity.',
              style: TextStyle(color: Color(0xFF68766B), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DiagnosisRecord diagnosis,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this analysis?'),
        content: const Text(
          'This saved image and result will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await onDelete(diagnosis.id);
    } catch (error, stackTrace) {
      debugPrint('Failed to delete diagnosis: $error\n$stackTrace');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete this analysis. Try again.'),
        ),
      );
    }
  }
}

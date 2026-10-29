import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/diagnosis_api.dart';

class DiagnosisResultScreen extends StatefulWidget {
  const DiagnosisResultScreen({
    required this.diagnosis,
    required this.imageBytes,
    required this.api,
    this.saveError,
    super.key,
  });

  final DiagnosisResult diagnosis;
  final Uint8List imageBytes;
  final DiagnosisApi api;
  final String? saveError;

  @override
  State<DiagnosisResultScreen> createState() => _DiagnosisResultScreenState();
}

class _DiagnosisResultScreenState extends State<DiagnosisResultScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _questionController;
  late final List<_ChatMessage> _messages;
  AgentReply? _agentReply;
  String? _agentError;
  bool _isAgentLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _questionController = TextEditingController();
    _agentReply = widget.diagnosis.agent;
    _agentError = widget.diagnosis.agentError;
    _messages = [
      if (_agentReply case final reply?)
        _ChatMessage(text: reply.message, fromUser: false),
    ];
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    _questionController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _sendQuestion() async {
    final reply = _agentReply;
    final question = _questionController.text.trim();
    if (reply == null || question.isEmpty || _isAgentLoading) return;

    _questionController.clear();
    setState(() {
      _isAgentLoading = true;
      _agentError = null;
      _messages.add(_ChatMessage(text: question, fromUser: true));
    });

    try {
      final nextReply = await widget.api.sendAgentMessage(
        sessionId: reply.sessionId,
        message: question,
      );
      if (!mounted) return;
      setState(() {
        _agentReply = nextReply;
        _messages.add(_ChatMessage(text: nextReply.message, fromUser: false));
      });
    } on DiagnosisApiException catch (error) {
      if (!mounted) return;
      setState(() => _agentError = error.message);
    } finally {
      if (mounted) setState(() => _isAgentLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis details'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'Result'),
            Tab(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              text: 'Rice Care',
            ),
            Tab(icon: Icon(Icons.menu_book_outlined), text: 'Sources'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildResultTab(context),
          _buildChatTab(),
          _buildSourcesTab(),
        ],
      ),
      bottomNavigationBar: _tabController.index == 1 && _agentReply != null
          ? _buildQuestionComposer()
          : null,
    );
  }

  Widget _buildResultTab(BuildContext context) {
    final confidence = widget.diagnosis.confidence;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.memory(
            widget.imageBytes,
            height: 230,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3E9),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.eco_outlined, color: Color(0xFF245C3A)),
                  SizedBox(width: 8),
                  Text(
                    'POSSIBLE IDENTIFICATION',
                    style: TextStyle(
                      color: Color(0xFF45664D),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.diagnosis.disease,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF193D29),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Model confidence',
                    style: TextStyle(
                      color: Color(0xFF526758),
                      fontWeight: FontWeight.w600,
                    ),
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
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (confidence / 100).clamp(0, 1),
                  minHeight: 8,
                  backgroundColor: Colors.white,
                  color: const Color(0xFF4C8B5F),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Confidence is not an indicator of disease severity. Use this result as a guide, not a confirmed diagnosis.',
                style: TextStyle(
                  color: Color(0xFF68766B),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (widget.saveError != null) ...[
          const SizedBox(height: 14),
          _NoticeCard(
            icon: Icons.warning_amber_rounded,
            message: widget.saveError!,
            color: const Color(0xFF8A5A12),
          ),
        ],
      ],
    );
  }

  Widget _buildChatTab() {
    if (_agentReply == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _NoticeCard(
            icon: Icons.cloud_off_outlined,
            message: _agentError ?? 'Rice Care could not start for this analysis. Please try again later.',
            color: const Color(0xFF8A5A12),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      itemCount:
          _messages.length +
          (_isAgentLoading ? 1 : 0) +
          (_agentError != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _messages.length) {
          final message = _messages[index];
          return Align(
            alignment: message.fromUser
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.84,
              ),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              decoration: BoxDecoration(
                color: message.fromUser
                    ? const Color(0xFF245C3A)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: message.fromUser
                    ? null
                    : Border.all(color: const Color(0xFFDDE7DF)),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  height: 1.45,
                  color: message.fromUser
                      ? Colors.white
                      : const Color(0xFF25422E),
                ),
              ),
            ),
          );
        }

        if (_isAgentLoading && index == _messages.length) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _NoticeCard(
            icon: Icons.info_outline,
            message: _agentError!,
            color: const Color(0xFF8A5A12),
          ),
        );
      },
    );
  }

  Widget _buildQuestionComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _questionController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendQuestion(),
                decoration: InputDecoration(
                  hintText: 'Ask about this result...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFDDE7DF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFDDE7DF)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isAgentLoading ? null : _sendQuestion,
              tooltip: 'Send question',
              icon: _isAgentLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF245C3A),
                foregroundColor: Colors.white,
                minimumSize: const Size(50, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesTab() {
    final sources = _agentReply?.sources ?? const [];
    if (sources.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _NoticeCard(
            icon: Icons.menu_book_outlined,
            message: 'No reference sources were returned for this response.',
            color: Color(0xFF68766B),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final source = sources[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.menu_book_outlined,
                      color: Color(0xFF245C3A),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        source.title,
                        style: const TextStyle(
                          color: Color(0xFF25422E),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  source.url,
                  style: const TextStyle(
                    color: Color(0xFF45664D),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE7DF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(height: 1.45, color: Color(0xFF526758)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'services/question_storage_service.dart';
import 'services/tts_service.dart';
class QuestionsScreen extends StatefulWidget {
  final TtsService ttsService;
  const QuestionsScreen({super.key, required this.ttsService});

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final QuestionStorageService _storageService = QuestionStorageService();
  List<String> _questions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final questions = await _storageService.getQuestions();
    setState(() {
      _questions = questions;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Questions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: 'Read All',
            onPressed: _questions.isEmpty
              ? null 
              : () {
                final allText = _questions.join('. ');
                widget.ttsService.speak(allText);
              }
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              await _storageService.clearQuestions();
              _loadQuestions();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? const Center(child: Text('No questions saved yet.'))
              : ListView.builder(
                  itemCount: _questions.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_questions[index]),
                      ),
                    );
                  },
                ),
    );
  }
}

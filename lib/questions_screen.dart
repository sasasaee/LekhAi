import 'package:flutter/material.dart';
import 'services/question_storage_service.dart';
import 'services/tts_service.dart';
import 'package:flutter/services.dart';

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
    widget.ttsService.speak(
      "Welcome to saved questions screen. Here you can review your previously saved questions.",
    );
  }

  Future<void> _loadQuestions() async {
    final questions = await _storageService.getQuestions();
    setState(() {
      _questions = questions.reversed.toList();
      _isLoading = false;
    });
  }

  void _deleteQuestion(int index) async {
    HapticFeedback.lightImpact();
    _questions.removeAt(index);
    await _storageService.clearQuestions();
    for (var q in _questions) {
      await _storageService.saveQuestion(q);
    }
    setState(() {});
    widget.ttsService.speak("Question deleted.");
  }

  void _openFullQuestion(String question) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullQuestionScreen(
          question: question,
          ttsService: widget.ttsService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Questions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Clear All',
            onPressed: () async {
              HapticFeedback.lightImpact();
              await _storageService.clearQuestions();
              _loadQuestions();
              widget.ttsService.speak("All questions deleted successfully.");
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
          ? const Center(
              child: Text(
                'No questions saved yet.',
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                final question = _questions[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 3,
                  child: ListTile(
                    title: Text(
                      question.length > 50
                          ? "${question.substring(0, 50)}..."
                          : question,
                      style: const TextStyle(fontSize: 16),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.volume_up, color: Colors.teal),
                          tooltip: "Read Question",
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.ttsService.speak(question);
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                          tooltip: "Delete Question",
                          onPressed: () => _deleteQuestion(index),
                        ),
                      ],
                    ),
                    onTap: () => _openFullQuestion(question),
                  ),
                );
              },
            ),
    );
  }
}

class FullQuestionScreen extends StatefulWidget {
  final String question;
  final TtsService ttsService;

  const FullQuestionScreen({
    super.key,
    required this.question,
    required this.ttsService,
  });

  @override
  State<FullQuestionScreen> createState() => _FullQuestionScreenState();
}

class _FullQuestionScreenState extends State<FullQuestionScreen> {
  bool _isReading = false;
  bool _isPaused = false;

  void _startReading() async {
    if (_isReading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isReading = true;
      _isPaused = false;
    });
    await widget.ttsService.speakAndWait(widget.question);
    setState(() => _isReading = false);
  }

  void _pauseReading() {
    if (!_isReading || _isPaused) return;
    HapticFeedback.lightImpact();
    widget.ttsService.pause(); // Make sure your TtsService has pause()
    setState(() => _isPaused = true);
  }

  void _resumeReading() {
    if (!_isReading || !_isPaused) return;
    HapticFeedback.lightImpact();
    widget.ttsService.resume(); // Make sure your TtsService has resume()
    setState(() => _isPaused = false);
  }

  void _stopReading() {
    if (!_isReading) return;
    HapticFeedback.lightImpact();
    widget.ttsService.stop();
    setState(() {
      _isReading = false;
      _isPaused = false;
    });
  }

  void _cancelReading() {
    if (!_isReading) return;
    HapticFeedback.lightImpact();
    widget.ttsService.stop();
    Navigator.pop(context); // Close the full question screen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Full Question')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  widget.question,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                  onPressed: _startReading,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                  onPressed: _pauseReading,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_circle),
                  label: const Text('Resume'),
                  onPressed: _resumeReading,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  onPressed: _stopReading,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel'),
                  onPressed: _cancelReading,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

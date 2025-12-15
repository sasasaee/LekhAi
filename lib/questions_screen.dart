import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'services/question_storage_service.dart';
import 'services/tts_service.dart';
import 'paper_detail_screen.dart';
import 'models/question_model.dart'; // Import models

class QuestionsScreen extends StatefulWidget {
  final TtsService ttsService;
  const QuestionsScreen({super.key, required this.ttsService});

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final QuestionStorageService _storageService = QuestionStorageService();
  // We store the raw JSON strings; parsing happens on demand or we could parse them all.
  // Let's parse them to display metadata (like date).
  List<ParsedDocument> _papers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    widget.ttsService.speak(
      "Welcome to saved papers. Here you can review your scanned question papers.",
    );
  }

  Future<void> _loadQuestions() async {
    final docs = await _storageService.getDocuments();

    setState(() {
      _papers = docs.reversed.toList(); // Newest first (assuming storage handles append)
      _isLoading = false;
    });
  }

  void _deletePaper(int index) async {
    HapticFeedback.lightImpact();
    
    // Optimistic UI update
    setState(() {
       _papers.removeAt(index);
    });
    
    // Resync storage
    // 1. Clear all
    await _storageService.clearDocuments();
    // 2. Add back remaining (reversed to restore chronological order)
    final toSave = _papers.reversed.toList();
    for (var doc in toSave) {
        await _storageService.saveDocument(doc);
    }

    widget.ttsService.speak("Paper deleted.");
  }

  void _openPaper(ParsedDocument doc, int index) {
    HapticFeedback.lightImpact();
    
    // We need to pass the timestamp. Since we lost it in the object, 
    // we can't show the real one unless we modify the model.
    // I will modify the model in a subsequent step to hold the timestamp.
    // For now, pass a placeholder.
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaperDetailScreen(
          document: doc, 
          ttsService: widget.ttsService,
          timestamp: DateTime.now().toIso8601String(), // Temporary until model update
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Papers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Clear All',
            onPressed: () async {
              HapticFeedback.lightImpact();
              await _storageService.clearDocuments();
              _loadQuestions();
              widget.ttsService.speak("All papers deleted.");
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _papers.isEmpty
          ? const Center(
              child: Text(
                'No papers saved yet.',
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _papers.length,
              itemBuilder: (context, index) {
                final doc = _papers[index];
                final qCount = doc.sections.fold(0, (sum, s) => sum + s.questions.length);
                
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 3,
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.description),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    title: Text(
                      "Scan ${index + 1}", // Simple numbering
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("$qCount questions"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => _deletePaper(index),
                    ),
                    onTap: () => _openPaper(doc, index),
                  ),
                );
              },
            ),
    );
  }
}


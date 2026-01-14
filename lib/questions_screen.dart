import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'services/question_storage_service.dart';
import 'services/tts_service.dart';
import 'paper_detail_screen.dart';
import 'models/question_model.dart'; // Import models
import 'services/voice_command_service.dart';
import 'services/accessibility_service.dart';
import 'widgets/accessible_widgets.dart'; // Added
import 'package:google_fonts/google_fonts.dart'; 
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui'; // Add this for ImageFilter

// ... rest of imports

class QuestionsScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService? accessibilityService; // Added
  const QuestionsScreen({super.key, required this.ttsService,required this.voiceService, this.accessibilityService});

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
    // Haptic handled by AccessibleIconButton
    
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
    // Haptic handled by AccessibleListTile
    
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
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
          timestamp: DateTime.now().toIso8601String(), // Temporary until model update
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        title: Text(
          'Saved Papers',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: "Back",
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Container(
             margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
             decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              tooltip: 'Clear All',
              onPressed: () async {
                 AccessibilityService().trigger(AccessibilityEvent.warning);
                 await _storageService.clearDocuments();
                 _loadQuestions();
                 widget.ttsService.speak("All papers deleted.");
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).cardTheme.color!.withOpacity(0.8),
              Theme.of(context).scaffoldBackgroundColor,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _papers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_rounded, size: 80, color: Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'No papers saved yet.',
                        style: GoogleFonts.outfit(fontSize: 18, color: Colors.white54),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _papers.length,
                  itemBuilder: (context, index) {
                    final doc = _papers[index];
                    final qCount = doc.sections.fold(0, (sum, s) => sum + s.questions.length);
                    
                    return Dismissible(
                      key: Key(doc.toString() + index.toString()), // Simple key
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.redAccent,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) => _deletePaper(index),
                      child: Container(
                         margin: const EdgeInsets.symmetric(vertical: 8),
                         decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.03)],
                          ),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.description_outlined, color: Theme.of(context).primaryColor),
                              ),
                              title: Text(
                                "Scan ${index + 1}",
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                              ),
                              subtitle: Text(
                                "$qCount questions",
                                style: GoogleFonts.outfit(color: Colors.white54),
                              ),
                              trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
                              onTap: () {
                                AccessibilityService().trigger(AccessibilityEvent.action);
                                _openPaper(doc, index);
                              },
                            ),
                          ),
                        ),
                      ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1, end: 0),
                    );
                  },
                ),
        ),
      ),
    );
  }
}


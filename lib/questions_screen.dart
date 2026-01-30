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

import 'exam_info_screen.dart';
import 'dart:async';
import 'services/stt_service.dart';

// ... rest of imports

class QuestionsScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService? accessibilityService;
  final ParsedDocument? document;
  final String? studentName;
  final String? studentId;
  final bool examMode;
  final bool isSelectionMode; // New flag

  const QuestionsScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    this.accessibilityService,
    this.document,
    this.studentName,
    this.studentId,
    this.examMode = false,
    this.isSelectionMode = false, // Default false
  });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final QuestionStorageService _storageService = QuestionStorageService();
  // We store the raw JSON strings; parsing happens on demand or we could parse them all.
  // Let's parse them to display metadata (like date).
  List<ParsedDocument> _papers = [];
  bool _isLoading = true;
  final SttService _sttService = SttService();
  bool _isListening = false;
  // bool _isSelectingForExam = false; // REMOVED
  //int _examTimer = 0; // seconds
  //bool _timerStarted = false;
  int _currentQuestionIndex = 0;
  Timer? _examTimer; // This controls the ticking
  int _remainingSeconds = 0; // This holds the time left
  bool _isExamRunning = false;
  // bool _showCountdown = false; // Removed
  // int _countdownValue = 3; // Removed
  // bool _isRecordingAnswer = false; // Removed

  List<dynamic> _allExamQuestions = [];

  @override
  void initState() {
    super.initState();
    _loadQuestions();

    if (widget.examMode) {
    // Exam sequence initiation handled by PaperDetailScreen logic now.
    // _startExamSequence(); // Removed
    } else {
      widget.ttsService.speak("Welcome to saved papers.");
      _initVoiceCommandListener();
    }
  }

  @override
  void dispose() {
    _examTimer?.cancel();
    _sttService.stopListening();
    super.dispose();
  }

  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      tts: widget.ttsService, // Pass TTS to enable auto-pause
      onStatus: (status) {
        // Just log status, rely on SttService internal loop for restarts
        // print("QuestionsScreen STT Status: $status");
      },
      onError: (error) => print("QuestionsScreen STT Error: $error"),
    );

    if (available) {
      _startCommandStream();
    }
  }

  void _startCommandStream() {
    if (!_sttService.isAvailable || _isListening) return;

    _sttService.startListening(
      localeId: "en-US",
      onResult: (text) {
        print("QuestionsScreen received: '$text'");
        final result = widget.voiceService.parse(
          text,
          context: VoiceContext.savedPapers,
        );
        if (result.action != VoiceAction.unknown) {
          _handleVoiceCommand(result);
        }
      },
    );
  }

  void _handleVoiceCommand(CommandResult result) async {
    // Handle local list selection
    if (result.action == VoiceAction.openPaper) {
      final int? targetIndex = result.payload;
      // Payload is 1-based (user says "1"), convert to 0-based
      if (targetIndex != null) {
        final int actualIndex = targetIndex - 1;
        if (actualIndex >= 0 && actualIndex < _papers.length) {
          await widget.ttsService.speak("Opening paper $targetIndex.");
          _openPaper(_papers[actualIndex], actualIndex);
        } else {
          await widget.ttsService.speak("Item $targetIndex not found.");
        }
      }
      return;
    }

    if (result.action == VoiceAction.deletePaper) {
      final int? targetIndex = result.payload;
      if (targetIndex != null) {
        final int actualIndex = targetIndex - 1;
        if (actualIndex >= 0 && actualIndex < _papers.length) {
          await widget.ttsService.speak("Deleting paper $targetIndex.");
          _deletePaper(actualIndex);
        } else {
          await widget.ttsService.speak("Paper $targetIndex not found.");
        }
      }
      return;
    }

    // Delegate other global commands
    widget.voiceService.performGlobalNavigation(result);
  }

  //   if (_timerStarted) return;
  //   _timerStarted = true;

  //   const totalSeconds = 60 * 60; // Example: 1-hour exam
  //   int remainingSeconds = totalSeconds;

  //   widget.ttsService.speak("The exam timer is starting now.");

  //   while (remainingSeconds > 0 && mounted) {
  //     setState(() => _examTimer = remainingSeconds);
  //     await Future.delayed(const Duration(seconds: 1));
  //     remainingSeconds--;
  //   }

  //   if (mounted) {
  //     setState(() => _examTimer = 0);
  //     widget.ttsService.speak("Time's up!");
  //   }
  // }

  // Removed _startExamSequence, _beginExam, _readCurrentQuestion, _nextQuestion as they are handled in PaperDetailScreen now.

  // _confirmEndExam moved to PaperDetailScreen

  void _finishExam() {
    _examTimer?.cancel(); // Cancel any local timer if existing
    widget.ttsService.speak("Exam finished. Returning to dashboard.");
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  Future<void> _loadQuestions() async {
    final docs = await _storageService.getDocuments();

    setState(() {
      _papers = docs.reversed
          .toList(); // Newest first (assuming storage handles append)
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

    // Stop local listener
    _sttService.stopListening();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaperDetailScreen(
          document: doc,
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
          timestamp: DateTime.now()
              .toIso8601String(), // Temporary until model update
          examMode: widget.examMode, // Pass the mode
        ),
      ),
    ).then((_) => _initVoiceCommandListener());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.examMode ? 'Exam Mode' : 'Saved Papers',
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
          child: AccessibleIconButton(
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
            child: AccessibleIconButton(
              icon: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.redAccent,
              ),
              tooltip: 'Clear All',
              onPressed: () async {
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
              : _papers.isEmpty && !widget.examMode
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        size: 80,
                        color: Colors.white.withOpacity(0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No papers saved yet.',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [

                    // Show exam header only if exam mode is active
                    if (widget.examMode)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.deepPurple.withOpacity(0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Exam Mode Activated",
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (widget.studentName != null)
                              Text(
                                "Name: ${widget.studentName}",
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            if (widget.studentId != null)
                              Text(
                                "Student ID: ${widget.studentId}",
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              "Time Remaining: ${_formatTime(_remainingSeconds)}",
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // List of papers
                    ..._papers.asMap().entries.map((entry) {
                      int index = entry.key;
                      ParsedDocument doc = entry.value;
                      final qCount = doc.sections.fold(
                        0,
                        (sum, s) => sum + s.questions.length,
                      );

                      return Dismissible(
                        // key: Key(doc.toString() + index.toString()),
                        key: Key(doc.id),
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
                              colors: [
                                Colors.white.withOpacity(0.08),
                                Colors.white.withOpacity(0.03),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: AccessibleListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.description_outlined,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                                title: Text(
                                  doc.name != null && doc.name!.isNotEmpty
                                      ? doc.name!
                                      : "Scan ${index + 1}",
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                subtitle: Text(
                                  "$qCount questions",
                                  style: GoogleFonts.outfit(
                                    color: Colors.white54,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white24,
                                  size: 16,
                                ),
                                onTap: () {
                                    // 1. CHECK: Are we in Exam Selection Mode?
                                    if (widget.isSelectionMode) {
                                      // YES -> Go to Exam Info (Rules, Timer, Name)
                                      // AccessibilityService().trigger(AccessibilityEvent.action); // Handled by widget
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ExamInfoScreen(
                                            document: doc,
                                            ttsService: widget.ttsService,
                                            voiceService: widget.voiceService,
                                            accessibilityService:
                                                widget.accessibilityService ??
                                                AccessibilityService(),
                                            sttService: _sttService,
                                          ),
                                        ),
                                      );
                                    } else {
                                      // NO -> Just open the paper normally (Review Mode)
                                      _openPaper(doc, index);
                                    }
                                },
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1, end: 0),
                      );
                    }).toList(),

                    if (widget.examMode) ...[
                      // "End Exam" moved to PaperDetailScreen as per user request
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

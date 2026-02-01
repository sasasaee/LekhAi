import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'services/gemini_question_service.dart';
import 'services/question_storage_service.dart';
import 'models/question_model.dart';
import 'services/tts_service.dart';
import 'services/stt_service.dart';
import 'services/audio_recorder_service.dart';
import 'services/voice_command_service.dart'; // Added
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'services/kiosk_service.dart'; // Added KioskService
import 'services/pdf_service.dart'; // Added PdfService
import 'package:open_filex/open_filex.dart'; // Added for View PDF
import 'package:share_plus/share_plus.dart'; // Added for Share PDF

// --- PAPER DETAIL SCREEN ---

import 'services/accessibility_service.dart';
import 'widgets/accessible_widgets.dart'; // Added
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
// import 'package:permission_handler/permission_handler.dart'; // Added for Save PDF permissions
// import 'package:path_provider/path_provider.dart'; // Added for downloads path
// import 'exam_info_screen.dart';
// import 'dart:convert';

class PaperDetailScreen extends StatefulWidget {
  final ParsedDocument document;
  final TtsService ttsService;
  final VoiceCommandService voiceService; // Added
  final AccessibilityService? accessibilityService;
  final String timestamp;
  final bool examMode;
  final String? studentName;
  final String? studentId;
  final int? examDurationSeconds;

  const PaperDetailScreen({
    super.key,
    required this.document,
    required this.ttsService,
    required this.voiceService, // Added
    this.accessibilityService,
    required this.timestamp,
    this.examMode =
        false, // Default to false so it works for normal scanning too
    this.studentName,
    this.studentId,
    this.examDurationSeconds,
  });

  @override
  State<PaperDetailScreen> createState() => _PaperDetailScreenState();
}

class _PaperDetailScreenState extends State<PaperDetailScreen> {
  late ParsedDocument _document;
  final GeminiQuestionService _geminiService = GeminiQuestionService();
  final QuestionStorageService _storageService = QuestionStorageService();
  final SttService _sttService = SttService();
  final bool _isListening =
      false; // Effectively constant in this screen's logic

  Timer? _examTimer;
  late int _remainingSeconds;

  bool _showCountdown = false;
  int _countdownValue = 3;

  bool _isWaitingForConfirmation = false;
  bool _kioskEnabled = false;
  int _totalExamSeconds = 3600;

  // Alert Flags
  bool _alert50Triggered = false;
  bool _alert25Triggered = false;
  bool _alert10Triggered = false;
  bool _alert1MinTriggered = false;

  int? _examStartTimestamp; // Cache for performance

  @override
  void initState() {
    super.initState();
    _totalExamSeconds = widget.examDurationSeconds ?? 3600;
    _remainingSeconds = _totalExamSeconds;
    _document = widget.document;

    // Init Kiosk Service Observer
    KioskService().init();

    AccessibilityService().trigger(AccessibilityEvent.navigation);
    _initVoiceCommandListener();

    if (widget.examMode) {
      // Don't start immediately. Ask for confirmation first.
      // Small delay to let the screen build and previous TTS finish.
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _confirmAndStartKiosk();
      });
    }
  }

  void _confirmAndStartKiosk() {
    if (!mounted) return;
    setState(() {
      _isWaitingForConfirmation = true;
    });

    // Audio Prompt
    widget.ttsService.speak(
      "Exam will start in locked mode. Say Start to confirm. Or Cancel to exit.",
    );

    // Visual Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Exam Mode Confirmation"),
          content: const Text(
            "The app will be locked to prevent exiting.\nDo you want to proceed?",
          ),
          actions: [
            AccessibleTextButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                _handleCancelConfirmation();
              },
              child: const Text("Cancel"),
            ),
            AccessibleElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                _handleConfirmExamStart();
              },
              child: const Text("Start Exam"),
            ),
          ],
        ),
      ),
    );
  }

  void _handleConfirmExamStart() async {
    setState(() {
      _isWaitingForConfirmation = false;
      _kioskEnabled = true;
    });

    // 1. Enable Kiosk Mode
    await KioskService().enableKioskMode();

    // 2. Start Countdown
    _startCountdownSequence();
  }

  void _handleCancelConfirmation() {
    setState(() {
      _isWaitingForConfirmation = false;
    });
    Navigator.pop(context); // Go back to scan/list screen
  }

  void _startCountdownSequence() {
    setState(() {
      _showCountdown = true;
      _countdownValue = 3;
    });

    widget.ttsService.speak("Exam starting in 3...");

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdownValue > 1) {
          _countdownValue--;
          widget.ttsService.speak("$_countdownValue...");
        } else {
          timer.cancel();
          _showCountdown = false;
          _initExamSession(); // Initialize Timer & Persistence
        }
      });
    });
  }

  Future<void> _initExamSession() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check for existing session (Crash Recovery)
    // For this simplified version, we'll overwrite if it's a "new" entry,
    // but in a real app check IDs. For now, assume new exam or simple restart.
    // Let's just SAVE the start time.
    await prefs.setInt('exam_start_timestamp', now);
    await prefs.setInt('exam_total_duration', _totalExamSeconds);

    setState(() {
      _examStartTimestamp = now;
    });

    _startExamTimer();

    int minutes = _remainingSeconds ~/ 60;
    widget.ttsService.speak("Exam started. You have $minutes minutes.");
  }

  @override
  void dispose() {
    _examTimer?.cancel();
    _sttService.stopListening();
    // if (_kioskEnabled) {
    KioskService().disableKioskMode();
    // }
    KioskService().dispose();
    super.dispose();
  }

  void _startExamTimer() {
    _examTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      int remaining = _remainingSeconds;

      // Fast Drift Correction using cached timestamp
      if (_examStartTimestamp != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsedSecs = (now - _examStartTimestamp!) ~/ 1000;
        remaining = _totalExamSeconds - elapsedSecs;
      } else {
        remaining--;
      }

      setState(() {
        _remainingSeconds = remaining;
      });

      if (_remainingSeconds > 0) {
        // Dynamic Alerts
        double progress = _remainingSeconds / _totalExamSeconds;

        // Approx 50% left
        if (progress <= 0.50 && !_alert50Triggered) {
          _alert50Triggered = true;
          _speakTimeRemaining("Halftime.");
        }

        // Approx 25% left
        if (progress <= 0.25 && !_alert25Triggered) {
          _alert25Triggered = true;
          _speakTimeRemaining("Attention.");
        }
        // Approx 10% left
        if (progress <= 0.10 && !_alert10Triggered) {
          _alert10Triggered = true;
          _speakTimeRemaining("Warning.");
        }

        // Critical 1 minute alert
        if (_remainingSeconds <= 60 &&
            !_alert1MinTriggered &&
            _totalExamSeconds > 120) {
          _alert1MinTriggered = true;
          widget.ttsService.speak("1 minute remaining.");
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("1 Minute Remaining")));
        }
      } else {
        // Time Up
        timer.cancel();
        widget.ttsService.speak(
          "Time is up. Exam finished. Submitting your answers.",
        );
        KioskService().disableKioskMode();
        setState(() {
          _kioskEnabled = false;
        });
        // Force exam completion flow (PDF generation)
        if (mounted) _finalizeExam();
      }
    });
  }

  void _speakTimeRemaining(String prefix) {
    int mins = _remainingSeconds ~/ 60;
    String timeStr = mins > 0
        ? "$mins minutes remaining."
        : "$_remainingSeconds seconds remaining.";
    widget.ttsService.speak("$prefix $timeStr");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$prefix $timeStr"),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _confirmEndExam() {
    // 1. Calculate Progress
    int total = 0;
    int answered = 0;
    for (var section in _document.sections) {
      for (var q in section.questions) {
        total++;
        bool hasText = q.answer.isNotEmpty;
        bool hasAudio = q.audioPath != null && q.audioPath!.isNotEmpty;
        if (hasText || hasAudio) answered++;
      }
    }

    // 2. Announce
    widget.ttsService.speak(
      "Ending exam. You have answered $answered out of $total questions. Double tap confirm to submit.",
    );

    // 3. Show Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          "Submit Exam?",
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        content: Text(
          "You have answered $answered out of $total questions.\nAre you sure you want to submit?",
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          AccessibleTextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.ttsService.speak("Exam continued.");
            },
            child: Text(
              "Cancel",
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
          AccessibleTextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finalizeExam(); // Calls existing finish logic
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(
              "Submit",
              style: GoogleFonts.outfit(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  // --- VOICE COMMAND LOGIC FOR LIST SCREEN ---
  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      onStatus: (status) {
        debugPrint("Paper List STT Status: $status");
        // Keep-alive loop for the listener
        if ((status == 'notListening' || status == 'done') && !_isListening) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isListening) _startCommandStream();
          });
        }
      },
      onError: (error) => debugPrint("Paper List STT Error: $error"),
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
        final result = widget.voiceService.parse(
          text,
          context: _isWaitingForConfirmation
              ? VoiceContext.confirmExamStart
              : VoiceContext.paperDetail,
        );
        if (result.action != VoiceAction.unknown) {
          _executeVoiceCommand(result);
        }
      },
    );
  }

  void _executeVoiceCommand(CommandResult result) async {
    switch (result.action) {
      case VoiceAction.confirmExamStart:
        if (_isWaitingForConfirmation) {
          // If dialog is open, pop it first (we know it's top of stack)
          if (Navigator.canPop(context)) Navigator.pop(context);
          _handleConfirmExamStart();
        }
        break;

      case VoiceAction.cancelExamStart:
        if (_isWaitingForConfirmation) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          _handleCancelConfirmation();
        }
        break;

      case VoiceAction.goToQuestion:
        // payload contains the question number (e.g., 1, 2, 3)
        final int? qNum = result.payload;
        if (qNum != null) {
          _openQuestionByNumber(qNum);
        }
        break;

      case VoiceAction.goBack:
        if (_kioskEnabled) {
          widget.ttsService.speak(
            "Exam is locked. You cannot go back until you submit.",
          );
          return;
        }
        await widget.ttsService.speak("Going back to home.");
        if (mounted) Navigator.pop(context);
        break;

      case VoiceAction.saveResult:
         if (!_kioskEnabled) {
             await widget.ttsService.speak("Saving paper.");
             if (mounted) _savePaper(context);
         } else {
             widget.ttsService.speak("In exam mode, please submit exam to save.");
         }
         break;

      case VoiceAction.submitExam: // Use this as "Save" for this screen
        if (_kioskEnabled) {
          _confirmEndExam(); 
        } else {
          await widget.ttsService.speak("Saving paper progress.");
          if (mounted) _savePaper(context);
        }
        break;

      case VoiceAction.scanQuestions:
        widget.ttsService.speak("Scanning new page.");
        _onAddPage(context);
        break;

      default:
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
  }

  void _openNextQuestion(ParsedQuestion currentQuestion, {bool replace = false}) {
    // Flatten list of all questions to find index
    List<ParsedQuestion> allQuestions = [];
    for (var section in _document.sections) {
      allQuestions.addAll(section.questions);
    }

    int index = allQuestions.indexOf(currentQuestion);
    if (index >= 0 && index < allQuestions.length - 1) {
      final nextQ = allQuestions[index + 1];
      // Find context for nextQ
      String? contextText;
      for (var section in _document.sections) {
        if (section.questions.contains(nextQ)) {
          contextText = section.context;
          break;
        }
      }

      widget.ttsService.speak("Opening next question.");

      // Stop local listening before pushing new screen
      _sttService.stopListening();

      final route = MaterialPageRoute(
        builder: (_) => SingleQuestionScreen(
          question: nextQ,
          contextText: contextText,
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
          onNext: () {
            // Replace current with next (recursive)
            _openNextQuestion(nextQ, replace: true);
          },
          onJump: (n) {
             // Replace current with jump target
             _openQuestionByNumber(n, replace: true);
          },
        ),
      );

      if (replace) {
        Navigator.pushReplacement(context, route).then((_) {
            _initVoiceCommandListener();
        });
      } else {
        Navigator.push(context, route).then((_) {
          _initVoiceCommandListener();
        });
      }

    } else {
      widget.ttsService.speak("No more questions.");
    }
  }

  // Helper to open a question via voice
  void _openQuestionByNumber(int number, {bool replace = false}) {
    ParsedQuestion? target;
    String? contextText;

    // Search through sections for the question number
    for (var section in _document.sections) {
      for (var q in section.questions) {
        if (q.number == number.toString()) {
          target = q;
          contextText = section.context;
          break;
        }
      }
    }

    if (target != null) {
      widget.ttsService.speak("Opening question $number.");

      // Stop local listening before pushing new screen
      _sttService.stopListening();

      final route = MaterialPageRoute(
        builder: (_) => SingleQuestionScreen(
          question: target!,
          contextText: contextText,
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
          onNext: () {
            _openNextQuestion(target!, replace: true);
          },
          onJump: (n) {
             _openQuestionByNumber(n, replace: true);
          },
        ),
      );

      if (replace) {
        Navigator.pushReplacement(context, route).then((_) {
             _initVoiceCommandListener();
        });
      } else {
         Navigator.push(context, route).then((_) {
           _initVoiceCommandListener();
        });
      }

    } else {
      widget.ttsService.speak("Question $number not found.");
    }
  }

  Future<void> _processWithGemini(BuildContext context, String apiKey) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Processing with Gemini AI... please wait."),
      ),
    );

    try {
      AccessibilityService().trigger(AccessibilityEvent.loading);
      final newDoc = await _geminiService.processImage(image.path, apiKey);
      AccessibilityService().trigger(AccessibilityEvent.success);

      setState(() {
        _document.sections.addAll(newDoc.sections);
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Successfully added questions from Gemini!"),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showCountdown) {
      // Countdown Screen
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.deepPurple,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Starting Exam",
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                      "$_countdownValue",
                      style: GoogleFonts.outfit(
                        fontSize: 120,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                    .animate(key: ValueKey(_countdownValue))
                    .scale(duration: 300.ms, curve: Curves.easeOutBack),
              ],
            ),
          ),
        ),
      );
    }

    final items = <_ListItem>[];

    if (_document.header.isNotEmpty) {
      items.add(_HeaderItem(_document.header.join("\n")));
    }

    for (var section in _document.sections) {
      if ((section.title != null && section.title!.isNotEmpty) ||
          (section.context != null && section.context!.isNotEmpty)) {
        items.add(_SectionItem(section.title, section.context));
      }

      for (var q in section.questions) {
        items.add(_QuestionItem(q, section.context));
      }
    }

    String dateStr = "Unknown Date";
    try {
      final dt = DateTime.parse(widget.timestamp);
      dateStr = "${dt.day}/${dt.month} ${dt.hour}:${dt.minute}";
    } catch (_) {}

    return PopScope(
      canPop: !_kioskEnabled,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _kioskEnabled) {
          // widget.ttsService.speak("Exam is locked.");
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(
            _document.name != null && _document.name!.isNotEmpty
                ? _document.name!
                : 'Paper $dateStr',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: Container(
            margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              tooltip: "Back",
              onPressed: () {
                if (_kioskEnabled) {
                  widget.ttsService.speak(
                    "Exam is locked. Finish the exam to exit.",
                  );
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("Exam Locked")));
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          actions: [
            if (!widget.examMode)
              Container(
                margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: AccessibleIconButton(
                  icon: const Icon(Icons.save_rounded, color: Colors.white),
                  tooltip: "Save Paper",
                  onPressed: () => _savePaper(context),
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
                Theme.of(context).cardTheme.color!.withValues(alpha: 0.8),
                Theme.of(context).scaffoldBackgroundColor,
                Colors.black,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // --- 1. INSERT THE TIMER HERE ---
                if (widget.examMode)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          _formatTime(_remainingSeconds), // 60:00 countdown
                          style: GoogleFonts.outfit(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: _remainingSeconds < 900
                                ? Colors.redAccent
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Student: ${widget.studentName ?? 'Unknown'}",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          "ID: ${widget.studentId ?? '---'}",
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),

                // --- 2. YOUR EXISTING LIST GOES HERE ---
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length + (widget.examMode ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (widget.examMode && index == items.length) {
                        return Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: AccessibleElevatedButton(
                            onPressed: _confirmEndExam,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              minimumSize: const Size(double.infinity, 56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              "End Exam",
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      }

                      // COPY AND PASTE YOUR EXISTING ITEM BUILDER CODE HERE
                      // (The exact same code you already have for _HeaderItem, _SectionItem, _QuestionItem)

                      final item = items[index];

                      if (item is _HeaderItem) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              item.text,
                              style: GoogleFonts.outfit(
                                fontStyle: FontStyle.italic,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        );
                      } else if (item is _SectionItem) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.title != null && item.title!.isNotEmpty)
                                Text(
                                  item.title!,
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              if (item.context != null &&
                                  item.context!.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: Colors.amber.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item.context!,
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      color: Colors.amber.shade100,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      } else if (item is _QuestionItem) {
                        final q = item.question;
                        final qTitle = q.number != null
                            ? "Q${q.number}"
                            : "Question";
                        final marks = q.marks != null ? "(${q.marks})" : "";

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.08),
                                Colors.white.withValues(alpha: 0.03),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
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
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: AccessibleListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).primaryColor.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    q.number ?? "Q",
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  "$qTitle $marks",
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    q.prompt + (q.body.isNotEmpty ? "..." : ""),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white24,
                                  size: 16,
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SingleQuestionScreen(
                                        question: q,
                                        contextText: item.context,
                                        ttsService: widget.ttsService,
                                        voiceService: widget.voiceService,
                                        accessibilityService:
                                            widget.accessibilityService,
                                        onNext: () {
                                          Navigator.pop(context);
                                          _openNextQuestion(q);
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColorDark,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: () => _onAddPage(context),
            backgroundColor: Colors.transparent,
            elevation: 0,
            tooltip: 'Add Page',
            child: const Icon(Icons.add_a_photo_outlined, color: Colors.white),
          ),
        ),
      ),
    ); // Close PopScope
  }

  Future<void> _onAddPage(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Process New Page"),
          content: Text(
            apiKey != null && apiKey.isNotEmpty
                ? "Gemini API Key detected. Would you like to use Gemini AI for superior accuracy?"
                : "No Gemini API Key found. Using standard Local OCR.",
          ),
          actions: [
            if (apiKey != null && apiKey.isNotEmpty)
              AccessibleTextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _processWithGemini(context, apiKey);
                },
                child: const Text("Use Gemini AI"),
              ),
            AccessibleTextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Local Processing unimplemented context..."),
                  ),
                );
              },
              child: Text(
                apiKey != null && apiKey.isNotEmpty
                    ? "Use Local OCR"
                    : "Proceed",
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _savePaper(BuildContext context) async {
    try {
      // 1. Prompt for name (Original Logic)
      final String? name = await _showNameDialog();
      if (name == null || name.isEmpty) {
        // User cancelled or entered empty name
        return;
      }

      // 2. Update document with name
      final newDoc = ParsedDocument(
        id: _document.id,
        name: name,
        header: _document.header,
        sections: _document.sections,
      );

      setState(() {
        _document = newDoc;
      });

      // 3. Save to Storage (JSON)
      await _storageService.saveDocument(_document);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Paper saved successfully!")),
        );
      }
    } catch (e) {
      AccessibilityService().trigger(AccessibilityEvent.error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _finalizeExam() async {
    // This is called when Time Up or User explicitly submits via voice/menu

    // Ensure Kiosk Mode is disabled immediately
    await KioskService().disableKioskMode();
    if (mounted) {
      setState(() {
        _kioskEnabled = false;
        _showCountdown = false; // Ensure countdown UI is gone
        _examTimer?.cancel(); // Ensure timer is stopped
      });
    }

    try {
      String sName = widget.studentName ?? "Unknown Student";
      String sId = widget.studentId ?? "Unknown ID";
      String pName = _document.name ?? "Exam Paper";

      // Re-saving document to ensure answers are persisted
      await _storageService.saveDocument(_document);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Generating PDF Result...")),
        );
      }

      final pdfFile = await PdfService().generateExamPdf(
        studentName: sName,
        studentId: sId,
        examName: pName,
        document: _document,
      );

      if (mounted) {
        // Show specific dialog with View, Share, Save options
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Exam Completed"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Your exam has been submitted and the PDF report generated.",
                ),
                const SizedBox(height: 20),
                AccessibleElevatedButton(
                  onPressed: () => _viewPdf(pdfFile.path),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.visibility),
                      SizedBox(width: 8),
                      Text("View PDF"),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                AccessibleElevatedButton(
                  onPressed: () => _sharePdf(pdfFile.path),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.share),
                      SizedBox(width: 8),
                      Text("Share PDF"),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                AccessibleElevatedButton(
                  onPressed: () => _savePdfToDownloads(pdfFile),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download),
                      SizedBox(width: 8),
                      Text("Save to Downloads"),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              AccessibleTextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context); // Exit PaperDetailScreen
                },
                child: const Text("Close & Exit"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      AccessibilityService().trigger(AccessibilityEvent.error);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error generating PDF: $e")));
      }
    }
  }

  Future<void> _viewPdf(String path) async {
    await OpenFilex.open(path);
  }

  Future<void> _sharePdf(String path) async {
    await Share.shareXFiles([XFile(path)], text: 'Exam Report');
  }

  Future<void> _savePdfToDownloads(File pdfFile) async {
    try {
      // Simple Approach for Android 10+ (Scoped Storage) and below
      // Using /storage/emulated/0/Download/ folder directly
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        // Fallback/IOS (not primarily targeted but safe)
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir != null && !downloadsDir.existsSync()) {
        // Try creating it?
        downloadsDir.createSync(recursive: true);
      }

      if (downloadsDir != null) {
        final fileName = pdfFile.uri.pathSegments.last;
        final newPath = "${downloadsDir.path}/$fileName";
        await pdfFile.copy(newPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Saved to Downloads: $fileName")),
          );
        }
      } else {
        throw "Downloads directory not found";
      }
    } catch (e) {
      // Fallback to Share if permission fails or other error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Could not save automatically. Please use Share to save.",
            ),
          ),
        );
        _sharePdf(pdfFile.path); // Use share as fallback
      }
    }
  }

  Future<String?> _showNameDialog() async {
    // Revert to simple name dialog
    final TextEditingController nameController = TextEditingController();
    if (_document.name != null) {
      nameController.text = _document.name!;
    }
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Name this Paper"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter a name for this paper:"),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "e.g. Physics Chapter 1",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          AccessibleTextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text("Cancel"),
          ),
          AccessibleElevatedButton(
            onPressed: () {
              final text = nameController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx, text);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}

// --- HELPER CLASSES ---

abstract class _ListItem {}

class _HeaderItem extends _ListItem {
  final String text;
  _HeaderItem(this.text);
}

class _SectionItem extends _ListItem {
  final String? title;
  final String? context;
  _SectionItem(this.title, this.context);
}

class _QuestionItem extends _ListItem {
  final ParsedQuestion question;
  final String? context;
  _QuestionItem(this.question, this.context);
}

// --- SINGLE QUESTION SCREEN ---

class SingleQuestionScreen extends StatefulWidget {
  final ParsedQuestion question;
  final String? contextText;
  final TtsService ttsService;
  final VoiceCommandService voiceService; // Added
  final AccessibilityService? accessibilityService;
  final VoidCallback? onNext; // Added
  final Function(int)? onJump; // Added

  const SingleQuestionScreen({
    super.key,
    required this.question,
    this.contextText,
    required this.ttsService,
    required this.voiceService,
    this.accessibilityService,
    this.onNext,
    this.onJump,
  });

  @override
  State<SingleQuestionScreen> createState() => _SingleQuestionScreenState();
}

class _SingleQuestionScreenState extends State<SingleQuestionScreen> {
  bool _isReading = false;
  bool _isPaused = false;

  double _displaySpeed = 1.0;
  double _currentVolume = 1.0;
  bool _playContext = false;

  final SttService _sttService = SttService();
  bool _isListening = false;
  final TextEditingController _answerController = TextEditingController();

  final AudioRecorderService _audioRecorderService = AudioRecorderService();
  bool _isProcessingAudio = false;
  String? _tempAudioPath;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Hands-Free State
  bool _isAppending = true;

  @override
  void initState() {
    super.initState();
    AccessibilityService().trigger(AccessibilityEvent.navigation);
    _stopAndInit();
    _answerController.text = widget.question.answer;

    // Start Command Listener
    _initVoiceCommandListener();

    _answerController.addListener(() {
      widget.question.answer = _answerController.text;
    });
  }

  // --- VOICE COMMAND LOGIC ---
  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      onStatus: (status) {
        debugPrint("STT Status: $status");
        // FIX: If the engine stops (status 'done' or 'notListening') and
        // the student isn't currently dictating an answer, restart it.
        if ((status == 'notListening' || status == 'done') && !_isListening) {
          // A 500ms delay ensures the OS has fully released the mic before we re-acquire it
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isListening) _startCommandStream();
          });
        }
      },
      onError: (error) => debugPrint("STT Error: $error"),
    );

    if (available) {
      _startCommandStream();
    }
  }

  // NEW: Helper method to handle the actual listening call
  void _startCommandStream() {
    // Ensure the service is ready and we aren't recording an answer (Gemini mode)
    if (!_sttService.isAvailable || _isListening) return;

    _sttService.startListening(
      localeId: "en-US",
      onResult: (text) {
        // Block command execution if the student is currently dictating an answer
        if (_isListening) return;

        final result = widget.voiceService.parse(text, context: VoiceContext.question);
        if (result.action != VoiceAction.unknown) {
          _executeVoiceCommand(result);
        }
      },
    );
  }

  void _executeVoiceCommand(CommandResult result) async {
    // --- READING PHASE GUARD ---
    // If we are currently reading, we ONLY accept:
    // 1. Stop Reading (pauseReading / stopDictation)
    // 2. Repeat Question (readQuestion)
    if (_isReading) {
      if (result.action == VoiceAction.pauseReading ||
          result.action == VoiceAction.stopDictation) {
        _stopReadingQuestion();
        return;
      }
      if (result.action == VoiceAction.readQuestion) {
        _startReadingQuestion(); // Restart/Repeat
        return;
      }
      // Reject all other commands (silently or with log)
      debugPrint("Ignored command '${result.action}' during reading phase.");
      return;
    }

    switch (result.action) {
      case VoiceAction.readQuestion:
        _startReadingQuestion();
        break;

      case VoiceAction.startDictation:
        await widget.ttsService.speak("Starting dictation.");
        _startListening(append: true);
        break;

      case VoiceAction.appendAnswer:
        await widget.ttsService.speak("Appending to answer.");
        _startListening(append: true);
        break;

      case VoiceAction.overwriteAnswer:
        await widget.ttsService.speak("Overwriting answer. Speak new answer.");
        _startListening(append: false);
        break;

      case VoiceAction.clearAnswer:
        _clearAnswer();
        break;

      case VoiceAction.readLastSentence:
        _readLastSentence();
        break;

      case VoiceAction.stopDictation:
        // If we are NOT reading (caught above), this might mean "Stop Dictation"
        // But dictation captures its own "Stop" usually.
        // If we are idle, "Stop" might just be feedback.
        await widget.ttsService.speak("Dictation is not active.");
        break;

      case VoiceAction.pauseReading:
         // If idle, maybe just say nothing or "Already stopped".
        break;

      case VoiceAction.playAudioAnswer:
         if (widget.question.audioPath != null) {
            await widget.ttsService.speak("Playing answer.");
            await _audioPlayer.play(DeviceFileSource(widget.question.audioPath!));
         } else {
            await widget.ttsService.speak("No audio answer recorded.");
         }
         break;

      case VoiceAction.toggleReadContext:
         setState(() => _playContext = !_playContext);
         await widget.ttsService.speak("Context reading ${_playContext ? 'enabled' : 'disabled'}.");
         break;

      case VoiceAction.readAnswer:
        widget.ttsService.speak(
          "Your current answer is: ${_answerController.text}",
        );
        break;

      case VoiceAction.changeSpeed:
        _changeSpeed();
        await widget.ttsService.speak(
          "Speed changed to ${_displaySpeed.toStringAsFixed(2)}.",
        );
        break;

      case VoiceAction.goBack:
        await widget.ttsService.speak("Going back.");
        if (mounted) Navigator.pop(context);
        break;

      case VoiceAction.nextPage:
        if (widget.onNext != null) {
          widget.onNext!();
        } else {
          widget.ttsService.speak("No next question.");
        }
        break;

      case VoiceAction.previousPage:
        // Treat as go back for now, or could link to previous if we passed a callback
        await widget.ttsService.speak("Going back.");
        if (mounted) Navigator.pop(context);
        break;

      case VoiceAction.goToQuestion:
        if (result.payload is int && widget.onJump != null) {
          widget.onJump!(result.payload);
        } else {
             widget.ttsService.speak("Jump not available.");
        }
        break;

      default:
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
  }

  Future<void> _startReadingQuestion() async {
    // 1. Reset State
    await widget.ttsService.stop();
    if (!mounted) return;
    setState(() {
      _isReading = true;
      _isPaused = false;
      _lastSpeechStartOffset = 0;
    });

    // 2. Prepare FULL Text (Atomic)
    // Using periods and spaces to ensure natural pauses
    final sb = StringBuffer();
    sb.write("Reading question now... ");
    // Replace newlines with period-space to prevent run-on sentences if newlines are squashed
    sb.write(_fullText.replaceAll('\n', '. '));
    sb.write(" ... End of question. Say ‘Start answering’ when ready.");

    // 3. One Speak Call
    await widget.ttsService.speakAndWait(sb.toString());

    // 4. Cleanup
    if (mounted) {
      setState(() {
        _isReading = false;
      });
    }
  }

  Future<void> _stopReadingQuestion() async {
    await widget.ttsService.stop();
    if (mounted) {
      setState(() {
        _isReading = false;
        _isPaused = false;
        _lastSpeechStartOffset = 0;
      });
    }
    await widget.ttsService.speak(
      "Reading stopped. Say ‘Read question’ to hear it again.",
    );
  }

  Future<void> _stopAndInit() async {
    await widget.ttsService.stop();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await widget.ttsService.loadPreferences();
    if (mounted) {
      setState(() {
        _displaySpeed = prefs['speed'] ?? 1.0;
        _currentVolume = prefs['volume'] ?? 1.0;
      });
      await widget.ttsService.setSpeed(_displaySpeed * 0.5);
      await widget.ttsService.setVolume(_currentVolume);
    }
  }

  @override
  void dispose() {
    _sttService.stopListening(); // Stop command listener
    _answerController.dispose();
    widget.ttsService.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- VOLUME LOGIC ---
  void _changeVolume() async {
    double newVolume = _currentVolume + 0.2;
    if (newVolume > 1.01) newVolume = 0.2;

    int currentPos = _currentAbsolutePosition;
    bool wasReading = _isReading && !_isPaused;
    bool wasPaused = _isPaused;

    await widget.ttsService.stop();

    setState(() => _currentVolume = newVolume);
    await widget.ttsService.setVolume(newVolume);
    await widget.ttsService.savePreferences(
      speed: _displaySpeed,
      volume: newVolume,
    );

    if (wasReading) {
      await _speakFromPosition(currentPos);
    } else if (wasPaused) {
      _lastSpeechStartOffset = currentPos;
    }
  }

  // --- SPEED LOGIC ---
  void _changeSpeed() async {
    double nextDisplaySpeed = _displaySpeed + 0.25;
    if (nextDisplaySpeed > 1.75) {
      nextDisplaySpeed = 0.5;
    }

    int currentPos = _currentAbsolutePosition;
    bool wasReading = _isReading && !_isPaused;
    bool wasPaused = _isPaused;

    await widget.ttsService.stop();

    setState(() => _displaySpeed = nextDisplaySpeed);

    await widget.ttsService.setSpeed(nextDisplaySpeed * 0.5);
    await widget.ttsService.savePreferences(
      speed: nextDisplaySpeed,
      volume: _currentVolume,
    );

    if (wasReading) {
      await _speakFromPosition(currentPos);
    } else if (wasPaused) {
      _lastSpeechStartOffset = currentPos;
    }
  }

  String get _fullText {
    final sb = StringBuffer();
    if (_playContext &&
        widget.contextText != null &&
        widget.contextText!.isNotEmpty) {
      sb.write("Context: ${widget.contextText}. ");
      sb.write("\n\n");
    }
    if (widget.question.number != null) {
      sb.write("Question ${widget.question.number}. ");
    }
    sb.write(widget.question.prompt);
    sb.write("\n");
    sb.write(widget.question.body.join("\n"));
    return sb.toString();
  }

  int _lastSpeechStartOffset = 0;
  int get _currentAbsolutePosition =>
      _lastSpeechStartOffset + widget.ttsService.currentWordStart;

  Future<void> _speakFromPosition(int start) async {
    String textToSpeak = _fullText;
    if (start > 0 && start < textToSpeak.length) {
      textToSpeak = textToSpeak.substring(start);
    }
    _lastSpeechStartOffset = start;
    setState(() {
      _isReading = true;
      _isPaused = false;
    });
    await widget.ttsService.speakAndWait(textToSpeak);
    if (mounted && !_isPaused) {
      setState(() => _isReading = false);
    }
  }

  void _onReadPressed() async {
    if (_isPaused) {
      await _speakFromPosition(_lastSpeechStartOffset);
    } else {
      _lastSpeechStartOffset = 0;
      await _speakFromPosition(0);
    }
  }

  void _onStopPressed() async {
    if (!_isPaused) {
      int currentPos = _currentAbsolutePosition;
      setState(() {
        _isPaused = true;
        _lastSpeechStartOffset = currentPos;
      });
      await widget.ttsService.stop();
    } else {
      await widget.ttsService.stop();
      setState(() {
        _isPaused = false;
        _lastSpeechStartOffset = 0;
      });
      _onReadPressed();
    }
  }

  void _startListening({bool append = true}) async {
    _isAppending = append;
    if (!await _audioRecorderService.hasPermission()) {
      widget.ttsService.speak("Microphone permission needed.");
      return;
    }
    // Briefly stop command listener to free mic for recording
    await _sttService.stopListening();

    await widget.ttsService.speak("Listening.");
    await Future.delayed(const Duration(milliseconds: 600));
    final tempDir = await getTemporaryDirectory();
    _tempAudioPath =
        '${tempDir.path}/temp_answer_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _audioRecorderService.startRecording(_tempAudioPath!);
      setState(() {
        _isListening = true;
        _isProcessingAudio = false;
      });
    } catch (e) {
      widget.ttsService.speak("Failed to start recording.");
      _initVoiceCommandListener(); // Resume listener on fail
    }
  }

  void _stopListening() async {
    if (_isListening) {
      final path = await _audioRecorderService.stopRecording();
      setState(() {
        _isListening = false;
        _isProcessingAudio = true;
      });
      if (path == null) {
        widget.ttsService.speak("Recording failed.");
        setState(() => _isProcessingAudio = false);
        _initVoiceCommandListener();
        return;
      }
      await _processAudioAnswer(path);
      // Resume Command Listener
      _initVoiceCommandListener();
    }
  }

  Future<void> _processAudioAnswer(String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');
    String transcribedText = "";
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final geminiService = GeminiQuestionService();
        transcribedText = await geminiService.transcribeAudio(
          audioPath,
          apiKey,
        );
      } catch (e) {
        transcribedText = "[Transcription Failed: $e]";
      }
    } else {
      transcribedText = "[No API Key - Audio Saved. Type answer manually.]";
      widget.ttsService.speak(
        "No API Key found. Audio saved, please type answer.",
      );
    }
    if (!mounted) return;
    setState(() {
      _isProcessingAudio = false;
      if (_isAppending && _answerController.text.isNotEmpty) {
        // Append Mode
        String separator = _answerController.text.endsWith('.') ? " " : ". ";
        if (_answerController.text.trim().isEmpty) separator = "";
        _answerController.text =
            _answerController.text + separator + transcribedText;
      } else {
        // Replace Mode (Overwrite)
        _answerController.text = transcribedText;
      }
    });
    await Future.delayed(const Duration(milliseconds: 100));
    _onDictationFinished();
  }

  void _clearAnswer() async {
    setState(() {
      _answerController.clear();
    });
    await widget.ttsService.speak("Answer cleared.");
  }

  void _readLastSentence() async {
    String text = _answerController.text.trim();
    if (text.isEmpty) {
      await widget.ttsService.speak("Answer is empty.");
      return;
    }

    // Simple split by period, handling common abbreviations briefly
    List<String> sentences = text.split(RegExp(r'(?<=[.?!])\s+'));
    if (sentences.isNotEmpty) {
      String last = sentences.last;
      await widget.ttsService.speak("Last sentence: $last");
    }
  }

  void _onDictationFinished() async {
    String answer = _answerController.text.trim();
    widget.ttsService.speak("You wrote: $answer. Is this correct?");
    if (mounted) {
      _showConfirmationDialog(answer);
    }
  }

  Future<void> _showConfirmationDialog(String answer) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Answer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("You wrote:\n\n$answer"),
            if (_tempAudioPath != null)
              TextButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text("Play Preview"),
                onPressed: () async {
                  await _audioPlayer.play(DeviceFileSource(_tempAudioPath!));
                },
              ),
          ],
        ),
        actions: [
          AccessibleTextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _discardAudio();
              setState(() {
                _answerController.text = "";
              });
              _startListening();
            },
            child: const Text("Retry"),
          ),
          AccessibleElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _handleConfirmedAnswer();
              AccessibilityService().trigger(AccessibilityEvent.success);
              widget.ttsService.speak("Answer saved.");
            },
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  void _discardAudio() {
    if (_tempAudioPath != null) {
      final file = File(_tempAudioPath!);
      if (file.existsSync()) file.deleteSync();
      _tempAudioPath = null;
    }
  }

  Future<void> _handleConfirmedAnswer() async {
    widget.question.answer = _answerController.text;
    if (_tempAudioPath != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName =
            'answer_q${widget.question.number ?? "x"}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final permPath = '${appDir.path}/$fileName';
        await File(_tempAudioPath!).copy(permPath);
        setState(() {
          widget.question.audioPath = permPath;
        });
        _discardAudio();
      } catch (e) {
        debugPrint("Error saving audio: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String readLabel = _isPaused
        ? "Resume"
        : (_isReading ? "Reading..." : "Read");
    IconData readIcon = _isPaused
        ? Icons.play_arrow_rounded
        : Icons.volume_up_rounded;
    VoidCallback? onRead = (_isReading && !_isPaused) ? null : _onReadPressed;

    String stopLabel = _isPaused ? "Restart" : "Stop";
    IconData stopIcon = _isPaused ? Icons.replay_rounded : Icons.stop_rounded;
    VoidCallback? onStop = (!_isReading && !_isPaused) ? null : _onStopPressed;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Question Detail",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: "Back",
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).cardTheme.color!.withValues(alpha: 0.8),
              Theme.of(context).scaffoldBackgroundColor,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.contextText != null &&
                            widget.contextText!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.3),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Shared Context:",
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade200,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.contextText!,
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    height: 1.4,
                                    color: Colors.white70,
                                  ),
                                ),
                                AccessibleSwitchListTile(
                                  title: Text(
                                    "Read this context too?",
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      color: Colors.white60,
                                    ),
                                  ),
                                  value: _playContext,
                                  onChanged: (val) =>
                                      setState(() => _playContext = val),
                                  contentPadding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  activeColor: Colors.amber,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (widget.question.number != null)
                          Text(
                            "Question ${widget.question.number}",
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        if (widget.question.marks != null)
                          Text(
                            "Marks: ${widget.question.marks}",
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: Colors.white54,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          widget.question.prompt,
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._buildBodyWidgets(widget.question.body),
                        const SizedBox(height: 32),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 16),
                        // NEXT BUTTON
                        if (widget.onNext != null) ...[
                          AccessibleElevatedButton(
                            onPressed: widget.onNext,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white10,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Next Question",
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                        Text(
                          "Your Answer:",
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _answerController,
                          maxLines: 5,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: "Type or detect answer...",
                            hintStyle: GoogleFonts.outfit(
                              color: Colors.white30,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            suffixIcon: _isProcessingAudio
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : AccessibleIconButton(
                                    icon: Icon(
                                      _isListening
                                          ? Icons.stop_circle_rounded
                                          : Icons.mic_rounded,
                                    ),
                                    color: _isListening
                                        ? Colors.redAccent
                                        : Colors.white60,
                                    iconSize: 28,
                                    onPressed: _isListening
                                        ? _stopListening
                                        : _startListening,
                                  ),
                          ),
                        ),
                        if (widget.question.audioPath != null &&
                            widget.question.audioPath!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: AccessibleOutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context).primaryColor,
                                side: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.play_circle_fill_rounded),
                              child: Text(
                                "Play Saved Answer",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () async => await _audioPlayer.play(
                                DeviceFileSource(widget.question.audioPath!),
                              ),
                            ),
                          ),
                        const SizedBox(height: 40), // Bottom padding
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Controls
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: AccessibleElevatedButton(
                              onPressed: onRead,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              icon: Icon(readIcon),
                              child: Text(readLabel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AccessibleElevatedButton(
                              onPressed: onStop,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                backgroundColor: _isPaused
                                    ? Colors.orangeAccent
                                    : Colors.redAccent.shade200,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              icon: Icon(stopIcon),
                              child: Text(stopLabel),
                            ),
                          ),
                        ],
                      ),

                      Row(
                        children: [
                          Expanded(
                            child: AccessibleElevatedButton(
                              onPressed: _changeSpeed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.speed_rounded, size: 18),
                              child: Text(
                                "${_displaySpeed.toStringAsFixed(2)}x",
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AccessibleElevatedButton(
                              onPressed: _changeVolume,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: Icon(
                                _currentVolume < 0.5
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_up_rounded,
                                size: 18,
                              ),
                              child: Text(
                                "Vol: ${(_currentVolume * 100).toInt()}%",
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBodyWidgets(List<String> body) {
    List<Widget> widgets = [];
    List<String> currentBoxItems = [];
    String? currentBoxTitle;
    bool inBox = false;
    for (var line in body) {
      final trimmed = line.trim();
      if (trimmed.startsWith("[[BOX:") && trimmed.endsWith("]]")) {
        if (inBox) {
          widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
        }
        inBox = true;
        currentBoxTitle = trimmed.substring(6, trimmed.length - 2).trim();
        currentBoxItems = [];
      } else if (trimmed == "[[BOX END]]") {
        if (inBox) {
          widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
          inBox = false;
        }
      } else {
        if (inBox) {
          currentBoxItems.add(line);
        } else {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: GoogleFonts.outfit(fontSize: 18, color: Colors.white70),
              ),
            ),
          );
        }
      }
    }
    if (inBox) widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
    return widgets;
  }

  Widget _buildBoxWidget(String? title, List<String> items) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Text(
              title ?? "Box",
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items
                  .map(
                    (i) => Text(
                      i,
                      style: GoogleFonts.outfit(color: Colors.white70),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

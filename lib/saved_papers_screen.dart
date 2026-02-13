import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // Unused
// import 'dart:convert'; // Unused
import 'services/paper_storage_service.dart';
import 'services/tts_service.dart';
import 'paper_detail_screen.dart';
import 'models/paper_model.dart'; // Import models
import 'services/voice_command_service.dart';
import 'services/accessibility_service.dart';
// import 'widgets/accessible_widgets.dart'; // Unused
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui'; // Add this for ImageFilter
import 'widgets/picovoice_mic_icon.dart';
import 'widgets/voice_alert_dialog.dart';

import 'exam_info_screen.dart';
import 'services/picovoice_service.dart';
import 'dart:async';
// import 'services/stt_service.dart'; // Removed

// ... rest of imports

class SavedPapersScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final PicovoiceService picovoiceService;
  final AccessibilityService? accessibilityService;
  final ParsedDocument? document;
  final String? studentName;
  final String? studentId;
  final bool examMode;
  final bool isSelectionMode; // New flag

  const SavedPapersScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    required this.picovoiceService,
    this.accessibilityService,
    this.document,
    this.studentName,
    this.studentId,
    this.examMode = false,
    this.isSelectionMode = false, // Default false
  });

  @override
  State<SavedPapersScreen> createState() => _SavedPapersScreenState();
}

class _SavedPapersScreenState extends State<SavedPapersScreen> {
  final PaperStorageService _storageService = PaperStorageService();
  List<ParsedDocument> _papers = [];
  bool _isLoading = true;
  StreamSubscription<CommandResult>? _commandSubscription;
  final ScrollController _scrollController = ScrollController(); // Added

  @override
  void initState() {
    super.initState();
    _loadPapers();

    if (widget.examMode) {
      // Exam sequence initiation handled by PaperDetailScreen logic now.
    } else {
      widget.ttsService.speak("Welcome to saved papers.");
      widget.ttsService.speak("Welcome to saved papers.");
    }
    _initVoiceCommandListener();
  }

  void _initVoiceCommandListener() {
    _commandSubscription = widget.voiceService.commandStream.listen((result) {
      if (!mounted) return;
      // Handle commands for Saved Papers context
      _handleVoiceCommand(result);
    });
  }

  void _handleVoiceCommand(CommandResult result) {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    debugPrint("SavedPapersScreen received command: ${result.action}");
    switch (result.action) {
      case VoiceAction.scrollToTop:
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
        break;
      case VoiceAction.scrollToBottom:
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
        break;

      case VoiceAction.deletePaper:
        if (result.payload is int) {
          int index = (result.payload as int) - 1; // 1-based to 0-based
          if (index >= 0 && index < _papers.length) {
            _confirmDeletePaper(index);
          } else {
            widget.ttsService.speak(
              "Paper number ${result.payload} not found.",
            );
          }
        }
        break;
      case VoiceAction.openPaper:
        if (result.payload is int) {
          int index = (result.payload as int) - 1;
          if (index >= 0 && index < _papers.length) {
            // Open it
            _openPaper(_papers[index], index);
          } else {
            widget.ttsService.speak(
              "Paper number ${result.payload} not found.",
            );
          }
        }
        break;
      case VoiceAction.clearAllPapers:
        _confirmClearAll();
        break;
      case VoiceAction.search:
        widget.ttsService.speak("Search functionality is coming soon.");
        break;
      case VoiceAction.goBack:
        Navigator.pop(context);
        break;
      case VoiceAction.scrollUp:
        _scrollUp();
        break;
      case VoiceAction.scrollDown:
        _scrollDown();
        break;
      default:
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
  }

  void _scrollUp() {
    if (_scrollController.hasClients) {
      final pos = _scrollController.offset - 300;
      _scrollController.animateTo(
        pos.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: 300.ms,
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollDown() {
    if (_scrollController.hasClients) {
      final pos = _scrollController.offset + 300;
      _scrollController.animateTo(
        pos.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: 300.ms,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _commandSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Voice command listener methods removed. Global Picovoice handles navigation.
  // Note: Open Paper X logic needs to be handled by VoiceCommandService globally now.

  // _handleVoiceCommand removed (logic should be in VoiceCommandService)

  // ... (rest of methods)

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

  // Removed unused _finishExam method

  // Removed unused _formatTime method

  Future<void> _clearAllPapers() async {
    await widget.ttsService.speak("Clearing all saved papers.");
    await _storageService.clearDocuments();
    setState(() {
      _papers = [];
    });
    widget.ttsService.speak("All papers cleared.");
  }

  Future<void> _loadPapers() async {
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
    // _sttService.stopListening(); // Removed

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
          picovoiceService: widget.picovoiceService,
        ),
      ),
    ); // .then listener restart removed
  }

  void _confirmDeletePaper(int index) {
    widget.ttsService.speak("Are you sure you want to delete this paper?");
    showDialog(
      context: context,
      builder: (ctx) => VoiceAlertDialog(
        title: const Text("Confirm Deletion"),
        voiceService: widget.voiceService,
        content: Text("Delete '${_papers[index].name}'?"),
        onConfirm: () {
          Navigator.pop(ctx);
          _deletePaper(index);
        },
        onCancel: () => Navigator.pop(ctx),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePaper(index);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    widget.ttsService.speak("Are you sure you want to clear all papers?");
    showDialog(
      context: context,
      builder: (ctx) => VoiceAlertDialog(
        title: const Text("Confirm Clear All"),
        voiceService: widget.voiceService,
        content: const Text("This will delete all saved papers permanently."),
        onConfirm: () {
          Navigator.pop(ctx);
          _clearAllPapers();
        },
        onCancel: () => Navigator.pop(ctx),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllPapers();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete All"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Removed obsolete exam mode build logic that caused errors

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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: PicovoiceMicIcon(service: widget.picovoiceService),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.redAccent,
              ),
              tooltip: 'Clear All',
              onPressed: () async {
                AccessibilityService().trigger(AccessibilityEvent.warning);
                await _storageService.clearDocuments();
                _loadPapers();
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
              Theme.of(context).cardTheme.color!.withValues(alpha: 0.8),
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
                        color: Colors.white.withValues(alpha: 0.2),
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
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Exam header removed as logic is now in PaperDetailScreen

                    // List of papers
                    ..._papers.asMap().entries.map((entry) {
                      int index = entry.key;
                      ParsedDocument doc = entry.value;
                      final qCount = doc.sections.fold(
                        0,
                        (sum, s) => sum + s.questions.length,
                      );

                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.horizontal, // Allow both
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          color: Colors.green, // Swipe Right -> Rename
                          child: const Icon(Icons.edit, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.redAccent, // Swipe Left -> Delete
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            // RENAME ACTION
                            String? newName = await showDialog<String>(
                              context: context,
                              builder: (ctx) {
                                final TextEditingController nameController =
                                    TextEditingController(text: doc.name);
                                return AlertDialog(
                                  title: const Text("Rename Paper"),
                                  content: TextField(
                                    controller: nameController,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: "New Name",
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, null),
                                      child: const Text("Cancel"),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        if (nameController.text
                                            .trim()
                                            .isNotEmpty) {
                                          Navigator.pop(
                                            ctx,
                                            nameController.text.trim(),
                                          );
                                        }
                                      },
                                      child: const Text("Rename"),
                                    ),
                                  ],
                                );
                              },
                            );

                            if (newName != null && newName != doc.name) {
                              setState(() {
                                doc.name = newName;
                              });
                              // Save the update
                              await _storageService.saveDocument(doc);
                              widget.ttsService.speak(
                                "Paper renamed to $newName.",
                              );
                            }
                            // Do not dismiss the row
                            return false;
                          } else {
                            // DELETE ACTION
                            return true; // Proceed to onDismissed
                          }
                        },
                        onDismissed: (direction) {
                          if (direction == DismissDirection.endToStart) {
                            _deletePaper(index);
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
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
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).primaryColor.withValues(alpha: 0.2),
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
                                  AccessibilityService().trigger(
                                    AccessibilityEvent.action,
                                  );

                                  // 1. CHECK: Are we in Exam Selection Mode?
                                  if (widget.isSelectionMode) {
                                    // YES -> Go to Exam Info (Rules, Timer, Name)
                                    AccessibilityService().trigger(
                                      AccessibilityEvent.action,
                                    );
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
                                          picovoiceService:
                                              widget.picovoiceService,
                                          // sttService: _sttService, // Removed (Also check ExamInfoScreen constructor!)
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
                    }),
                  ],
                ),
        ),
      ),
    );
  }
}

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
import 'services/stt_service.dart';
import 'exam_info_screen.dart';
import 'dart:async';

// ... rest of imports

class QuestionsScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService? accessibilityService;
  final ParsedDocument? document;
  final String? studentName;      
  final String? studentId;       
  final bool examMode;            
  
  const QuestionsScreen({super.key, required this.ttsService,required this.voiceService, this.accessibilityService,  this.document,
  this.studentName,
  this.studentId,
  this.examMode = false });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  final QuestionStorageService _storageService = QuestionStorageService();
  // We store the raw JSON strings; parsing happens on demand or we could parse them all.
  // Let's parse them to display metadata (like date).
  List<ParsedDocument> _papers = [];
  bool _isLoading = true;
  bool _isSelectingForExam = false;
  //int _examTimer = 0; // seconds
  //bool _timerStarted = false;
  final SttService _sttService = SttService();

  int _currentQuestionIndex = 0;
  Timer? _examTimer; // This controls the ticking
  int _remainingSeconds = 0; // This holds the time left
  bool _isExamRunning = false;
  bool _showCountdown = false;
  int _countdownValue = 3;
  bool _isRecordingAnswer = false;

  List<dynamic> _allExamQuestions = [];

  @override
  void initState() {
    super.initState();
    _loadQuestions();
   
    if (widget.examMode) {
    _startExamSequence();
    }
    else{
         widget.ttsService.speak(
      "Welcome to saved papers. Here you can review your scanned question papers.",
    );
    }
  }

  @override
  void dispose() {
    _examTimer?.cancel(); // Added safety
    super.dispose();
  }
//   Future<void> _startExamTimer() async {
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

void _startExamSequence() {
    if (widget.document != null) {
      _allExamQuestions = widget.document!.sections
          .expand((section) => section.questions)
          .toList();
    }

    _remainingSeconds = 900; // 15 Minutes
    setState(() {
      _showCountdown = true;
      _countdownValue = 3; 
    });

    // 3-2-1 Countdown
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownValue > 1) {
        setState(() => _countdownValue--);
      } else {
        timer.cancel();
        _beginExam();
      }
    });
  }

  void _beginExam() {
    setState(() {
      _showCountdown = false;
      _isExamRunning = true;
    });
    
    widget.ttsService.speak("Exam started.");

    _examTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
        if (_remainingSeconds == 900) {
          widget.ttsService.speak("Fifteen minutes remaining.");
        }
      } else {
        _finishExam();
      }
    });

    _readCurrentQuestion();
  }

  void _readCurrentQuestion() {
    // FIX: Use _allExamQuestions instead of widget.document!.questions
    if (_allExamQuestions.isNotEmpty) {
      String text = _allExamQuestions[_currentQuestionIndex].prompt;
      widget.ttsService.stop(); 
      widget.ttsService.speak("Question ${_currentQuestionIndex + 1}. $text");
    }
  }

  void _toggleAnswerRecording() {
    setState(() {
      _isRecordingAnswer = !_isRecordingAnswer;
    });
    // Add your actual _sttService.listen() call here if needed later
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _allExamQuestions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _isRecordingAnswer = false; 
      });
      _readCurrentQuestion();
    } else {
      _finishExam();
    }
  }

  void _finishExam() {
    _examTimer?.cancel();
    widget.ttsService.speak("Exam finished.");
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
    
    if (widget.examMode) {
      // A. The 3-2-1 Countdown Screen
      if (_showCountdown) {
        return Scaffold(
          body: Center(
            child: Text(
              "$_countdownValue",
              style: GoogleFonts.outfit(fontSize: 100, fontWeight: FontWeight.bold, color: Colors.deepPurple),
            ),
          ),
        );
      }
      
      // B. The Active Exam Screen
      // Safety Check: If document is null, show error to avoid crash
      if (_allExamQuestions.isEmpty) {
         return const Scaffold(body: Center(child: Text("Error: No questions loaded.")));
      }

      final question = _allExamQuestions[_currentQuestionIndex];
      
      return Scaffold(
        appBar: AppBar(
          title: Text("Time: ${_formatTime(_remainingSeconds)}"),
          automaticallyImplyLeading: false, 
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Question ${_currentQuestionIndex + 1} of ${_allExamQuestions.length}",
                style: GoogleFonts.outfit(fontSize: 20, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Text(
                      question.prompt,
                      style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Mic Button
              GestureDetector(
                onTap: _toggleAnswerRecording,
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: _isRecordingAnswer ? Colors.redAccent : Colors.deepPurple,
                  child: Icon(_isRecordingAnswer ? Icons.stop : Icons.mic, size: 40, color: Colors.white),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isRecordingAnswer ? "Listening..." : "Tap to Answer",
                style: GoogleFonts.outfit(color: Colors.grey),
              ),
              
              const SizedBox(height: 40),
              
              // Next Button
              ElevatedButton(
                onPressed: _nextQuestion,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _currentQuestionIndex == _allExamQuestions.length - 1 
                      ? "Finish Exam" 
                      : "Next Question",
                  style: GoogleFonts.outfit(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
          child:_isLoading
    ? const Center(child: CircularProgressIndicator())
    : _papers.isEmpty && !widget.examMode
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
        : ListView(
  padding: const EdgeInsets.all(20),
  children: [
    // Show button only if not in exam mode
    if (!widget.examMode)
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: ElevatedButton.icon(
          onPressed: () {
            if(widget.document!=null){
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExamInfoScreen(
                  document: widget.document!,
                  ttsService: widget.ttsService,
                  voiceService: widget.voiceService,
                  accessibilityService: widget.accessibilityService!,
                  sttService: _sttService,
                  ),
                ),
              );
            }else{
              setState(() {
                _isSelectingForExam = !_isSelectingForExam;
              });

              String msg = _isSelectingForExam 
                  ? "Please tap a paper below to start the exam." 
                  : "Exam selection cancelled.";
                  
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg, style: GoogleFonts.outfit()),
                  backgroundColor: Colors.deepPurple,
                  //behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
              widget.ttsService.speak(msg);
            }
          },
          icon: const Icon(Icons.school),
          label: Text(
            'Enter Exam Mode',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0),
      ),

    // Show exam header only if exam mode is active
    if (widget.examMode)
      Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.deepPurple.withOpacity(0.5)),
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
                style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70),
              ),
            if (widget.studentId != null)
              Text(
                "Student ID: ${widget.studentId}",
                style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70),
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
      final qCount = doc.sections.fold(0, (sum, s) => sum + s.questions.length);

      return Dismissible(
        key: Key(doc.toString() + index.toString()),
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

                  // 1. CHECK: Are we trying to start an exam?
                  if (_isSelectingForExam) {
                    // YES -> Turn off the selection switch
                    setState(() => _isSelectingForExam = false);

                    // ...and go to the Student Info Screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExamInfoScreen(
                          document: doc,
                          ttsService: widget.ttsService,
                          voiceService: widget.voiceService,
                          accessibilityService: widget.accessibilityService ?? AccessibilityService(),
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
  ],
)


        ),
      ),
    );
  }
}


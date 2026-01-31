import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lekhai/paper_detail_screen.dart';
// import 'dart:io';
// import 'questions_screen.dart';
// import 'package:lekhai/services/ocr_service.dart';
import 'package:lekhai/services/tts_service.dart';
import 'package:lekhai/services/stt_service.dart';
import 'package:lekhai/services/voice_command_service.dart';
import 'package:lekhai/services/accessibility_service.dart';
import 'package:lekhai/models/question_model.dart';

class ExamInfoScreen extends StatefulWidget {
  final ParsedDocument document;
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;
  final SttService sttService;

  const ExamInfoScreen({
    Key? key,
    required this.document,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
    required this.sttService,
  }) : super(key: key);

  @override
  _ExamInfoScreenState createState() => _ExamInfoScreenState();
}

class _ExamInfoScreenState extends State<ExamInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _studentId = '';
  String _timerText = '60'; // Default 60 minutes
  // bool _isListeningName = false;
  // bool _isListeningId = false;

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak(
      "Exam Setup. Please review rules and enter details.",
    );
  }

  void _confirmAndStartExam() {
    if (_formKey.currentState?.validate() != true) {
      widget.ttsService.speak("Please correct the errors.");
      return;
    }

    int? minutes = int.tryParse(_timerText);
    if (minutes == null || minutes <= 0) {
      widget.ttsService.speak("Invalid duration.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid duration > 0")),
      );
      return;
    }

    // Convert to seconds
    int durationSeconds = minutes * 60;

    widget.ttsService.speak(
      "Starting exam for $_name with $minutes minutes duration.",
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaperDetailScreen(
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
          document: widget.document,
          studentName: _name,
          studentId: _studentId,
          examMode: true,
          examDurationSeconds: durationSeconds,
          timestamp: DateTime.now().toIso8601String(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Exam Setup",
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
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- GENERAL RULES SECTION ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "General Exam Rules",
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent.shade100,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildRuleItem("1. Do not minimize the app."),
                        _buildRuleItem(
                          "2. Audio is recorded for verification.",
                        ),
                        _buildRuleItem(
                          "3. Ensure you have a stable environment.",
                        ),
                        _buildRuleItem(
                          "4. Time will be tracked automatically.",
                        ),
                      ],
                    ),
                  ),

                  Text(
                    "Student Information",
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Name input
                  TextFormField(
                    initialValue: _name,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration("Full Name", Icons.person),
                    validator: (val) =>
                        val == null || val.isEmpty ? "Name is required" : null,
                    onChanged: (val) => setState(() => _name = val),
                  ),
                  const SizedBox(height: 16),

                  // Student ID input
                  TextFormField(
                    initialValue: _studentId,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration("Student ID", Icons.badge),
                    validator: (val) =>
                        val == null || val.isEmpty ? "ID is required" : null,
                    onChanged: (val) => setState(() => _studentId = val),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    "Exam Settings",
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Timer Input
                  TextFormField(
                    initialValue: _timerText,
                    style: GoogleFonts.outfit(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                      "Duration (Minutes)",
                      Icons.timer,
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty)
                        return "Duration required";
                      final n = int.tryParse(val);
                      if (n == null || n <= 0) return "Must be positive";
                      return null;
                    },
                    onChanged: (val) => setState(() => _timerText = val),
                  ),

                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed:
                        (_name.isNotEmpty &&
                            _studentId.isNotEmpty &&
                            _timerText.isNotEmpty)
                        ? _confirmAndStartExam
                        : null, // Disable if fields empty
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Colors.deepPurple,
                      disabledBackgroundColor: Colors.white10,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: Text(
                      "Enter Exam Mode",
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuleItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(color: Colors.white70)),
          Expanded(
            child: Text(text, style: GoogleFonts.outfit(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: Icon(icon, color: Colors.white60),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepPurple),
      ),
    );
  }
}

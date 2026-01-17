import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'questions_screen.dart';
import 'package:lekhai/services/ocr_service.dart';
import 'package:lekhai/services/tts_service.dart';
import 'package:lekhai/services/stt_service.dart';
import 'package:lekhai/services/voice_command_service.dart';
import 'package:lekhai/services/accessibility_service.dart';
//import 'package:lekhai/models/parsed_document.dart';


class ExamInfoScreen extends StatefulWidget {
  //final ParsedDocument document;
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;
  final SttService sttService;


  const ExamInfoScreen({
    Key? key,
   //required this.document,
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
  bool _isListeningName = false;
  bool _isListeningId = false;

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak(
      "Please enter your full name and student ID to start Exam Mode."
    );
  }

 Future<void> _listenName() async {
  setState(() => _isListeningName = true);

  await widget.sttService.startListening(
    localeId: 'en_US',
    onResult: (result) {
      if (result.isNotEmpty) setState(() => _name = result);
    },
  );

  setState(() => _isListeningName = false);
}

Future<void> _listenId() async {
  setState(() => _isListeningId = true);

  await widget.sttService.startListening(
    localeId: 'en_US',
    onResult: (result) {
      if (result.isNotEmpty) setState(() => _studentId = result);
    },
  );

  setState(() => _isListeningId = false);
}



  void _confirmAndStartExam() {
  if (_name.isEmpty || _studentId.isEmpty) {
    widget.ttsService.speak("Please provide both name and student ID.");
    return;
  }

  widget.ttsService.speak(
      "You entered name $_name and student ID $_studentId. Is this correct? Say yes or no."
  );

  // Start listening for the confirmation
  widget.sttService.startListening(
    localeId: 'en_US',
    onResult: (result) {
      if (result.toLowerCase() == 'yes') {
        widget.ttsService.speak("Starting exam in 5 seconds.");
        Future.delayed(const Duration(seconds: 5), () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => QuestionsScreen(
                ttsService: widget.ttsService,
                voiceService: widget.voiceService,
                accessibilityService: widget.accessibilityService,
                studentName: _name,
                studentId: _studentId,
                examMode: true,
              ),
            ),
          );
        });
      } else {
        widget.ttsService.speak("Information not confirmed. Please re-enter.");
      }

      // Stop listening after first result
      widget.sttService.stopListening();
    },
  );
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Exam Info", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Enter your information",
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // Name input
              TextFormField(
                initialValue: _name,
                decoration: InputDecoration(
                  labelText: "Full Name",
                  suffixIcon: IconButton(
                    icon: Icon(_isListeningName ? Icons.mic : Icons.mic_none),
                    onPressed: _listenName,
                  ),
                ),
                onChanged: (val) => _name = val,
              ),
              const SizedBox(height: 16),

              // Student ID input
              TextFormField(
                initialValue: _studentId,
                decoration: InputDecoration(
                  labelText: "Student ID",
                  suffixIcon: IconButton(
                    icon: Icon(_isListeningId ? Icons.mic : Icons.mic_none),
                    onPressed: _listenId,
                  ),
                ),
                onChanged: (val) => _studentId = val,
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _confirmAndStartExam,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text("Confirm & Start Exam", style: GoogleFonts.outfit(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

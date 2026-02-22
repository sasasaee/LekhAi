import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:lekhai/paper_detail_screen.dart';
// import 'dart:io';
// import 'questions_screen.dart';
// import 'package:lekhai/services/ocr_service.dart';
import 'package:lekhai/services/tts_service.dart';
// import 'package:lekhai/services/stt_service.dart'; // Removed
import 'package:lekhai/services/voice_command_service.dart';
import 'package:lekhai/services/accessibility_service.dart';
import 'package:lekhai/models/paper_model.dart';
import 'package:lekhai/services/picovoice_service.dart';
import 'package:lekhai/widgets/picovoice_mic_icon.dart';
import 'package:lekhai/widgets/accessible_widgets.dart';
import 'package:lekhai/services/audio_recorder_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'package:lekhai/utils/string_utils.dart';
import 'package:lekhai/widgets/voice_alert_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lekhai/services/gemini_paper_service.dart';

enum DictationField { name, id, none }

class ExamInfoScreen extends StatefulWidget {
  final ParsedDocument document;
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;
  final PicovoiceService picovoiceService;
  // final SttService sttService; // Removed

  const ExamInfoScreen({
    super.key,
    required this.document,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
    required this.picovoiceService,
    // required this.sttService, // Removed
  });

  @override
  State<ExamInfoScreen> createState() => _ExamInfoScreenState();
}

class _ExamInfoScreenState extends State<ExamInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _hoursController = TextEditingController(
    text: '1',
  );
  final TextEditingController _minutesController = TextEditingController(
    text: '0',
  );
  String _hoursText = '1';
  String _minutesText = '0';
  String _name = '';
  String _studentId = '';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();

  // Focus Nodes for Voice Navigation
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _idFocus = FocusNode();
  final FocusNode _hoursFocus = FocusNode();
  final FocusNode _minutesFocus = FocusNode();

  StreamSubscription? _commandSubscription;

  // Audio Recording states
  final AudioRecorderService _audioRecorderService = AudioRecorderService();
  bool _isListening = false;
  bool _isProcessingAudio = false;
  bool _isListeningDialogOpen = false;
  bool _isTranscribingDialogOpen = false;
  String? _tempAudioPath;
  final AudioPlayer _audioPlayer = AudioPlayer();
  DictationField _currentDictationField = DictationField.none;

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak(
      "Exam Setup. Please review rules and enter details. Say Start Exam to begin.",
    );
    // _initVoiceListener(); // Removed
    _subscribeToVoiceCommands();

    // Add focus listeners for Handoff Resume
    void focusListener() {
      if (!_nameFocus.hasFocus &&
          !_idFocus.hasFocus &&
          !_hoursFocus.hasFocus &&
          !_minutesFocus.hasFocus) {
        // If all lost focus, assume dictation/editing done
        widget.picovoiceService.resumeListening();
      }
    }

    _nameFocus.addListener(focusListener);
    _idFocus.addListener(focusListener);
    _hoursFocus.addListener(focusListener);
    _minutesFocus.addListener(focusListener);

    // Initial safety resume
    widget.picovoiceService.resumeListening();
  }

  void _subscribeToVoiceCommands() {
    _commandSubscription = widget.voiceService.commandStream.listen((result) {
      if (mounted) {
        _executeVoiceCommand(result);
      }
    });
    widget.picovoiceService.stateNotifier.addListener(_onPicovoiceStateChanged);
  }

  void _onPicovoiceStateChanged() {
    if (widget.picovoiceService.stateNotifier.value == PicovoiceState.wakeDetected) {
      if (_isListening) {
        _stopListening();
      }
    }
  }

  @override
  void dispose() {
    _commandSubscription?.cancel();
    widget.picovoiceService.stateNotifier.removeListener(_onPicovoiceStateChanged);
    _audioPlayer.dispose();
    _nameFocus.dispose();
    _idFocus.dispose();
    _hoursFocus.dispose();
    _minutesFocus.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  // _initVoiceListener and _startListening Removed

  void _executeVoiceCommand(CommandResult result) {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;

    if (result.action == VoiceAction.confirmExamStart ||
        result.action == VoiceAction.enterExamMode ||
        result.action == VoiceAction.submitForm) {
      _confirmAndStartExam();
    } else if (result.action == VoiceAction.goBack ||
        result.action == VoiceAction.cancelExamStart) {
      Navigator.pop(context);
    } else if (result.action == VoiceAction.goToHome) {
      widget.voiceService.performGlobalNavigation(result);
    }

    // Form Navigation
    if (result.action == VoiceAction.setStudentName) {
      if (result.payload != null && result.payload.toString().isNotEmpty) {
        setState(() {
          _name = result.payload.toString();
          _nameController.text = _name;
        });
        widget.ttsService.speak("Name set to $_name");
        widget.picovoiceService.resumeListening(); // Direct set -> resume
      } else {
        FocusScope.of(context).requestFocus(_nameFocus);
        _startListening();
      }
    }
    if (result.action == VoiceAction.setStudentID) {
      if (result.payload != null && result.payload.toString().isNotEmpty) {
        setState(() {
          _studentId = result.payload.toString();
          _idController.text = _studentId;
        });
        widget.ttsService.speak("ID set to $_studentId");
        widget.picovoiceService.resumeListening();
      } else {
        FocusScope.of(context).requestFocus(_idFocus);
        _startListening();
      }
    }
    if (result.action == VoiceAction.startDictation) {
      if (_nameFocus.hasFocus || _idFocus.hasFocus) {
        _startListening();
      } else {
        widget.ttsService.speak("Please select name or ID field first.");
        widget.picovoiceService.resumeListening();
      }
    }
    if (result.action == VoiceAction.stopDictation) {
      _stopListening();
    }
    if (result.action == VoiceAction.setExamTime) {
      if (result.payload != null) {
        int totalMinutes = 0;
        if (result.payload is int) {
          totalMinutes = result.payload;
        } else {
          String p = result.payload.toString().replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );
          totalMinutes = int.tryParse(p) ?? 0;
        }

        if (totalMinutes > 0) {
          int h = totalMinutes ~/ 60;
          int m = totalMinutes % 60;
          setState(() {
            _hoursText = h.toString();
            _minutesText = m.toString();
            _hoursController.text = h.toString();
            _minutesController.text = m.toString();
          });
          widget.ttsService.speak("Duration set to $h hours and $m minutes");
          widget.picovoiceService.resumeListening();
        } else {
          widget.ttsService.speak("Invalid time format.");
          widget.picovoiceService.resumeListening();
        }
      } else {
        FocusScope.of(context).requestFocus(_hoursFocus);
        widget.ttsService.speak("Please set the exam duration.");
      }
    }
  }

  void _startListening() async {
    if (!await _audioRecorderService.hasPermission()) {
      widget.ttsService.speak("Microphone permission needed.");
      return;
    }

    if (_nameFocus.hasFocus) {
      _currentDictationField = DictationField.name;
    } else if (_idFocus.hasFocus) {
      _currentDictationField = DictationField.id;
    } else {
      _currentDictationField = DictationField.none;
    }

    await widget.ttsService.speak("Listening.");
    await Future.delayed(const Duration(milliseconds: 600));
    final tempDir = await getTemporaryDirectory();
    _tempAudioPath = '${tempDir.path}/temp_form_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _audioRecorderService.startRecording(_tempAudioPath!);
      setState(() {
        _isListening = true;
        _isProcessingAudio = false;
      });
      if (mounted && !_isListeningDialogOpen) {
        _isListeningDialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            content: Row(
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text("Listening... Say 'hey lekhai stop' to finish.")),
              ],
            ),
          ),
        ).then((_) => _isListeningDialogOpen = false);
      }
    } catch (e) {
      widget.ttsService.speak("Failed to start recording.");
    }
  }

  void _stopListening() async {
    if (_isListening) {
      final path = await _audioRecorderService.stopRecording();
      
      if (_isListeningDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _isListeningDialogOpen = false;
      }

      setState(() {
        _isListening = false;
        _isProcessingAudio = true;
      });
      if (path == null) {
        widget.ttsService.speak("Recording failed.");
        setState(() => _isProcessingAudio = false);
        return;
      }
      
      if (mounted && !_isTranscribingDialogOpen) {
        _isTranscribingDialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            content: Row(
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text("Transcribing..."),
              ],
            ),
          ),
        ).then((_) => _isTranscribingDialogOpen = false);
      }

      await _processAudioDictation(path);
    }
  }

  Future<void> _processAudioDictation(String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');
    String transcribedText = "";
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final geminiService = GeminiPaperService();
        transcribedText = await geminiService.transcribeAudio(audioPath, apiKey);
      } catch (e) {
        transcribedText = "[Transcription Failed: $e]";
      }
    } else {
      transcribedText = "[No API Key - Audio Saved. Type answer manually.]";
      widget.ttsService.speak("No API Key found. Audio saved, please type manually.");
    }
    if (!mounted) return;

    if (_isTranscribingDialogOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      _isTranscribingDialogOpen = false;
    }

    String processed = StringUtils.stripWakeWordsAndCommands(transcribedText);

    setState(() {
      _isProcessingAudio = false;
    });

    await Future.delayed(const Duration(milliseconds: 100));
    _onDictationFinished(processed);
  }

  void _onDictationFinished(String answer) async {
    // If dictating ID, extract digits first
    if (_currentDictationField == DictationField.id) {
      answer = StringUtils.extractDigits(answer);
      if (answer.isEmpty) {
        widget.ttsService.speak("I couldn't hear any numbers. Please try again.");
        widget.picovoiceService.resumeListening();
        return; // Don't show confirmation if empty ID
      }
    }

    if (answer.isEmpty) {
      widget.ttsService.speak("I couldn't hear anything. Please try again.");
      widget.picovoiceService.resumeListening();
      return;
    }

    widget.ttsService.speak("You said: $answer. Is this correct?");
    if (mounted) {
      _showConfirmationDialog(answer);
    }
  }

  Future<void> _showConfirmationDialog(String answer) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VoiceAlertDialog(
        voiceService: widget.voiceService,
        onConfirm: () async {
          Navigator.pop(ctx);
          if (_currentDictationField == DictationField.name) {
            setState(() {
              _name = answer;
              _nameController.text = answer;
            });
          } else if (_currentDictationField == DictationField.id) {
            setState(() {
              _studentId = answer;
              _idController.text = answer;
            });
          }
          _discardAudio();
          widget.ttsService.speak("Saved.");
          widget.picovoiceService.resumeListening(); // Direct set -> resume
          FocusScope.of(context).unfocus(); // Unfocus text fields after save
        },
        onCancel: () {
          Navigator.pop(ctx);
          _discardAudio();
          // refocus the correct field before retrying
          if (_currentDictationField == DictationField.name) {
            FocusScope.of(context).requestFocus(_nameFocus);
          } else if (_currentDictationField == DictationField.id) {
            FocusScope.of(context).requestFocus(_idFocus);
          }
          widget.picovoiceService.resumeListening();
        },
        title: const Text("Confirm"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("You said:\n\n$answer"),
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
              if (_currentDictationField == DictationField.name) {
                FocusScope.of(context).requestFocus(_nameFocus);
              } else if (_currentDictationField == DictationField.id) {
                FocusScope.of(context).requestFocus(_idFocus);
              }
              widget.picovoiceService.resumeListening();
            },
            child: const Text("Retry"),
          ),
          AccessibleElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (_currentDictationField == DictationField.name) {
                setState(() {
                  _name = answer;
                  _nameController.text = answer;
                });
              } else if (_currentDictationField == DictationField.id) {
                setState(() {
                  _studentId = answer;
                  _idController.text = answer;
                });
              }
              _discardAudio();
              widget.ttsService.speak("Saved.");
              widget.picovoiceService.resumeListening();
              FocusScope.of(context).unfocus(); 
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

  void _confirmAndStartExam() {
    if (_formKey.currentState?.validate() != true) {
      widget.ttsService.speak("Please correct the errors.");
      return;
    }

    int hours = int.tryParse(_hoursText) ?? 0;
    int minutes = int.tryParse(_minutesText) ?? 0;
    int totalMinutes = (hours * 60) + minutes;

    if (totalMinutes <= 0) {
      widget.ttsService.speak("Invalid duration. Must be at least 1 minute.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid duration > 0")),
      );
      return;
    }

    // Convert to seconds
    int durationSeconds = totalMinutes * 60;

    widget.ttsService.speak(
      "Starting exam for $_name with $hours hours and $minutes minutes duration.",
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
          picovoiceService: widget.picovoiceService,
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: PicovoiceMicIcon(service: widget.picovoiceService),
          ),
        ],
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
              Theme.of(context).cardTheme.color!.withValues(alpha: 0.8),
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
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3),
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
                    controller: _nameController,
                    focusNode: _nameFocus,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration("Full Name", Icons.person),
                    validator: (val) =>
                        val == null || val.isEmpty ? "Name is required" : null,
                    onChanged: (val) => setState(() => _name = val),
                  ),
                  const SizedBox(height: 16),

                  // Student ID input
                  TextFormField(
                    controller: _idController,
                    focusNode: _idFocus,
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
                  // Timer Input (Hours and Minutes)
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _hoursController,
                          focusNode: _hoursFocus,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.outfit(color: Colors.white),
                          decoration: _inputDecoration("Hours", Icons.timer),
                          validator: (val) {
                            if (val == null || val.isEmpty) return "Required";
                            final n = int.tryParse(val);
                            if (n == null || n < 0) return "Invalid";
                            return null;
                          },
                          onChanged: (val) {
                            setState(() {
                              _hoursText = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _minutesController,
                          focusNode: _minutesFocus,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.outfit(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Minutes",
                            labelStyle: const TextStyle(color: Colors.white60),
                            prefixIcon: const Icon(
                              Icons.timer_outlined,
                              color: Colors.white60,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return "Required";
                            final n = int.tryParse(val);
                            if (n == null || n < 0) return "Invalid";
                            return null;
                          },
                          onChanged: (val) {
                            setState(() {
                              _minutesText = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  ElevatedButton(
                    onPressed:
                        (_name.isNotEmpty &&
                            _studentId.isNotEmpty &&
                            (_hoursText.isNotEmpty || _minutesText.isNotEmpty))
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
      fillColor: Colors.white.withValues(alpha: 0.05),
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

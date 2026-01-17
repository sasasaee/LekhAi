import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'services/gemini_question_service.dart';
import 'services/question_storage_service.dart';
import 'models/question_model.dart';
import 'services/tts_service.dart';
import 'dart:convert';
import 'services/stt_service.dart';
import 'services/audio_recorder_service.dart';
import 'services/voice_command_service.dart'; // Added
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';

// --- PAPER DETAIL SCREEN ---

import 'services/accessibility_service.dart';
import 'widgets/accessible_widgets.dart'; // Added
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';

class PaperDetailScreen extends StatefulWidget {
  final ParsedDocument document;
  final TtsService ttsService;
  final VoiceCommandService voiceService; // Added
  final AccessibilityService? accessibilityService;
  final String timestamp;

  const PaperDetailScreen({
    super.key,
    required this.document,
    required this.ttsService,
    required this.voiceService, // Added
    this.accessibilityService,
    required this.timestamp,
  });

  @override
  State<PaperDetailScreen> createState() => _PaperDetailScreenState();
}

class _PaperDetailScreenState extends State<PaperDetailScreen> {
  late ParsedDocument _document;
  final GeminiQuestionService _geminiService = GeminiQuestionService();
  final QuestionStorageService _storageService = QuestionStorageService();
  final SttService _sttService = SttService();
  bool _isListening = false;
  @override
  void initState() {
    super.initState();
    _document = widget.document;
    AccessibilityService().trigger(AccessibilityEvent.navigation);
    // Initialize the listener for this screen
    _initVoiceCommandListener();
  }

  @override
  void dispose() {
    _sttService.stopListening(); // Stop listening when leaving the screen
    super.dispose();
  }

  // --- VOICE COMMAND LOGIC FOR LIST SCREEN ---
  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      onStatus: (status) {
        print("Paper List STT Status: $status");
        // Keep-alive loop for the listener
        if ((status == 'notListening' || status == 'done') && !_isListening) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isListening) _startCommandStream();
          });
        }
      },
      onError: (error) => print("Paper List STT Error: $error"),
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
        final result = widget.voiceService.parse(text);
        if (result.action != VoiceAction.unknown) {
          _executeVoiceCommand(result);
        }
      },
    );
  }

  void _executeVoiceCommand(CommandResult result) async {
    switch (result.action) {
      case VoiceAction.goToQuestion:
        // payload contains the question number (e.g., 1, 2, 3)
        final int? qNum = result.payload;
        if (qNum != null) {
          _openQuestionByNumber(qNum);
        }
        break;

      case VoiceAction.goBack:
        await widget.ttsService.speak("Going back to home.");
        if (mounted) Navigator.pop(context);
        break;

      case VoiceAction.submitExam: // Use this as "Save" for this screen
        await widget.ttsService.speak("Saving paper progress.");
        _savePaper(context);
        break;

      default:
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
  }

  // Helper to open a question via voice
  void _openQuestionByNumber(int number) {
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

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SingleQuestionScreen(
            question: target!,
            contextText: contextText,
            ttsService: widget.ttsService,
            voiceService: widget.voiceService,
            accessibilityService: widget.accessibilityService,
          ),
        ),
      ).then((_) {
        // Resume listening when returning
        _initVoiceCommandListener();
      });
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Paper $dateStr',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
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
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.1)),
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
              Theme.of(context).cardTheme.color!.withOpacity(0.8),
              Theme.of(context).scaffoldBackgroundColor,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
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
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
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
                      if (item.context != null && item.context!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            border: Border.all(
                              color: Colors.amber.withOpacity(0.3),
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
                final qTitle = q.number != null ? "Q${q.number}" : "Question";
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
                        Colors.white.withOpacity(0.08),
                        Colors.white.withOpacity(0.03),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
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
                            ).primaryColor.withOpacity(0.2),
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
                            style: GoogleFonts.outfit(color: Colors.white70),
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
              color: Theme.of(context).primaryColor.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => _onAddPage(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add_a_photo_outlined, color: Colors.white),
          tooltip: 'Add Page',
        ),
      ),
    );
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
                  _processWithGemini(context, apiKey!);
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

  const SingleQuestionScreen({
    super.key,
    required this.question,
    this.contextText,
    required this.ttsService,
    required this.voiceService, // Added
    this.accessibilityService,
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
        print("STT Status: $status");
        // FIX: If the engine stops (status 'done' or 'notListening') and
        // the student isn't currently dictating an answer, restart it.
        if ((status == 'notListening' || status == 'done') && !_isListening) {
          // A 500ms delay ensures the OS has fully released the mic before we re-acquire it
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isListening) _startCommandStream();
          });
        }
      },
      onError: (error) => print("STT Error: $error"),
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

        final result = widget.voiceService.parse(text);
        if (result.action != VoiceAction.unknown) {
          _executeVoiceCommand(result);
        }
      },
    );
  }

  void _executeVoiceCommand(CommandResult result) async {
    switch (result.action) {
      case VoiceAction.readQuestion:
        await widget.ttsService.speak("Reading question.");
        _onReadPressed();
        break;

      case VoiceAction.startDictation:
        await widget.ttsService.speak("Starting dictation.");
        _startListening();
        break;

      case VoiceAction.stopDictation:
        await widget.ttsService.speak("Stopping dictation.");
        _stopListening();
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
        Navigator.pop(context);
        break;

      default:
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
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
    if (widget.question.number != null)
      sb.write("Question ${widget.question.number}. ");
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

  void _startListening() async {
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
      _answerController.text = transcribedText;
    });
    await Future.delayed(const Duration(milliseconds: 100));
    _onDictationFinished();
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
        print("Error saving audio: $e");
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
                              color: Colors.amber.withOpacity(0.1),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.3),
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
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.1),
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
                              icon: Icon(readIcon),
                              child: Text(readLabel),
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
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AccessibleElevatedButton(
                              onPressed: onStop,
                              icon: Icon(stopIcon),
                              child: Text(stopLabel),
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
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AccessibleElevatedButton(
                              onPressed: _changeSpeed,
                              icon: const Icon(Icons.speed_rounded, size: 18),
                              child: Text(
                                "${_displaySpeed.toStringAsFixed(2)}x",
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AccessibleElevatedButton(
                              onPressed: _changeVolume,
                              icon: Icon(
                                _currentVolume < 0.5
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_up_rounded,
                                size: 18,
                              ),
                              child: Text(
                                "Vol: ${(_currentVolume * 100).toInt()}%",
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
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
        if (inBox)
          widgets.add(_buildBoxWidget(currentBoxTitle, currentBoxItems));
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
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
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

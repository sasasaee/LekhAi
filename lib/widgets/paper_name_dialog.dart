import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import '../services/audio_recorder_service.dart';
import '../services/gemini_paper_service.dart';
import '../services/tts_service.dart';
import '../services/picovoice_service.dart';
import '../services/voice_command_service.dart';
import '../utils/string_utils.dart';

/// A dialog that lets the user both type a paper name and dictate it via voice,
/// using the same audio → Gemini transcription → confirm flow as ExamInfoScreen.
///
/// Listens to VoiceCommandService stream for:
/// - confirmAction / saveResult → saves the current name
/// - cancelAction / goBack → cancels
/// - setStudentName / renameFile → starts audio dictation
class PaperNameDialog extends StatefulWidget {
  final String initialName;
  final TtsService ttsService;
  final PicovoiceService picovoiceService;
  final VoiceCommandService voiceService;

  const PaperNameDialog({
    super.key,
    required this.initialName,
    required this.ttsService,
    required this.picovoiceService,
    required this.voiceService,
  });

  @override
  State<PaperNameDialog> createState() => _PaperNameDialogState();
}

class _PaperNameDialogState extends State<PaperNameDialog> {
  late TextEditingController _nameController;
  final AudioRecorderService _recorder = AudioRecorderService();
  StreamSubscription<CommandResult>? _subscription;

  bool _isListening = false;
  bool _isListeningDialogOpen = false;
  bool _isTranscribingDialogOpen = false;
  String? _tempAudioPath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);

    // Listen to voice command stream for confirm / set name / cancel
    _subscription = widget.voiceService.commandStream.listen(_handleCommand);

    // Announce dialog for accessibility
    if (widget.initialName.isNotEmpty) {
      widget.ttsService.speak(
        "Name this paper. Suggested name: ${widget.initialName}. "
        "Say 'Confirm' to save, 'Set Name' to dictate a new name, or 'Skip' to dismiss.",
      );
    } else {
      widget.ttsService.speak(
        "Name this paper. Say 'Set Name' to dictate a name, or 'Skip' to dismiss.",
      );
    }

    // Listen for wake word to stop recording
    widget.picovoiceService.stateNotifier.addListener(_onPicovoiceState);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    widget.picovoiceService.stateNotifier.removeListener(_onPicovoiceState);
    _nameController.dispose();
    super.dispose();
  }

  /// Handle voice commands while this dialog is showing
  void _handleCommand(CommandResult result) {
    if (!mounted) return;

    switch (result.action) {
      // --- CONFIRM: save with current name ---
      case VoiceAction.confirmAction:
      case VoiceAction.saveResult:
      case VoiceAction.confirmExamStart:
        _confirmAndClose();
        break;

      // --- CANCEL: dismiss dialog ---
      case VoiceAction.cancelAction:
      case VoiceAction.goBack:
        Navigator.pop(context, null);
        break;

      // --- SET NAME / RENAME: start dictation ---
      case VoiceAction.setStudentName:
      case VoiceAction.renameFile:
        _startListening();
        break;

      default:
        break;
    }
  }

  void _confirmAndClose() {
    final name = _nameController.text.trim();
    Navigator.pop(context, name.isNotEmpty ? name : null);
  }

  void _onPicovoiceState() {
    if (widget.picovoiceService.stateNotifier.value ==
        PicovoiceState.wakeDetected) {
      if (_isListening) _stopListening();
    }
  }

  // ─── Audio Dictation Flow (mirrors ExamInfoScreen) ───

  Future<void> _startListening() async {
    if (_isListening) return;
    await widget.ttsService.speak("Listening. Say hey lekhai stop to finish.");
    await Future.delayed(const Duration(milliseconds: 600));
    final tempDir = await getTemporaryDirectory();
    _tempAudioPath =
        '${tempDir.path}/paper_name_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.startRecording(_tempAudioPath!);
      setState(() => _isListening = true);

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
                Expanded(
                  child: Text("Listening... Say 'hey lekhai stop' to finish."),
                ),
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
    if (!_isListening) return;
    final path = await _recorder.stopRecording();

    if (_isListeningDialogOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _isListeningDialogOpen = false;
    }
    setState(() => _isListening = false);

    if (path == null) {
      widget.ttsService.speak("Recording failed.");
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

    await _transcribeAndApply(path);
  }

  Future<void> _transcribeAndApply(String audioPath) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    String transcribed = '';

    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final svc = GeminiPaperService();
        transcribed = await svc.transcribeAudio(
          audioPath,
          apiKey,
          contextPrompt:
              "Extract ONLY the paper or document title from this audio. "
              "Ignore wake words such as 'hey lekhai', 'stop to finish', etc. "
              "Only output the title. No extra symbols.",
        );
      } catch (e) {
        transcribed = '';
        widget.ttsService.speak("Transcription failed. Please try again.");
      } finally {
        if (mounted && _isTranscribingDialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          _isTranscribingDialogOpen = false;
        }
      }
    } else {
      widget.ttsService.speak(
        "No API Key found. Please type the name manually.",
      );
      if (mounted && _isTranscribingDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        _isTranscribingDialogOpen = false;
      }
    }

    if (!mounted) return;

    final processed = StringUtils.stripWakeWordsAndCommands(transcribed).trim();
    if (processed.isEmpty) {
      widget.ttsService.speak("I couldn't hear a name. Please try again.");
      widget.picovoiceService.resumeListening();
      return;
    }

    // Spell it out and ask for confirmation (same pattern as ExamInfoScreen)
    final spelled = processed.split('').join('. ');
    widget.ttsService.speak(
      "You said: $spelled. That is $processed. Say confirm to save, or cancel to retry.",
    );

    // Update the text field immediately so the user can see it
    setState(() => _nameController.text = processed);
    widget.picovoiceService.resumeListening();
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Name this Paper"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "e.g. Physics Midterm",
              labelText: "Paper Name",
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.mic, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isListening
                      ? "🔴 Listening... say 'hey lekhai stop'"
                      : "Say 'Set Name' to dictate, or 'Confirm' to save.",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text("Skip"),
        ),
        IconButton(
          onPressed: _isListening ? _stopListening : _startListening,
          icon: Icon(
            _isListening ? Icons.stop_circle : Icons.mic,
            color: _isListening ? Colors.red : null,
          ),
          tooltip: _isListening ? "Stop recording" : "Dictate name",
        ),
        ElevatedButton(onPressed: _confirmAndClose, child: const Text("Save")),
      ],
    );
  }
}

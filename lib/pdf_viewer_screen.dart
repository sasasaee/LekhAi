import 'package:flutter/material.dart';
import 'services/tts_service.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter_pdf_text/flutter_pdf_text.dart';
import 'dart:io';
import 'services/voice_command_service.dart';
import 'services/stt_service.dart';
import 'package:google_fonts/google_fonts.dart'; // Added

// import 'dart:ui'; // Added
// import 'widgets/accessible_widgets.dart'; // Added

class PdfViewerScreen extends StatefulWidget {
  final String path;
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  const PdfViewerScreen({
    super.key,
    required this.path,
    required this.ttsService,
    required this.voiceService,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final SttService _sttService = SttService();
  final bool _isListening = false;

  PDFDoc? _doc;
  List<String> _sentences = [];
  int _currentIndex = 0;
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
    _initVoiceCommandListener();
  }

  @override
  void dispose() {
    _sttService.stopListening();
    widget.ttsService.stop(); // Stop audio when leaving screen
    super.dispose();
  }

  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      tts: widget.ttsService,
      onStatus: (status) {
        if ((status == 'notListening' || status == 'done') && !_isListening) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isListening) _startCommandStream();
          });
        }
      },
      onError: (error) => debugPrint("PDF Viewer STT Error: $error"),
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
          context: VoiceContext.pdfViewer,
        );
        if (result.action != VoiceAction.unknown) {
          _handleVoiceCommand(result);
        }
      },
    );
  }

  void _handleVoiceCommand(CommandResult result) {
    if (!mounted) return;
    switch (result.action) {
      case VoiceAction.nextPage:
        _pdfController.nextPage();
        widget.ttsService.speak("Next page");
        break;
      case VoiceAction.previousPage:
        _pdfController.previousPage();
        widget.ttsService.speak("Previous page");
        break;
      case VoiceAction.stopDictation: // Reuse stop action
        _stopReading();
        break;
      case VoiceAction.pauseReading:
        _pauseReading();
        break;
      case VoiceAction.resumeReading:
        _resumeReading();
        break;
      case VoiceAction.restartReading:
        _restartReading();
        break;
      case VoiceAction.goBack:
        Navigator.pop(context);
        break;
      // Fallback
      case VoiceAction.goToHome:
      case VoiceAction.goToSettings:
      case VoiceAction.goToSavedPapers:
      case VoiceAction.goToReadPDF:
      case VoiceAction.goToTakeExam:
        widget.voiceService.performGlobalNavigation(result);
        break;
      default:
        break;
    }
  }

  Future<void> _loadPdf() async {
    _doc = await PDFDoc.fromPath(widget.path);
    String text = await _doc!.text;
    _sentences = text.split(RegExp(r'(?<=[.!?])\s+')); // split by sentence
    _currentIndex = 0;
    _startReading();
  }

  void _startReading() async {
    if (_isReading) return;
    _isReading = true;

    while (_currentIndex < _sentences.length) {
      if (!mounted) break;

      if (widget.ttsService.isPaused) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue; // wait while paused
      }

      // Stop reading if listening to voice command?
      // Handled by TtsService stream in SttService -> actually STT pauses when TTS speaks.
      // So here we are fine.

      String sentence = _sentences[_currentIndex].trim();
      if (sentence.isNotEmpty) {
        await widget.ttsService.speakAndWait(sentence);
      }

      _currentIndex++;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _isReading = false;
  }

  void _stopReading() async {
    _currentIndex = 0;
    _isReading = false;
    await widget.ttsService.stop();
  }

  void _pauseReading() async {
    await widget.ttsService.pause();
  }

  void _resumeReading() async {
    await widget.ttsService.resume();
    _startReading(); // Continue reading where left off
  }

  void _restartReading() async {
    await widget.ttsService.stop();
    _currentIndex = 0;
    _isReading = false;
    _startReading();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'PDF Viewer',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: 0.3,
            ), // Darker background for visibility over PDF?
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black, // Dark top for AppBar visibility
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0.1, 0.3], // Quickly fade to scaffold bg
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: SfPdfViewer.file(
                    File(widget.path),
                    controller: _pdfController,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _ControlBtn(
                        icon: Icons.pause_rounded,
                        label: "Pause",
                        onTap: _pauseReading,
                      ),
                      _ControlBtn(
                        icon: Icons.play_arrow_rounded,
                        label: "Resume",
                        onTap: _resumeReading,
                        isPrimary: true,
                      ),
                      _ControlBtn(
                        icon: Icons.stop_rounded,
                        label: "Stop",
                        onTap: _stopReading,
                        isDanger: true,
                      ),
                      _ControlBtn(
                        icon: Icons.replay_rounded,
                        label: "Restart",
                        onTap: _restartReading,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDanger;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    Color baseColor = isPrimary
        ? Theme.of(context).primaryColor
        : (isDanger ? Colors.redAccent : Colors.white24);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: isPrimary || isDanger ? 1.0 : 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary || isDanger ? Colors.transparent : Colors.white30,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

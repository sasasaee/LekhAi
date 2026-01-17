import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'services/ocr_service.dart';
import 'services/question_storage_service.dart';
import 'services/tts_service.dart';
import 'services/question_segmentation_service.dart';
import 'models/question_model.dart';
import 'questions_screen.dart';
import 'services/voice_command_service.dart';
import 'services/stt_service.dart';

import 'services/accessibility_service.dart';
import 'widgets/accessible_widgets.dart'; // Added
// import 'widgets/animated_button.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart'; // Ensure animate is available
import 'dart:ui'; // For ImageFilter

// ... existing imports

class OcrScreen extends StatefulWidget {
  // ... (unchanged)
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService? accessibilityService;

  const OcrScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    this.accessibilityService,
  });

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  // ... (unchanged state variables and methods)
  final OcrService _ocrService = OcrService();
  final QuestionStorageService _storageService = QuestionStorageService();
  final QuestionSegmentationService _segmenter = QuestionSegmentationService();
  final ImagePicker _picker = ImagePicker();

  final SttService _sttService = SttService();
  bool _isListening = false;

  bool _isProcessing = false;
  File? _imageFile;
  ParsedDocument? _doc;
  List<OcrLine> _rawLines = [];

  // ... (maintain all existing methods: initState, _retrieveLostData, _pickImage, _processImage, _saveParsed, dispose)

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak(
      "Welcome to the OCR screen. You can scan from camera or select from gallery.",
    );
    _retrieveLostData();
    _initVoiceCommandListener();
  }

  // --- VOICE COMMAND LOGIC ---
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
      onError: (error) => print("OCR Screen STT Error: $error"),
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
        // Parse with OCR context!
        final result = widget.voiceService.parse(
          text,
          context: VoiceContext.ocr,
        );

        if (result.action != VoiceAction.unknown) {
          _handleVoiceCommand(result);
        }
      },
    );
  }

  void _handleVoiceCommand(CommandResult result) {
    if (!mounted) return;

    // Stop listener momentarily if action takes over UI or TTS speaks
    // But since we have auto-pause, we generally just execute.

    switch (result.action) {
      case VoiceAction.scanCamera:
        if (!_isProcessing) _pickImage(ImageSource.camera);
        break;
      case VoiceAction.scanGallery:
        if (!_isProcessing) _pickImage(ImageSource.gallery);
        break;
      case VoiceAction.saveResult:
        _saveParsed();
        break;
      case VoiceAction.goBack:
        Navigator.pop(context);
        break;
      // Fallback to global
      case VoiceAction.goToHome:
      case VoiceAction.goToSettings:
      case VoiceAction.goToSavedPapers:
      case VoiceAction.goToReadPDF:
        widget.voiceService.performGlobalNavigation(result);
        break;
      default:
        break;
    }
  }

  Future<void> _retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) return;
    if (response.file != null) {
      setState(() {
        _imageFile = File(response.file!.path);
        _isProcessing = true;
        _doc = null;
        _rawLines = [];
      });
      await _processImage(response.file!.path);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _imageFile = File(image.path);
        _isProcessing = true;
        _doc = null;
        _rawLines = [];
      });

      await _processImage(image.path);
    } catch (e) {
      AccessibilityService().trigger(AccessibilityEvent.error);
      widget.ttsService.speak("Error picking image");
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processImage(String path) async {
    try {
      AccessibilityService().trigger(AccessibilityEvent.loading);
      // 1) OCR -> lines
      final lines = await _ocrService.processImageLines(path);

      // 2) Rule-based segmentation
      final doc = _segmenter.segment(lines);

      setState(() {
        _rawLines = lines;
        _doc = doc;
      });

      final qCount = doc.sections.fold<int>(
        0,
        (sum, s) => sum + s.questions.length,
      );

      widget.ttsService.speak(
        qCount == 0
            ? "Text extracted, but I could not detect questions clearly."
            : "Extracted and segmented $qCount questions. Tap save to store.",
      );
      AccessibilityService().trigger(AccessibilityEvent.success);
    } catch (e) {
      AccessibilityService().trigger(AccessibilityEvent.error);
      widget.ttsService.speak("Error processing image");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveParsed() async {
    AccessibilityService().trigger(AccessibilityEvent.loading);
    final doc = _doc;

    if (doc == null) {
      AccessibilityService().trigger(AccessibilityEvent.error);
      return;
    }

    try {
      await _storageService.saveDocument(doc);
      AccessibilityService().trigger(AccessibilityEvent.success);
      widget.ttsService.speak("Saved successfully");

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionsScreen(
            ttsService: widget.ttsService,
            voiceService: widget.voiceService,
            accessibilityService: widget.accessibilityService,
          ),
        ),
      );
    } catch (e) {
      AccessibilityService().trigger(AccessibilityEvent.error);
      widget.ttsService.speak("Error saving document.");
    }
  }

  @override
  void dispose() {
    _sttService.stopListening();
    _ocrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Scan Question',
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _GlassButton(
                        icon: Icons.camera_alt_outlined,
                        label: "Camera",
                        color: Theme.of(context).primaryColor,
                        onTap: _isProcessing
                            ? null
                            : () => _pickImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _GlassButton(
                        icon: Icons.photo_library_outlined,
                        label: "Gallery",
                        color: Theme.of(context).colorScheme.secondary,
                        onTap: _isProcessing
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                if (_imageFile == null && !_isProcessing)
                  Container(
                    height: 300,
                    margin: const EdgeInsets.only(top: 32),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.document_scanner_rounded,
                                size: 64,
                                color: Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.8),
                              ),
                            )
                            .animate(
                              onPlay: (controller) =>
                                  controller.repeat(reverse: true),
                            )
                            .scaleXY(begin: 1.0, end: 1.1, duration: 2.seconds),
                        const SizedBox(height: 24),
                        Text(
                          "Ready to Scan",
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            "Capture a photo of your question paper or choose from gallery to analyze.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              color: Colors.white54,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 800.ms),

                if (_imageFile != null)
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black12,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(_imageFile!, fit: BoxFit.contain),
                    ),
                  ).animate().fadeIn(),

                const SizedBox(height: 16),

                if (_isProcessing)
                  const Center(child: CircularProgressIndicator())
                else if (doc != null) ...[
                  Text(
                    'Detected Header:',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _GlassBox(
                    child: Text(
                      doc.header.join("\n"),
                      style: GoogleFonts.outfit(color: Colors.white70),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'Detected Questions:',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (doc.sections.isEmpty)
                    _GlassBox(
                      child: Text(
                        "No sections/questions detected.",
                        style: GoogleFonts.outfit(color: Colors.white70),
                      ),
                    )
                  else
                    ...doc.sections.map((s) {
                      return _SectionPreview(section: s);
                    }),

                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _saveParsed,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(
                      'Save Result',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 8,
                      shadowColor: Theme.of(
                        context,
                      ).primaryColor.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),

                  const SizedBox(height: 12),
                  Text(
                    "Debug: OCR lines = ${_rawLines.length}",
                    style: GoogleFonts.outfit(
                      color: Colors.white24,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _GlassButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.2), color.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassBox extends StatelessWidget {
  final Widget child;
  const _GlassBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

// ... (keep _SectionPreview but maybe update styling slightly if needed, or leave generic)

class _BoxText extends StatelessWidget {
  final String text;
  const _BoxText(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: GoogleFonts.outfit(color: Colors.white70)),
    );
  }
}

class _SectionPreview extends StatelessWidget {
  final ParsedSection section;
  const _SectionPreview({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title != null && section.title!.trim().isNotEmpty) ...[
            Text(
              section.title!,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (section.questions.isEmpty)
            Text(
              "No questions found in this section.",
              style: GoogleFonts.outfit(color: Colors.white70),
            )
          else
            ...section.questions.take(6).map((q) {
              final title = q.number != null ? "Q${q.number}" : "Q";
              final marks = (q.marks != null && q.marks!.trim().isNotEmpty)
                  ? "   (${q.marks})"
                  : "";
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$title$marks: ${q.prompt}",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (q.body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          q.body.join("\n"),
                          style: GoogleFonts.outfit(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              );
            }),
          if (section.questions.length > 6)
            Text(
              "…and ${section.questions.length - 6} more",
              style: GoogleFonts.outfit(color: Colors.white38),
            ),
        ],
      ),
    );
  }
}

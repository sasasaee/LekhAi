import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async'; // For Timer/Future

// Services
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';
import 'services/accessibility_service.dart';
// import 'services/stt_service.dart'; // Removed
// Screens
import 'questions_screen.dart';
import 'preferences_screen.dart';
import 'services/picovoice_service.dart';
import 'widgets/picovoice_mic_icon.dart';

// import 'dart:ui'; // For standard imports if needed
// import 'widgets/accessible_widgets.dart';
// import 'package:image_picker/image_picker.dart';

class TakeExamScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;
  final PicovoiceService picovoiceService;
  // final SttService sttService; // Removed

  const TakeExamScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
    required this.picovoiceService,
    // required this.sttService, // Removed
  });

  @override
  State<TakeExamScreen> createState() => _TakeExamScreenState();
}

class _TakeExamScreenState extends State<TakeExamScreen> {
  // bool _shouldListen = true; // Removed

  StreamSubscription<CommandResult>? _commandSubscription;

  @override
  void initState() {
    super.initState();
    widget.accessibilityService.trigger(AccessibilityEvent.navigation);
    widget.ttsService.speak("Take Exam.");
    _subscribeToVoiceCommands();
  }

  @override
  void dispose() {
    _commandSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToVoiceCommands() {
    _commandSubscription = widget.voiceService.commandStream.listen((result) {
      _handleVoiceCommand(result);
    });
  }

  void _handleVoiceCommand(CommandResult result) {
    if (!mounted) return;
    switch (result.action) {
      case VoiceAction.scanQuestions:
        _handleScan();
        break;
      case VoiceAction.scanCamera:
        // Force camera logic if possible, or just call _handleScan which shows dialog
        _handleScan();
        break;
      case VoiceAction.scanGallery:
        // Force gallery logic if possible
        _handleScan();
        break;
      case VoiceAction.goBack:
        Navigator.pop(context);
        break;
      default:
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
  }

  Future<void> _handleScan() async {
    widget.voiceService.performGlobalNavigation(
      CommandResult(VoiceAction.scanQuestions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Image.asset('assets/images/logo.png', width: 140, height: 80),
        centerTitle: true,
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
            tooltip: "Back",
            onPressed: () {
              widget.accessibilityService.trigger(AccessibilityEvent.action);
              Navigator.pop(context);
            },
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Exam Tools",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ).animate().fadeIn().slideY(begin: -0.2, end: 0),
                  const SizedBox(height: 8),
                  Text(
                    "Select an option to begin",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: Colors.white54,
                    ),
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 48),

                  _ExamActionTile(
                    icon: Icons.camera_alt_outlined,
                    label: "Scan Questions",
                    subLabel: "Capture & Analyze",
                    color: const Color(0xFF3B82F6),
                    delay: 400,
                    onTap: _handleScan,
                  ),
                  const SizedBox(height: 20),
                  _ExamActionTile(
                    icon: Icons.question_answer_outlined,
                    label: "Saved Questions",
                    subLabel: "Review Archives",
                    color: const Color(0xFF10B981),
                    delay: 500,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuestionsScreen(
                            ttsService: widget.ttsService,
                            voiceService: widget.voiceService,
                            picovoiceService: widget.picovoiceService,
                            isSelectionMode: true, // Exam FLow
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _ExamActionTile(
                    icon: Icons.settings_outlined,
                    label: "Preferences",
                    subLabel: "Configure Settings",
                    color: const Color(0xFF8B5CF6),
                    delay: 600,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PreferencesScreen(
                            ttsService: widget.ttsService,
                            voiceService: widget.voiceService,
                            picovoiceService: widget.picovoiceService,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExamActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subLabel;
  final Color color;
  final int delay;
  final VoidCallback onTap;

  const _ExamActionTile({
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.color,
    required this.delay,
    required this.onTap,
  });

  @override
  State<_ExamActionTile> createState() => _ExamActionTileState();
}

class _ExamActionTileState extends State<_ExamActionTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: 150.ms);
    _scale = Tween<double>(begin: 1.0, end: 0.98).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        AccessibilityService().trigger(AccessibilityEvent.action);
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child:
          ScaleTransition(
                scale: _scale,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 30),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.label,
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.subLabel,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: Colors.white54,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white24,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: widget.delay.ms)
              .slideX(begin: 0.1, end: 0, curve: Curves.easeOutBack),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'theme/app_theme.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

// Services
import 'services/tts_service.dart';
import 'services/gemini_question_service.dart';
import 'services/voice_command_service.dart';
import 'services/stt_service.dart';
import 'services/accessibility_service.dart';

// Screens
import 'preferences_screen.dart';
import 'ocr_screen.dart';
import 'questions_screen.dart';
import 'pdf_viewer_screen.dart';
import 'paper_detail_screen.dart';
import 'start_page.dart'; // Imported StartPage
import 'take_exam_screen.dart'; // Extracted screen
import 'models/question_model.dart';
import 'widgets/accessible_widgets.dart';
import 'widgets/animated_button.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Initialize core services at the top level
  final TtsService ttsService = TtsService();
  final AccessibilityService accessibilityService = AccessibilityService();
  late final VoiceCommandService voiceCommandService;

  MyApp({super.key}) {
    // Inject TTS into the Voice Command Service
    voiceCommandService = VoiceCommandService(ttsService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LekhAi',
      navigatorKey: voiceCommandService.navigatorKey,
      theme: AppTheme.darkTheme,
      home: SplashScreen(
        ttsService: ttsService,
        voiceService: voiceCommandService,
        accessibilityService: accessibilityService,
      ),
      debugShowCheckedModeBanner: false,
      routes: {
        '/home': (context) => HomeScreen(
          ttsService: ttsService,
          voiceService: voiceCommandService,
          accessibilityService: accessibilityService,
        ),
        '/saved_papers': (context) => QuestionsScreen(
          ttsService: ttsService,
          voiceService: voiceCommandService,
          // accessibilityService: accessibilityService,
        ),
        '/settings': (context) => PreferencesScreen(
          ttsService: ttsService,
          voiceService: voiceCommandService,
        ),
        '/take_exam': (context) {
          throw UnimplementedError(
            "Use named route with arguments or direct navigation",
          );
        },
      },
    );
  }
}

// ---------------------- Splash Screen ----------------------

class SplashScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;

  const SplashScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StartPage(
            // Navigate to StartPage first
            ttsService: widget.ttsService,
            voiceService: widget.voiceService,
            accessibilityService: widget.accessibilityService,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.2),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Center(
          child:
              Hero(
                    tag:
                        'app_logo', // Hero tag for smooth transition to StartPage
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 260,
                      height: 260,
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .scale(
                    duration: const Duration(seconds: 2),
                    begin: const Offset(1, 1),
                    end: const Offset(1.05, 1.05),
                  )
                  .fadeIn(duration: const Duration(milliseconds: 800)),
        ),
      ),
    );
  }
}

// ---------------------- Home Screen ----------------------

class HomeScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;

  const HomeScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // late Animation<double> _animation; // Unused
  late Timer _timeTimer;
  String _currentTimeStr = "";

  // Added: Speech-to-text service for background command listening
  final SttService _sttService = SttService();
  // Flag to track if we are intentionally listening
  bool _shouldListen = true;

  static const Color buttonColor = Color(0xFF1283B2);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    // 1. CRITICAL: Initialize voice command listener FIRST before any TTS
    // This ensures STT subscribes to TTS events before speech starts
    _initVoiceCommandListener();

    // 2. Initial Greeting & Haptics (AFTER STT init)
    widget.accessibilityService.trigger(AccessibilityEvent.navigation);
    widget.ttsService.speak("Welcome.");

    // 3. Start Time Timer
    _updateTime();
    _timeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _updateTime(),
    );
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTimeStr =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    });
  }

  // --- VOICE COMMAND LOGIC ---
  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      tts: widget.ttsService, // Pass TTS to enable auto-pause
      onStatus: (status) {
        // print("Home STT Status: $status");
        // Keep-Alive: Restart if the OS stops the microphone due to timeout
        if (status == 'notListening' || status == 'done') {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _shouldListen) _startListeningLoop();
          });
        }
      },
      onError: (error) => print("Home STT Error: $error"),
    );

    if (available) {
      _startListeningLoop();
    }
  }

  void _startListeningLoop() {
    if (!_sttService.isAvailable || !_shouldListen) return;

    _sttService.startListening(
      localeId: "en-US",
      onResult: (text) {
        // Parse the spoken text into a VoiceAction
        final result = widget.voiceService.parse(text);

        if (result.action != VoiceAction.unknown) {
          if (_shouldListen) _handleHomeVoiceCommand(result);
        }
      },
    );
  }

  void _handleHomeVoiceCommand(CommandResult result) async {
    // If the action involves navigation away from Home, stop listening first.
    bool willNavigate =
        result.action == VoiceAction.goToSavedPapers ||
        result.action == VoiceAction.goToTakeExam ||
        result.action == VoiceAction.goToSettings ||
        result.action == VoiceAction.goToReadPDF;

    if (willNavigate) {
      _shouldListen = false;
      await _sttService.stopListening();
    }

    switch (result.action) {
      case VoiceAction.goToSavedPapers:
        await widget.ttsService.speak("Opening saved papers.");
        await widget.voiceService.performGlobalNavigation(result);
        break;

      case VoiceAction.goToTakeExam:
        await widget.ttsService.speak("Starting exam mode.");
        // _openTakeExam handles its own navigation logic but we double check
        // _openTakeExam actually calls push, so we can use performGlobalNavigation or custom method
        // But the custom method _openTakeExam ALREADY handles stop/start!
        // So we should delegate to it or use performGlobalNav if it does the same.
        // NOTE: _openTakeExam passes the STT service which might be needed.
        // Let's stick to _openTakeExam for consistency if it does special setup.
        await _openTakeExam(); // This handles its own start/stop
        return; // Return early as we handled resume in _openTakeExam

      default:
        // Handle other global navigation commands
        await widget.voiceService.performGlobalNavigation(result);
        break;
    }

    // Resume listening if we navigated away and came back (or if action didn't navigate)
    if (willNavigate && mounted) {
      _shouldListen = true;
      _initVoiceCommandListener();
    }
  }

  @override
  void dispose() {
    _sttService.stopListening(); // Stop microphone when leaving home
    _controller.dispose();
    _timeTimer.cancel();
    super.dispose();
  }

  // --- NAVIGATION METHODS ---

  Future<void> _openPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) {
      widget.ttsService.speak("No PDF selected.");
      return;
    }

    String path = result.files.single.path!;
    if (!mounted) return;

    // Stop home listener before entering PDF viewer to avoid mic conflicts
    _shouldListen = false;
    await _sttService.stopListening();

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          path: path,
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
        ),
      ),
    ).then((_) {
      _shouldListen = true;
      _initVoiceCommandListener();
    }); // Restart when coming back
  }

  Future<void> _openTakeExam() async {
    _shouldListen = false;
    await _sttService.stopListening(); // Stop home listener (await is CRITICAL)

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TakeExamScreen(
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
          sttService: _sttService,
        ),
      ),
    ).then((_) {
      _shouldListen = true;
      _initVoiceCommandListener();
    }); // Restart when coming back
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("About LekhAi"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Version 1.0.0"),
            const SizedBox(height: 8),
            const Text("L."),
            const SizedBox(height: 16),
            Text(
              "Developed by:",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Text("LekhAi Team"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Current date for the dashboard header
    final now = DateTime.now();
    final dateStr = "${now.day}/${now.month}/${now.year}";

    return Scaffold(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Welcome to LekhAi",
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ).animate().fadeIn(duration: 600.ms).slideX(),
                          const SizedBox(height: 12),
                          // Date & Time Container
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "$dateStr  •  $_currentTimeStr",
                                  style: GoogleFonts.outfit(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ).animate().scale(
                            delay: 200.ms,
                            curve: Curves.easeOutBack,
                          ),
                        ],
                      ),
                    ),
                    // About Button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.info_outline_rounded),
                        color: Colors.white70,
                        tooltip: "About",
                        onPressed: _showAboutDialog,
                      ),
                    ).animate().fadeIn(delay: 400.ms).scale(),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // --- Grid Menu ---
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 24,
                  childAspectRatio: 0.82,
                  children: [
                    _DashboardCard(
                      icon: Icons.assignment_outlined,
                      label: "Take Exam",
                      subLabel: "Scan & Solve",
                      color: const Color(0xFF3B82F6), // Blue
                      delay: 600,
                      onTap: _openTakeExam,
                    ),
                    _DashboardCard(
                      icon: Icons.picture_as_pdf_outlined,
                      label: "Read PDF",
                      subLabel: "Listen & Learn",
                      color: const Color(0xFFF43F5E), // Rose
                      delay: 700,
                      onTap: _openPdf,
                    ),
                    _DashboardCard(
                      icon: Icons.folder_special_outlined,
                      label: "Saved Papers",
                      subLabel: "Your Archive",
                      color: const Color(0xFF10B981), // Emerald
                      delay: 800,
                      onTap: () async {
                        widget.ttsService.speak("Opening saved papers.");
                        _shouldListen = false;
                        await _sttService.stopListening();
                        if (!mounted) return;
                        Navigator.pushNamed(context, '/saved_papers').then((_) {
                          _shouldListen = true;
                          _initVoiceCommandListener();
                        });
                      },
                    ),
                    _DashboardCard(
                      icon: Icons.settings_outlined,
                      label: "Preferences",
                      subLabel: "Customize App",
                      color: const Color(0xFF8B5CF6), // Violet
                      delay: 900,
                      onTap: () async {
                        widget.ttsService.speak("Opening preferences.");
                        _shouldListen = false;
                        await _sttService.stopListening();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PreferencesScreen(
                              ttsService: widget.ttsService,
                              voiceService: widget.voiceService,
                            ),
                          ),
                        ).then((_) {
                          _shouldListen = true;
                          _initVoiceCommandListener();
                        });
                      },
                    ),
                  ],
                ),
              ),

              // --- Footer (Copyright) ---
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    "© 2026 LekhAi. All rights reserved.",
                    style: GoogleFonts.outfit(
                      color: Colors.white24,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ).animate().fadeIn(delay: 1.seconds),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subLabel;
  final Color color;
  final int delay;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.label,
    required this.subLabel, // Added subLabel for professionalism
    required this.color,
    required this.delay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        AccessibilityService().trigger(AccessibilityEvent.action);
        onTap();
      },
      child:
          Container(
                decoration: BoxDecoration(
                  // Glassmorphism effect
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  // Clip for any internal overflow if needed
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 4,
                      sigmaY: 4,
                    ), // Subtle blur behind
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color.withOpacity(0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(icon, size: 36, color: color),
                            )
                            .animate(onPlay: (c) => c.loop(period: 4.seconds))
                            .shimmer(delay: 2.seconds, duration: 1.seconds),

                        const SizedBox(height: 20),

                        Text(
                          label,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 6),

                        Text(
                          subLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.white54,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: delay.ms, duration: 600.ms)
              .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
    );
  }
}

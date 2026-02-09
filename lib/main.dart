import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';

// Services
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';
import 'services/picovoice_service.dart';
import 'widgets/picovoice_mic_icon.dart'; // Changed
import 'services/accessibility_service.dart';
// Screens
import 'take_exam_screen.dart'; // Extracted screen
import 'preferences_screen.dart';
import 'questions_screen.dart';
import 'pdf_viewer_screen.dart';
import 'start_page.dart'; // Imported StartPage
import 'widgets/picovoice_mic_icon.dart';

// import 'dart:ui';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:image_picker/image_picker.dart';
// import 'services/gemini_question_service.dart';
// import 'ocr_screen.dart';
// import 'paper_detail_screen.dart';
// import 'models/question_model.dart';
// import 'widgets/accessible_widgets.dart';
// import 'widgets/animated_button.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Initialize core services at the top level
  final TtsService ttsService = TtsService();
  final AccessibilityService accessibilityService = AccessibilityService();
  late final VoiceCommandService voiceCommandService;
  final PicovoiceService picovoiceService = PicovoiceService(); // Added

  MyApp({super.key}) {
    // Inject TTS and Picovoice into the Voice Command Service
    voiceCommandService = VoiceCommandService(ttsService, picovoiceService);
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
        picovoiceService: picovoiceService, // Passed
      ),
      debugShowCheckedModeBanner: false,
      routes: {
        '/home': (context) => HomeScreen(
          ttsService: ttsService,
          voiceService: voiceCommandService,
          accessibilityService: accessibilityService,
          picovoiceService: picovoiceService, // Passed
        ),
        '/saved_papers': (context) => QuestionsScreen(
          ttsService: ttsService,
          voiceService: voiceCommandService,
          picovoiceService: picovoiceService,
          // accessibilityService: accessibilityService,
        ),
        '/settings': (context) => PreferencesScreen(
          ttsService: ttsService,
          voiceService: voiceCommandService,
          picovoiceService: picovoiceService, // Passed for AccessKey update
        ),
        '/take_exam': (context) => TakeExamScreen(
          ttsService: ttsService,
          voiceService: voiceCommandService,
          accessibilityService: accessibilityService,
          picovoiceService: picovoiceService,
        ),
      },
    );
  }
}

// ---------------------- Splash Screen ----------------------

class SplashScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;
  final PicovoiceService picovoiceService;

  const SplashScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
    required this.picovoiceService,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    
    // Initialize Picovoice Service (Async)
    widget.picovoiceService.init(widget.voiceService);

    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/start'),
          builder: (_) => StartPage(
            // Navigate to StartPage first
            ttsService: widget.ttsService,
            voiceService: widget.voiceService,
            accessibilityService: widget.accessibilityService,
            picovoiceService: widget.picovoiceService,
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
              Theme.of(context).primaryColor.withValues(alpha: 0.2),
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
  final PicovoiceService picovoiceService;

  const HomeScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
    required this.picovoiceService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Timer _timeTimer;
  String _currentTimeStr = "";

  // NO SttService here anymore
  
  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _controller.forward();

    // 1. Voice Command Listener is now managed by PicovoiceService globally (in Splash/Main)
    // We can observe state if needed for UI feedback

    // 2. Initial Greeting & Haptics
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

  @override
  void dispose() {
    // Picovoice continues running in background/navigation, unlike SttService loop
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

    // No need to stop listening manually, Picovoice handles lifecycle via service
    // But if we wanted to pause it during PDF reading specifically we could.
    // For now, let it run (it pauses on TTS anyway).

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          path: path,
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          picovoiceService: widget.picovoiceService,
        ),
      ),
    );
  }

  Future<void> _openTakeExam() async {
    // Note: TakeExamScreen still expects SttService if not updated.
    // We should refactor TakeExamScreen to use PicovoiceService or remove Stt dependency.
    // For this step, we assume TakeExamScreen needs update or we pass null/dummy?
    // Based on prompt, we are only integrating into main.dart now.
    // BUT TakeExamScreen constructor will fail if we don't pass SttService?
    // Let's create a dummy or fix TakeExamScreen later. 
    // Actually, we must pass something. 
    // Ideally we should have refactored TakeExamScreen too.
    // For now, let's just NOT pass it and see (it is named argument usually?)
    // Checking previous file view... used `sttService: _sttService`. Make it optional there?
    // Or just create a local instance here if needed for legacy support until refactored.
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TakeExamScreen(
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
          picovoiceService: widget.picovoiceService,
        ),
      ),
    );
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
    return Scaffold(
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
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PicovoiceMicIcon(
                                  service: widget.picovoiceService,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "${DateFormat('EEE, d MMM').format(DateTime.now())}  •  $_currentTimeStr",
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
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
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

              // --- Vertical Menu ---
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DashboardCard(
                          icon: Icons.assignment_outlined,
                          label: "Take Exam",
                          subLabel: "Scan & Solve",
                          color: const Color(0xFF3B82F6), // Blue
                          delay: 600,
                          onTap: _openTakeExam,
                        ),
                        const SizedBox(height: 20),
                        _DashboardCard(
                          icon: Icons.picture_as_pdf_outlined,
                          label: "Read PDF",
                          subLabel: "Listen & Learn",
                          color: const Color(0xFFF43F5E), // Rose
                          delay: 700,
                          onTap: _openPdf,
                        ),
                        const SizedBox(height: 20),
                        _DashboardCard(
                          icon: Icons.settings_outlined,
                          label: "Preferences",
                          subLabel: "Customize App",
                          color: const Color(0xFF8B5CF6), // Violet
                          delay: 900,
                          onTap: () async {
                            widget.ttsService.speak("Opening preferences.");
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                settings: const RouteSettings(name: '/settings'),
                                builder: (_) => PreferencesScreen(
                                  ttsService: widget.ttsService,
                                  voiceService: widget.voiceService,
                                  picovoiceService: widget.picovoiceService, // Passed
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
                margin: const EdgeInsets.symmetric(
                  vertical: 8,
                ), // Add margin for spacing
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  // Glassmorphism effect
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
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Icon(icon, size: 30, color: color),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subLabel,
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
              )
              .animate()
              .fadeIn(delay: delay.ms, duration: 600.ms)
              .slideX(begin: 0.1, end: 0, curve: Curves.easeOutBack),
    );
  }
}

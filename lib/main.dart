import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

// Services
import 'services/tts_service.dart';
import 'services/gemini_question_service.dart';
import 'services/voice_command_service.dart'; // New Service
import 'services/tts_service.dart';
import 'services/gemini_question_service.dart';
import 'services/voice_command_service.dart'; 
import 'services/stt_service.dart';
import 'services/accessibility_service.dart'; // New Service

// Screens
import 'preferences_screen.dart';
import 'ocr_screen.dart';
import 'questions_screen.dart';
import 'pdf_viewer_screen.dart';
import 'paper_detail_screen.dart';
import 'models/question_model.dart';
import 'widgets/accessible_widgets.dart'; // Added

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Initialize core services at the top level
  final TtsService ttsService = TtsService();
  final AccessibilityService accessibilityService = AccessibilityService(); // Init
  late final VoiceCommandService voiceCommandService;

  MyApp({super.key}) {
    // Inject TTS into the Voice Command Service
    voiceCommandService = VoiceCommandService(ttsService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LekhAi',
      // CRITICAL: Attach the navigatorKey here for voice-driven navigation
      navigatorKey: voiceCommandService.navigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(
        ttsService: ttsService,
        voiceService: voiceCommandService,
        accessibilityService: accessibilityService,
      ),
      debugShowCheckedModeBanner: false,
      // Named routes make voice navigation easier to manage
      routes: {
        '/home': (context) => HomeScreen(
              ttsService: ttsService,
              voiceService: voiceCommandService,
              accessibilityService: accessibilityService,
            ),
        '/saved_papers': (context) => QuestionsScreen(
              ttsService: ttsService,
              voiceService: voiceCommandService,
              // accessibilityService: accessibilityService, // Propagate to other screens similarly
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
          builder: (_) => HomeScreen(
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
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          width: 220,
          height: 220,
          fit: BoxFit.contain,
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
  late Animation<double> _animation;

  // Added: Speech-to-text service for background command listening
  final SttService _sttService = SttService();
  bool _isListening = false; // Flag to track if we are intentionally listening

  static const Color buttonColor = Color(0xFF1283B2);

  @override
  void initState() {
    super.initState(); // Must be first

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    // 1. Initial Greeting & Haptics
    widget.accessibilityService.trigger(AccessibilityEvent.navigation);
    widget.ttsService.speak(
      "Welcome to the main screen. Choose 'Take Exam' or 'Read PDF'.",
    );

    // 2. Start listening for voice commands (like "saved papers")
    _initVoiceCommandListener();
  }

  // --- VOICE COMMAND LOGIC ---
  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      onStatus: (status) {
        print("Home STT Status: $status");
        // Keep-Alive: Restart if the OS stops the microphone due to timeout
        if (status == 'notListening' || status == 'done') {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _startListeningLoop();
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
    if (!_sttService.isAvailable) return;

    _sttService.startListening(
      localeId: "en-US",
      onResult: (text) {
        // Parse the spoken text into a VoiceAction
        final result = widget.voiceService.parse(text);
        
        if (result.action != VoiceAction.unknown) {
          _handleHomeVoiceCommand(result);
        }
      },
    );
  }

  void _handleHomeVoiceCommand(CommandResult result) async {
    switch (result.action) {
      case VoiceAction.goToSavedPapers:
        await widget.ttsService.speak("Opening saved papers.");
        widget.voiceService.performGlobalNavigation(result);
        break;
        
      case VoiceAction.goToTakeExam:
        await widget.ttsService.speak("Starting exam mode.");
        _openTakeExam();
        break;

      default:
        // Handle other global navigation commands
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
  }

  @override
  void dispose() {
    _sttService.stopListening(); // Stop microphone when leaving home
    _controller.dispose();
    super.dispose();
  }

  // --- NAVIGATION METHODS ---

  void _openPdf() async {
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
    _sttService.stopListening();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          path: path,
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
        ),
      ),
    ).then((_) => _initVoiceCommandListener()); // Restart when coming back
  }

  void _openTakeExam() {
    _sttService.stopListening(); // Stop home listener
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TakeExamScreen(
          ttsService: widget.ttsService,
          voiceService: widget.voiceService,
          accessibilityService: widget.accessibilityService,
        ),
      ),
    ).then((_) => _initVoiceCommandListener()); // Restart when coming back
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', width: 260, height: 160),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _animation,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedButton(
                icon: Icons.quiz,
                label: "Take Exam",
                onTap: _openTakeExam,
                // accessibilityService removed, handled internally
              ),
              const SizedBox(height: 32),
              AnimatedButton(
                icon: Icons.picture_as_pdf,
                label: "Read PDF",
                onTap: _openPdf,
                // accessibilityService removed
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------------------- Take Exam Screen ----------------------

class TakeExamScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;
  
  const TakeExamScreen({
    super.key, 
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
  });

  @override
  State<TakeExamScreen> createState() => _TakeExamScreenState();
}

class _TakeExamScreenState extends State<TakeExamScreen> {
  final GeminiQuestionService _geminiService = GeminiQuestionService();

  @override
  void initState() {
    super.initState();
    widget.accessibilityService.trigger(AccessibilityEvent.navigation);
    widget.ttsService.speak("Welcome to Take Exam. Choose an option.");
  }

  Future<void> _handleScan() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');

    if (!mounted) return;

    if (apiKey != null && apiKey.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Preferences'),
          content: const Text(
              "Gemini AI Key detected. Do you want to use Gemini AI for superior accuracy?"),
          actions: [
            AccessibleTextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _processGeminiFlow(apiKey);
              },
              child: const Text("Use Gemini AI"),
            ),
            AccessibleTextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _navigateToOcr();
              },
              child: const Text("Use Local OCR"),
            ),
          ],
        ),
      );
    } else {
      _navigateToOcr();
    }
  }

  void _navigateToOcr() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OcrScreen(ttsService: widget.ttsService,
          voiceService: widget.voiceService,),
      ),
    );
  }

  Future<void> _processGeminiFlow(String apiKey) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Processing with Gemini AI...")),
    );

    try {
      final doc = await _geminiService.processImage(image.path, apiKey);
      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaperDetailScreen(
            document: doc,
            ttsService: widget.ttsService,
            voiceService: widget.voiceService,
            timestamp: DateTime.now().toString(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset('assets/images/logo.png', width: 260, height: 160),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedButton(
              icon: Icons.camera_alt,
              label: "Scan Questions",
              onTap: _handleScan,
              // accessibilityService: widget.accessibilityService, // Removed
            ),
            const SizedBox(height: 24),
            AnimatedButton(
              icon: Icons.question_answer,
              label: "Saved Questions",
              // accessibilityService: widget.accessibilityService, // Add to other buttons too
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuestionsScreen(ttsService: widget.ttsService, voiceService: widget.voiceService,),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            AnimatedButton(
              icon: Icons.settings,
              label: "Preferences",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreferencesScreen(ttsService: widget.ttsService,
          voiceService: widget.voiceService,),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------- Animated Button ----------------------
// (Keeping your existing AnimatedButton code below...)

class AnimatedButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  // Removed accessibilityService param as it will use singleton

  const AnimatedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  static const Color buttonColor = Color(0xFF1283B2);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
  }

  void _onTapDown(TapDownDetails details) => _controller.forward();
  void _onTapUp(TapUpDetails details) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: (details) async {
        _onTapUp(details);
        await AccessibilityService().trigger(AccessibilityEvent.action);
        widget.onTap();
      },
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: buttonColor.withOpacity(0.6),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 36),
                    const SizedBox(width: 16),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
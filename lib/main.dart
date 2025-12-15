import 'package:flutter/material.dart';
import 'dart:ui';
import 'services/tts_service.dart';
import 'preferences_screen.dart';
import 'ocr_screen.dart';
import 'questions_screen.dart';
import 'pdf_viewer_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart'; // Added
import 'package:image_picker/image_picker.dart'; // Added
import 'services/gemini_question_service.dart'; // Added
import 'models/question_model.dart'; // Added
import 'paper_detail_screen.dart'; // Added

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final TtsService ttsService = TtsService();

  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LekhAi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(ttsService: ttsService),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------------------- Splash Screen ----------------------

class SplashScreen extends StatefulWidget {
  final TtsService ttsService;
  const SplashScreen({super.key, required this.ttsService});

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
          builder: (_) => HomeScreen(ttsService: widget.ttsService),
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
  const HomeScreen({super.key, required this.ttsService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  static const Color buttonColor = Color(0xFF1283B2);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    widget.ttsService.speak(
      "Welcome to the main screen. Choose 'Take Exam' or 'Read PDF'.",
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfViewerScreen(path: path, ttsService: widget.ttsService),
      ),
    );
  }

  void _openTakeExam() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TakeExamScreen(ttsService: widget.ttsService),
      ),
    );
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
              ),
              const SizedBox(height: 32),

              AnimatedButton(
                icon: Icons.picture_as_pdf,
                label: "Read PDF",
                onTap: _openPdf,
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
  const TakeExamScreen({super.key, required this.ttsService});

  @override
  State<TakeExamScreen> createState() => _TakeExamScreenState();
}

class _TakeExamScreenState extends State<TakeExamScreen> {
  final GeminiQuestionService _geminiService = GeminiQuestionService();

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak("Welcome to Take Exam. Choose an option.");
  }

  Future<void> _handleScan() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');

    if (!mounted) return;

    if (apiKey != null && apiKey.isNotEmpty) {
      // Show choice
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Scan Mode"),
          content: const Text(
              "Gemini API Key detected. Do you want to use Gemini AI for superior accuracy?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _processGeminiFlow(apiKey);
              },
              child: const Text("Use Gemini AI"),
            ),
            TextButton(
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
      // Direct to OCR
      _navigateToOcr();
    }
  }

  void _navigateToOcr() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OcrScreen(ttsService: widget.ttsService),
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
            ),
            const SizedBox(height: 24),

            AnimatedButton(
              icon: Icons.question_answer,
              label: "Saved Questions",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuestionsScreen(ttsService: widget.ttsService),
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
                    builder: (_) => PreferencesScreen(ttsService: widget.ttsService),
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

class AnimatedButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
      onTapUp: (details) {
        _onTapUp(details);
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

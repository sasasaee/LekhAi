import 'package:flutter/material.dart';
import 'services/tts_service.dart';
import 'preferences_screen.dart';
import 'ocr_screen.dart';
import 'questions_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdf_text/flutter_pdf_text.dart';
import 'pdf_viewer_screen.dart';



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
      title: 'LekhAi TTS Demo',
      home: HomeScreen(ttsService: ttsService),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final TtsService ttsService;
  const HomeScreen({super.key, required this.ttsService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TTS Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => widget.ttsService.speak(
                  "আপনার প্রশ্ন এখানে, ধন্যবাদ। আমি চাই আপনি বাংলায় কথা বলুন।"),
              child: const Text('Speak Bangla'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => widget.ttsService.speak(
                  "Your question is here, thank you. I want you to speak in English."),

              child: const Text('Speak English'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () => widget.ttsService.pause(),
                child: const Text('Pause')),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () => widget.ttsService.resume(),
                child: const Text('Resume')),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () => widget.ttsService.stop(),
                child: const Text('Stop')),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PreferencesScreen(ttsService: widget.ttsService)),
                );
              },
              child: const Text('Preferences'),
            ),
            
             ElevatedButton(
              onPressed: () async {
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pdf'],
                );

                if (result == null) {
                  widget.ttsService.speak("No PDF selected.");
                  return;
                }

                String path = result.files.single.path!;
                 // Navigate to the PDF viewer screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfViewerScreen(
                      path: path,
                      ttsService: widget.ttsService,
                    ),
                  ),
                );
              },
              child: const Text('Read PDF'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OcrScreen()),
                );
              },
              child: const Text('Scan Question'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QuestionsScreen()),
                );
              },
              child: const Text('View Saved Questions'),
            ),
          ],
        ),
      ),
    );
  }
}

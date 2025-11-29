import 'package:flutter/material.dart';
import 'services/tts_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("APP STARTED → main() executed");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final TtsService ttsService = TtsService();

  MyApp({super.key}) {
    debugPrint("MyApp → TtsService instance created");
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("MyApp.build() → Building MaterialApp");

    return MaterialApp(
      title: 'LekhAi TTS Demo',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('TTS Demo'),
        ),
        body: Builder(
          builder: (context) {
            debugPrint("Building Home Screen UI");

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        debugPrint("UI → Speak Bangla pressed");
                        ttsService.speak(
                          "আপনার প্রশ্ন এখানে, ধন্যবাদ। আমি চাই আপনি বাংলায় কথা বলুন।",
                        );
                      },
                      child: const Text('Speak Bangla'),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: () {
                        debugPrint("UI → Speak English pressed");
                        ttsService.speak(
                          "Your question is here, thank you. I want you to speak in English.",
                        );
                      },
                      child: const Text('Speak English'),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: () {
                        debugPrint("UI → Pause requested");
                        ttsService.pause();
                      },
                      child: const Text('Pause'),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: () {
                        debugPrint("UI → Resume requested");
                        ttsService.resume();
                      },
                      child: const Text('Resume'),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: () {
                        debugPrint("UI → Stop requested");
                        ttsService.stop();
                      },
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

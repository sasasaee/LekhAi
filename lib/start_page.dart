import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/stt_service.dart';
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';
import 'services/accessibility_service.dart';
import 'main.dart'; // Import main to access HomeScreen if needed or just use named routes if setup

class StartPage extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService accessibilityService;

  const StartPage({
    super.key,
    required this.ttsService,
    required this.voiceService,
    required this.accessibilityService,
  });

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final SttService _sttService = SttService();
  bool _shouldListen = true;

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak(
      "Welcome to LekhAi. Your intelligent study companion. Say Get Started to begin.",
    );
    _initVoiceListener();
  }

  @override
  void dispose() {
    _shouldListen = false;
    _sttService.stopListening();
    super.dispose();
  }

  void _initVoiceListener() async {
    bool available = await _sttService.init(
      tts: widget.ttsService,
      onStatus: (status) {
        if ((status == 'notListening' || status == 'done') && _shouldListen) {
           Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _shouldListen) _startListening();
          });
        }
      },
    );

    if (available) {
      _startListening();
    }
  }

  void _startListening() {
    if (!_shouldListen) return;
    _sttService.startListening(
      localeId: 'en-US',
      onResult: (text) {
        final result = widget.voiceService.parse(text);
        if (result.action == VoiceAction.startApp || 
            text.toLowerCase().contains('get started')) {
          _navigateToHome();
        }
      },
    );
  }

  void _navigateToHome() {
    _shouldListen = false;
    _sttService.stopListening();
    widget.accessibilityService.trigger(AccessibilityEvent.action);
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
              Theme.of(context).primaryColor.withValues(alpha: 0.1),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                // Logo
                Hero(
                      tag: 'app_logo',
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 320, // Increased size
                        height: 320,
                      ),
                    )
                    .animate()
                    .fade(duration: 800.ms)
                    .scale(duration: 800.ms, curve: Curves.easeOutBack),

                const SizedBox(height: 32),

                // Description
                Text(
                  "Your ability defines you, not your limitations.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 22, // Increased font size
                    color: Colors.white, // Brighter color
                    fontWeight: FontWeight.w600, // Bolder
                    height: 1.4,
                  ),
                ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2, end: 0),

                const Spacer(flex: 3),

                // Start Button
                SizedBox(
                      width: double.infinity,
                      height: 68, // Slightly taller
                      child: ElevatedButton(
                        onPressed: _navigateToHome,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          shadowColor: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Get Started",
                              style: TextStyle(
                                fontSize: 24, // Bigger font
                                fontWeight: FontWeight.w800, // Bolder
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.arrow_forward_rounded, size: 28),
                          ],
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 800.ms)
                    .shimmer(delay: 1500.ms, duration: 1500.ms)
                    .slideY(begin: 0.5, end: 0, curve: Curves.easeOutQuad),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

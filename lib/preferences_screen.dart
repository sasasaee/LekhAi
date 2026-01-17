import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';
import 'services/accessibility_service.dart';
import 'widgets/accessible_widgets.dart'; // Added
import 'services/stt_service.dart';

class PreferencesScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService? accessibilityService;

  const PreferencesScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    this.accessibilityService,
  });

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  // Track what the user sees (Human-readable speed)
  double _displaySpeed = 1.0;
  double _volume = 0.7;

  final SttService _sttService = SttService();
  bool _isListening = false;
  bool _voiceCommandsEnabled = true; // Default ON
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    widget.ttsService.speak("Settings");
    _initVoiceCommandListener();
  }

  @override
  void dispose() {
    _sttService.stopListening();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _initVoiceCommandListener() async {
    bool available = await _sttService.init(
      tts: widget.ttsService, // Pass TTS to enable auto-pause
      onStatus: (status) {
        if ((status == 'notListening' || status == 'done') && !_isListening) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isListening) _startCommandStream();
          });
        }
      },
      onError: (error) => print("PreferencesScreen STT Error: $error"),
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
          context: VoiceContext.settings,
        );
        if (result.action != VoiceAction.unknown) {
          widget.voiceService.performGlobalNavigation(result);
        }
      },
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await widget.ttsService.loadPreferences();
    final sp = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // Load the human-readable speed, default to 1.0
        _displaySpeed = (prefs['speed'] as num?)?.toDouble() ?? 1.0;
        _volume = (prefs['volume'] as num?)?.toDouble() ?? 0.7;
        _apiKeyController.text = sp.getString('gemini_api_key') ?? '';

        // Load Haptics
        bool hapticsEnabled = prefs['haptics'] as bool? ?? true;
        AccessibilityService().setEnabled(hapticsEnabled);

        // Load Voice Commands
        _voiceCommandsEnabled = sp.getBool('voice_commands_enabled') ?? true;
      });
      // Ensure engine is synced with mapped value immediately
      await widget.ttsService.setSpeed(_displaySpeed * 0.5);
      await widget.ttsService.setVolume(_volume);
    }
  }

  Future<void> _savePreferences() async {
    // 1. Map display speed to engine speed for the session
    double engineSpeed = _displaySpeed * 0.5;
    await widget.ttsService.setSpeed(engineSpeed);
    await widget.ttsService.setVolume(_volume);

    // 2. Save the display speed (so other screens load 1.0, 1.25, etc.)
    await widget.ttsService.savePreferences(
      speed: _displaySpeed,
      volume: _volume,
    );
    await widget.ttsService.saveHapticPreference(
      AccessibilityService().enabled,
    );

    final sp = await SharedPreferences.getInstance();
    await sp.setString('gemini_api_key', _apiKeyController.text.trim());

    widget.ttsService.speak("Preferences saved successfully.");
    AccessibilityService().trigger(AccessibilityEvent.success);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences saved')));
    }
  }

  void _reset() async {
    setState(() {
      _displaySpeed = 1.0; // Reset to normal human speed
      _volume = 0.7;
      _apiKeyController.clear();
    });

    // Reset TTS engine to internal defaults
    await widget.ttsService.resetPreferences();
    final sp = await SharedPreferences.getInstance();
    await sp.remove('gemini_api_key');

    widget.ttsService.speak("Preferences have been reset.");
    AccessibilityService().trigger(AccessibilityEvent.warning);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Preferences',
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
              children: [
                // API Key Card
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gemini API Key',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKeyController,
                        style: GoogleFonts.outfit(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter your API Key here',
                          hintStyle: GoogleFonts.outfit(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: const Icon(
                            Icons.key,
                            color: Colors.white70,
                          ),
                        ),
                        obscureText: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Speed Card
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Speed: ${_displaySpeed.toStringAsFixed(2)}x',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.play_circle_fill,
                              color: Colors.blueAccent,
                              size: 32,
                            ),
                            onPressed: () => widget.ttsService.speak(
                              "This is a speed test at ${_displaySpeed.toStringAsFixed(2)} speed",
                            ),
                          ),
                        ],
                      ),
                      AccessibleSlider(
                        min: 0.5,
                        max: 1.75,
                        value: _displaySpeed,
                        divisions: 5,
                        onChanged: (v) {
                          setState(() => _displaySpeed = v);
                          widget.ttsService.setSpeed(v * 0.5);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Volume Card
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Volume: ${(_volume * 100).toInt()}%',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.volume_up_rounded,
                              color: Colors.greenAccent,
                              size: 32,
                            ),
                            onPressed: () => widget.ttsService.speak(
                              "This is a volume test",
                            ),
                          ),
                        ],
                      ),
                      AccessibleSlider(
                        min: 0.0,
                        max: 1.0,
                        value: _volume,
                        divisions: 10,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          widget.ttsService.setVolume(v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Haptic Feedback Toggle
                _GlassCard(
                  child: SwitchListTile(
                    value: AccessibilityService().enabled,
                    activeColor: Theme.of(context).primaryColor,
                    title: Text(
                      "Haptic Feedback",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      "Vibrate on interactions",
                      style: GoogleFonts.outfit(color: Colors.white54),
                    ),
                    onChanged: (val) {
                      setState(() {
                        AccessibilityService().setEnabled(val);
                      });
                      if (val)
                        AccessibilityService().trigger(
                          AccessibilityEvent.action,
                        );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Voice Commands Toggle
                _GlassCard(
                  child: SwitchListTile(
                    value: _voiceCommandsEnabled,
                    activeColor: Theme.of(context).primaryColor,
                    title: Text(
                      "Voice Commands",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      "Enable always-on voice control",
                      style: GoogleFonts.outfit(color: Colors.white54),
                    ),
                    onChanged: (val) async {
                      setState(() => _voiceCommandsEnabled = val);

                      // Save immediately for responsiveness
                      final sp = await SharedPreferences.getInstance();
                      await sp.setBool('voice_commands_enabled', val);

                      if (val) {
                        _initVoiceCommandListener();
                        widget.ttsService.speak("Voice commands enabled.");
                      } else {
                        _sttService.stopListening();
                        widget.ttsService.speak("Voice commands disabled.");
                      }
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _savePreferences,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                          shadowColor: Colors.blueAccent.withOpacity(0.4),
                        ),
                        child: Text(
                          'Save',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reset,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(
                            color: Colors.redAccent,
                            width: 2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Reset',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

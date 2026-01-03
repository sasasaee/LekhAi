import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/tts_service.dart';
import 'services/voice_command_service.dart';
import 'services/accessibility_service.dart';
import 'widgets/accessible_widgets.dart'; // Added

class PreferencesScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService? accessibilityService;

  const PreferencesScreen({super.key, required this.ttsService,
    required this.voiceService, this.accessibilityService});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  // Track what the user sees (Human-readable speed)
  double _displaySpeed = 1.0; 
  double _volume = 0.7;

  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    widget.ttsService.speak(
      "Welcome to the Preferences screen. Here you can adjust speed and volume.",
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
    await widget.ttsService.saveHapticPreference(AccessibilityService().enabled);
    
    final sp = await SharedPreferences.getInstance();
    await sp.setString('gemini_api_key', _apiKeyController.text.trim());

    widget.ttsService.speak(
      "Preferences saved successfully.",
    );
    AccessibilityService().trigger(AccessibilityEvent.success);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences saved')),
      );
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
      appBar: AppBar(
        title: const Text('Preferences'),
        leading: AccessibleIconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
            // API Key Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gemini API Key',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        hintText: 'Enter your API Key here',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.key),
                      ),
                      obscureText: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Speed Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Speed: ${_displaySpeed.toStringAsFixed(2)}x',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    AccessibleSlider(
                      min: 0.5,
                      max: 1.75,
                      value: _displaySpeed,
                      divisions: 5, // Creates steps of 0.25 (0.5, 0.75, 1.0, 1.25, 1.5, 1.75)
                      onChanged: (v) {
                        setState(() => _displaySpeed = v);
                        // Real-time engine update with mapping
                        widget.ttsService.setSpeed(v * 0.5);
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AccessibleIconButton(
                        icon: const Icon(Icons.play_arrow),
                        color: Colors.blueAccent,
                        onPressed: () =>
                            widget.ttsService.speak("This is a speed test at ${_displaySpeed.toStringAsFixed(2)} speed"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Volume Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Volume: ${(_volume * 100).toInt()}%',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: AccessibleIconButton(
                        icon: const Icon(Icons.play_arrow),
                        color: Colors.green,
                        onPressed: () =>
                            widget.ttsService.speak("This is a volume test"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Haptic Feedback Toggle
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: AccessibleSwitchListTile(
                 value: AccessibilityService().enabled,
                 title: const Text(
                  "Haptic Feedback",
                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                 ),
                 subtitle: const Text("Vibrate on interactions"),
                 onChanged: (val) {
                   setState(() {
                     AccessibilityService().setEnabled(val);
                   });
                   // Immediate feedback if enabling
                   if (val) AccessibilityService().trigger(AccessibilityEvent.action);
                 },
              ),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: AccessibleElevatedButton(
                    onPressed: _savePreferences,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Save Preferences',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AccessibleElevatedButton(
                    onPressed: _reset,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Reset', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'services/tts_service.dart';

class PreferencesScreen extends StatefulWidget {
  final TtsService ttsService;
  const PreferencesScreen({super.key, required this.ttsService});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  double _speed = 0.5;
  double _volume = 0.7;

  @override
  void initState() {
    super.initState();
    widget.ttsService.loadPreferences().then((prefs) {
      setState(() {
        _speed = prefs['speed']!;
        _volume = prefs['volume']!;
      });
    });
    widget.ttsService.speak(
      "Welcome to the Preferences screen. Here you can adjust TTS speed and volume.",
    );
  }

  void _reset() {
    setState(() {
      _speed = 0.5;
      _volume = 0.7;
    });
    widget.ttsService.resetPreferences();
    widget.ttsService.speak("Preferences have been reset.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                      'Speed: ${_speed.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      min: 0.1,
                      max: 1.0,
                      value: _speed,
                      divisions: 9,
                      onChanged: (v) => setState(() => _speed = v),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        color: Colors.blueAccent,
                        onPressed: () =>
                            widget.ttsService.speak("This is a speed test"),
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
                      'Volume: ${_volume.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      min: 0.0,
                      max: 1.0,
                      value: _volume,
                      divisions: 10,
                      onChanged: (v) => setState(() => _volume = v),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
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
            const SizedBox(height: 32),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.ttsService.setSpeed(_speed);
                      widget.ttsService.setVolume(_volume);
                      widget.ttsService.savePreferences(
                        speed: _speed,
                        volume: _volume,
                      );
                      widget.ttsService.speak(
                        "Preferences saved successfully.",
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.blueAccent,
                    ),
                    child: const Text(
                      'Save Preferences',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _reset,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                    child: const Text('Reset', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    widget.ttsService.speak(
      "Welcome to the Preferences screen. Here you can adjust TTS speed and volume, and set your API key.",
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await widget.ttsService.loadPreferences();
    final sp = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _speed = prefs['speed']!;
        _volume = prefs['volume']!;
        _apiKeyController.text = sp.getString('gemini_api_key') ?? '';
      });
    }
  }

  Future<void> _savePreferences() async {
    widget.ttsService.setSpeed(_speed);
    widget.ttsService.setVolume(_volume);
    await widget.ttsService.savePreferences(
      speed: _speed,
      volume: _volume,
    );
    
    final sp = await SharedPreferences.getInstance();
    await sp.setString('gemini_api_key', _apiKeyController.text.trim());

    widget.ttsService.speak(
      "Preferences and API key saved successfully.",
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences saved')),
      );
    }
  }

  void _reset() async {
    setState(() {
      _speed = 1.0;
      _volume = 0.7;
      _apiKeyController.clear();
    });
    await widget.ttsService.resetPreferences();
    final sp = await SharedPreferences.getInstance();
    await sp.remove('gemini_api_key');
    
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                      'Speed: ${_speed.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      min: 0.1,
                      max: 1.5,
                      value: _speed,
                      divisions: 14,
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
                  child: ElevatedButton(
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

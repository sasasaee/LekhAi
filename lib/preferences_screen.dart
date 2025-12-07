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
  }

  void _reset() {
    setState(() {
      _speed = 0.5;
      _volume = 0.7;
    });
    widget.ttsService.resetPreferences();
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
            Text('Speed: ${_speed.toStringAsFixed(2)}'),
            Slider(
              min: 0.1,
              max: 1.0,
              divisions: 9,
              value: _speed,
              onChanged: (v) => setState(() => _speed = v),
            ),
            const SizedBox(height: 16),
            Text('Volume: ${_volume.toStringAsFixed(2)}'),
            Slider(
              min: 0.0,
              max: 1.0,
              divisions: 10,
              value: _volume,
              onChanged: (v) => setState(() => _volume = v),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () {
                    widget.ttsService.setSpeed(_speed);
                    widget.ttsService.setVolume(_volume);
                    widget.ttsService.savePreferences(speed: _speed, volume: _volume);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Preferences saved!')),
                    );
                  },
                  child: const Text('Save Preferences'),
                ),
                ElevatedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

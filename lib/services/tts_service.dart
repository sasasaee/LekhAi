import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  String? _lastText;
  bool _isPaused = false;

  TtsService() {
    _init();
  }

  void _init() {
    _tts.setVolume(1.0);
    _tts.setSpeechRate(0.5);

    _tts.setStartHandler(() => print("TTS → Speech Started"));
    _tts.setCompletionHandler(() => print("TTS → Speech Completed"));
    _tts.setPauseHandler(() => _isPaused = true);
    _tts.setContinueHandler(() => _isPaused = false);
    _tts.setErrorHandler((msg) => print("TTS ERROR → $msg"));

    _initialized = true;
    loadPreferences(); // auto-load saved prefs
  }

  Future<void> speak(String text) async {
    if (!_initialized) return;
    _lastText = text;
    _isPaused = false;
    await _tts.speak(text);
  }

  Future<void> pause() async {
    _isPaused = true;
    await _tts.pause();
  }

  Future<void> resume() async {
    if (_isPaused && _lastText != null) {
      await speak(_lastText!);
    }
  }

  Future<void> stop() async {
    _isPaused = false;
    await _tts.stop();
  }

  Future<void> setSpeed(double v) => _tts.setSpeechRate(v.clamp(0.1, 1.0));
  Future<void> setVolume(double v) => _tts.setVolume(v.clamp(0.0, 1.0));

  // ---------------- Preferences ----------------
  Future<void> savePreferences({required double speed, required double volume}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speed', speed);
    await prefs.setDouble('volume', volume);
  }

  Future<Map<String, double>> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    double speed = prefs.getDouble('speed') ?? 0.5;
    double volume = prefs.getDouble('volume') ?? 0.7;

    await setSpeed(speed);
    await setVolume(volume);

    return {'speed': speed, 'volume': volume};
  }

  Future<void> resetPreferences() async {
    await savePreferences(speed: 0.5, volume: 0.7);
    await setSpeed(0.5);
    await setVolume(0.7);
  }
}

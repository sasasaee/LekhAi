import 'package:flutter_tts/flutter_tts.dart';

enum TtsLanguage { bangla, english }

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  String? banglaVoice;
  String? englishVoice;

  String? _lastText;       // store last spoken text
  bool _isPaused = false;  // track pause

  TtsLanguage _currentLanguage = TtsLanguage.english;

  TtsService() {
    _init();
  }

  void _init() {
    print("TTS → Initializing engine settings");

    _tts.setVolume(1.0);
    _tts.setPitch(1.0);
    _tts.setSpeechRate(0.5);

    _tts.setStartHandler(() => print("TTS Event → Speech Started"));
    _tts.setCompletionHandler(() => print("TTS Event → Speech Completed"));
    _tts.setPauseHandler(() {
      print("TTS Event → Speech Paused");
      _isPaused = true;
    });
    _tts.setContinueHandler(() => print("TTS Event → Speech Resumed"));
    _tts.setErrorHandler((msg) => print("TTS ERROR → $msg"));

    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      print("TTS → Loading available voices...");

      final voices = await _tts.getVoices;
      print("TTS → Voices loaded");

      for (var v in voices) {
        if (v["locale"] == "bn-BD" || v["locale"] == "bn-IN") {
          banglaVoice = v["name"];
        }
        if (v["locale"] == "en-US") {
          englishVoice = v["name"];
        }
      }

      print("TTS → Bangla voice: $banglaVoice");
      print("TTS → English voice: $englishVoice");

      _initialized = true;

    } catch (e) {
      print("TTS ERROR → Failed to load voices: $e");
    }
  }

  Future<void> setLanguage(TtsLanguage lang) async {
    if (!_initialized) return;

    _currentLanguage = lang;

    if (lang == TtsLanguage.bangla) {
      print("TTS → Switching language to Bangla");
      await _tts.setLanguage("bn-BD");
      if (banglaVoice != null) {
        await _tts.setVoice({"name": banglaVoice!});
      }
    } else {
      print("TTS → Switching language to English");
      await _tts.setLanguage("en-US");
      if (englishVoice != null) {
        await _tts.setVoice({"name": englishVoice!});
      }
    }
  }

  Future<void> speak(String text) async {
    if (!_initialized) {
      print("TTS WARNING → speak() called before initialization");
      return;
    }

    _lastText = text;

    if (RegExp(r'[\u0980-\u09FF]').hasMatch(text)) {
      await setLanguage(TtsLanguage.bangla);
    } else {
      await setLanguage(TtsLanguage.english);
    }

    _isPaused = false;
    print("TTS → Speaking text: $text");

    await _tts.speak(text);
  }

  Future<void> pause() async {
    print("TTS → Pause requested");
    _isPaused = true;
    await _tts.pause();
  }

  Future<void> resume() async {
    if (_isPaused && _lastText != null) {
      print("TTS → Resume triggered (re-speaking last text)");
      await speak(_lastText!);
      _isPaused = false;
    } else {
      print("TTS → Resume ignored (no paused speech)");
    }
  }

  Future<void> stop() async {
    print("TTS → Stop requested");
    _isPaused = false;
    await _tts.stop();
  }

  Future<void> setSpeed(double v) => _tts.setSpeechRate(v.clamp(0.0, 1.0));
  Future<void> setPitch(double v) => _tts.setPitch(v.clamp(0.5, 2.0));
  Future<void> setVolume(double v) => _tts.setVolume(v.clamp(0.0, 1.0));
}

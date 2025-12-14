import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'math_text_processor.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  String? _lastText;
  bool _isPaused = false;
  bool get isPaused => _isPaused; //public getter for the pdf read

  int _currentWordStart = 0;
  int get currentWordStart => _currentWordStart; // Public getter for resume logic
  bool _isSpeaking = false; // Internal flag to know if we are actually speaking to auto-resume

  TtsService() {
    _init();
  }

  VoidCallback? _defaultCompletionHandler;

  void _init() {
    _tts.setVolume(1.0);
    _tts.setSpeechRate(1.0);
    
    _setupHandlers();

    _initialized = true;
    loadPreferences(); 
  }

  void _setupHandlers() {
    _tts.setStartHandler(() {
      print("TTS → Speech Started");
      _isSpeaking = true;
    });

    _defaultCompletionHandler = () {
      print("TTS → Speech Completed");
      _isSpeaking = false;
      _currentWordStart = 0;
    };
    
    _tts.setCompletionHandler(_defaultCompletionHandler!);

    _tts.setProgressHandler((text, start, end, word) {
      _currentWordStart = start;
    });

    _tts.setPauseHandler(() {
      _isPaused = true;
      _isSpeaking = false; 
    });

    _tts.setContinueHandler(() {
      _isPaused = false;
      _isSpeaking = true;
    });
    
    _tts.setCancelHandler(() {
      print("TTS → Speech Cancelled");
      _isSpeaking = false;
      _currentWordStart = 0;
    });
    
    _tts.setErrorHandler((msg) {
      print("TTS ERROR → $msg");
      _isSpeaking = false;
    });
  }

  // Speaks text and waits for completion (sequential)
  Future<void> speakAndWait(String text) async {
    if (!_initialized) return;
    
    await _tts.stop();
    
    final processedText = _preprocessText(text);
    _lastText = processedText;
    _currentWordStart = 0;
    _isPaused = false;

    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      completer.complete();
    });
    
    _tts.setCancelHandler(() {
      if (!completer.isCompleted) completer.complete();
      _isSpeaking = false;
    });

    try {
      await _tts.speak(processedText);
      await completer.future; 
    } finally {
      if (_defaultCompletionHandler != null) {
        _tts.setCompletionHandler(_defaultCompletionHandler!);
      }
      _tts.setCancelHandler(() {
          print("TTS → Speech Cancelled");
          _isSpeaking = false;
          _currentWordStart = 0;
      });
    }
  }

  // Speaks text immediately
  Future<void> speak(String text) async {
    if (!_initialized) return;
    
    await _tts.stop();
    
    final processedText = _preprocessText(text);
    _lastText = processedText;
    _currentWordStart = 0;
    _isPaused = false;
    await _tts.speak(processedText);
  }

  // Prepares text: handles blanks, lists, and math
  String _preprocessText(String text) {
    String out = text;
    
    const pauseToken = "[[PAUSE]]"; 

    // 1. Handle "Blank with Item" i.e. (a) —, — (a), (a) -, (a) ____
    
    // Case A: (a) followed by dash
    out = out.replaceAllMapped(
      RegExp(r'(\([a-zA-Z0-9]+\))\s*([—–_\-]+)'), 
      (match) {
          final rawMarker = match.group(1)!; 
          final markerContent = rawMarker.replaceAll(RegExp(r'[()]'), '');
          return ' $pauseToken blank $markerContent $pauseToken '; 
      }
    );

    // Case B: Dash followed by (a)
    out = out.replaceAllMapped(
      RegExp(r'([—–_\-]+)\s*(\([a-zA-Z0-9]+\))'), 
      (match) {
          final rawMarker = match.group(2)!; 
          final markerContent = rawMarker.replaceAll(RegExp(r'[()]'), '');
          return ' $pauseToken blank $markerContent $pauseToken '; 
      }
    );

    // 2. Handle remaining List Items (a)
    out = out.replaceAllMapped(
      RegExp(r'\(([a-zA-Z0-9]+)\)'), 
      (match) => ' $pauseToken ${match.group(1)} $pauseToken '
    );

    // 3. Handle remaining standalone blanks
    out = out.replaceAll(RegExp(r'([_\-.]{2,}|[—–]+)'), ' $pauseToken blank $pauseToken ');

    // 4. Vertical bars
    out = out.replaceAll('|', ',');
    
    // 5. Finalize: Replace placeholder with actual pause
    out = out.replaceAll(pauseToken, '...');
    
    if (MathTextProcessor.isMathLine(out)) {
       out = MathTextProcessor.prepareForSpeech(out);
    }

    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> pause() async {
    _isPaused = true;
    await _tts.pause();
  }

  Future<void> resume() async {
    if (_isPaused && _lastText != null) {
      // If we have progress, resume from there
      String textToSpeak = _lastText!;
      if (_currentWordStart > 0 && _currentWordStart < textToSpeak.length) {
        textToSpeak = textToSpeak.substring(_currentWordStart);
      }
      await _tts.speak(textToSpeak);
    }
  }

  Future<void> stop() async {
    _isPaused = false;
    await _tts.stop();
  }

  Future<void> setSpeed(double v) async {
    await _tts.setSpeechRate(v.clamp(0.1, 1.5));
  }
  Future<void> setVolume(double v) => _tts.setVolume(v.clamp(0.0, 1.0));

  // ---------------- Preferences ----------------
  Future<void> savePreferences({
    required double speed,
    required double volume,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speed', speed);
    await prefs.setDouble('volume', volume);
  }

  Future<Map<String, double>> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    double speed = prefs.getDouble('speed') ?? 1.0;
    double volume = prefs.getDouble('volume') ?? 0.7;

    await setSpeed(speed);
    await setVolume(volume);

    return {'speed': speed, 'volume': volume};
  }

  Future<void> resetPreferences() async {
    await savePreferences(speed: 1.0, volume: 0.7);
    await setSpeed(1.0);
    await setVolume(0.7);
  }
}

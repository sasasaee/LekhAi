import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

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
    loadPreferences(); // auto-load saved prefs
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

  Future<void> speakAndWait(String text) async {
    if (!_initialized) return;
    
    // Stop any ongoing speech first to prevent carryover
    await _tts.stop();
    
    final processedText = _preprocessText(text);
    _lastText = processedText;
    _currentWordStart = 0;
    _isPaused = false;

    final completer = Completer<void>();

    // Set a temporary completion handler that completes the future
    _tts.setCompletionHandler(() {
      completer.complete();
    });
    
    // Also complete on cancel
    _tts.setCancelHandler(() {
      if (!completer.isCompleted) completer.complete();
      _isSpeaking = false;
    });

    try {
      await _tts.speak(processedText);
      await completer.future; // Wait until TTS finishes
    } finally {
      // Restore default handlers
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

  Future<void> speak(String text) async {
    if (!_initialized) return;
    
    // Stop any ongoing speech first (defensive)
    await _tts.stop();
    
    final processedText = _preprocessText(text);
    _lastText = processedText;
    _currentWordStart = 0;
    _isPaused = false;
    await _tts.speak(processedText);
  }

  String _preprocessText(String text) {
    String out = text;
    
    // Placeholder for pause to avoid regex collision with dots/dashes
    const pauseToken = "[[PAUSE]]"; 

    // 1. Handle "Blank with Item" i.e. (a) —, — (a), (a) -, (a) ____
    //    We replace BOTH the marker and the dash with "pause blank char pause"
    
    // Case A: (a) followed by dash
    out = out.replaceAllMapped(
      RegExp(r'(\([a-zA-Z0-9]+\))\s*([—–_\-]+)'), 
      (match) {
          final rawMarker = match.group(1)!; // (a)
          final markerContent = rawMarker.replaceAll(RegExp(r'[()]'), '');
          return ' $pauseToken blank $markerContent $pauseToken '; 
      }
    );

    // Case B: Dash followed by (a)
    out = out.replaceAllMapped(
      RegExp(r'([—–_\-]+)\s*(\([a-zA-Z0-9]+\))'), 
      (match) {
          final rawMarker = match.group(2)!; // (a)
          final markerContent = rawMarker.replaceAll(RegExp(r'[()]'), '');
          return ' $pauseToken blank $markerContent $pauseToken '; 
      }
    );

    // 2. Handle remaining List Items (a) that were NOT consumed by above
    //    Replace (a) with "pause a pause"
    out = out.replaceAllMapped(
      RegExp(r'\(([a-zA-Z0-9]+)\)'), 
      (match) => ' $pauseToken ${match.group(1)} $pauseToken '
    );

    // 3. Handle remaining standalone blanks (____ or —)
    //    Matches 2 or more underscores/dots, OR single/multiple em/en dashes
    out = out.replaceAll(RegExp(r'([_\-.]{2,}|[—–]+)'), ' $pauseToken blank $pauseToken ');

    // 4. Vertical bars
    out = out.replaceAll('|', ',');
    
    // 5. Finalize: Replace placeholder with actual pause (using ellipses for pause)
    out = out.replaceAll(pauseToken, '...');

    // 6. Cleanup
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
    // This stop should trigger cancel handler which resets _isSpeaking
    await _tts.stop();
  }

  Future<void> setSpeed(double v) async {
    await _tts.setSpeechRate(v.clamp(0.1, 1.5));
    // Auto-restart logic removed to let UI handle state
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

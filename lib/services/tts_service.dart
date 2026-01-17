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
  int get currentWordStart =>
      _currentWordStart; // Public getter for resume logic
  bool _isSpeaking =
      false; // Internal flag to know if we are actually speaking to auto-resume
  bool get isSpeaking => _isSpeaking;

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

  // Broadcasts true when speaking, false when stopped/paused
  final StreamController<bool> _speakingController =
      StreamController<bool>.broadcast();
  Stream<bool> get speakingStream => _speakingController.stream;

  void _setupHandlers() {
    _tts.setStartHandler(() {
      print("TTS → setStartHandler callback fired");
      _isSpeaking = true;
      _speakingController.add(true);
    });

    _defaultCompletionHandler = () {
      print("TTS → setCompletionHandler callback fired");
      _isSpeaking = false;
      _currentWordStart = 0;
      print("TTS → Broadcasting speakingStream: FALSE");
      _speakingController.add(false);
    };

    _tts.setCompletionHandler(_defaultCompletionHandler!);

    _tts.setProgressHandler((text, start, end, word) {
      _currentWordStart = start;
    });

    _tts.setPauseHandler(() {
      print("TTS → setPauseHandler callback fired");
      _isPaused = true;
      _isSpeaking = false;
      _speakingController.add(false);
    });

    _tts.setContinueHandler(() {
      print("TTS → setContinueHandler callback fired");
      _isPaused = false;
      _isSpeaking = true;
      _speakingController.add(true);
    });

    _tts.setCancelHandler(() {
      print("TTS → setCancelHandler callback fired");
      _isSpeaking = false;
      _currentWordStart = 0;
      _speakingController.add(false);
    });

    _tts.setErrorHandler((msg) {
      print("TTS → setErrorHandler callback fired: $msg");
      _isSpeaking = false;
      _speakingController.add(false);
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

    print(
      "TTS → speak() called with: '${text.substring(0, text.length > 50 ? 50 : text.length)}...'",
    );

    // CRITICAL: Broadcast speaking=true IMMEDIATELY to prevent STT restart race condition
    // The setStartHandler might fire later, but STT needs to know NOW that we're about to speak
    print("TTS → Broadcasting speakingStream: TRUE (pre-speak)");
    _speakingController.add(true);
    _isSpeaking = true;
    print("TTS → _isSpeaking set to true");

    // Stop any current speech - this ends the previous utterance
    // Broadcast FALSE to signal the previous speech has stopped
    if (_isSpeaking) {
      print(
        "TTS → Stopping previous speech, broadcasting speakingStream: FALSE",
      );
      await _tts.stop();
      _speakingController.add(false);
      await Future.delayed(const Duration(milliseconds: 100)); // Brief pause
    } else {
      await _tts.stop();
    }
    print("TTS → Stopped previous speech");

    // Now broadcast TRUE again for the NEW speech
    print("TTS → Broadcasting speakingStream: TRUE (for new speech)");
    _speakingController.add(true);
    _isSpeaking = true;

    final processedText = _preprocessText(text);
    _lastText = processedText;
    _currentWordStart = 0;
    _isPaused = false;

    print("TTS → About to call platform speak()");
    await _tts.speak(processedText);
    print("TTS → Platform speak() returned (but may still be speaking)");

    // FALLBACK: Estimate speech duration and broadcast FALSE after completion
    // This ensures STT resumes even if no follow-up speech occurs
    // Rough estimate: ~150ms per word (at default speed)
    final wordCount = processedText.split(' ').length;
    final estimatedDurationMs = (wordCount * 150) + 500; // Add 500ms buffer

    print("TTS → Setting fallback timer for ${estimatedDurationMs}ms");
    Future.delayed(Duration(milliseconds: estimatedDurationMs), () {
      if (_isSpeaking) {
        print("TTS → Fallback timer fired. Broadcasting speakingStream: FALSE");
        _isSpeaking = false;
        _speakingController.add(false);
      }
    });
  }

  // Prepares text: handles blanks, lists, and math
  String _preprocessText(String text) {
    String out = text;

    const pauseToken = "[[PAUSE]]";

    // 1. Handle "Blank with Item" i.e. (a) —, — (a), (a) -, (a) ____

    // Case A: (a) followed by dash
    out = out.replaceAllMapped(RegExp(r'(\([a-zA-Z0-9]+\))\s*([—–_\-]+)'), (
      match,
    ) {
      final rawMarker = match.group(1)!;
      final markerContent = rawMarker.replaceAll(RegExp(r'[()]'), '');
      return ' $pauseToken blank $markerContent $pauseToken ';
    });

    // Case B: Dash followed by (a)
    out = out.replaceAllMapped(RegExp(r'([—–_\-]+)\s*(\([a-zA-Z0-9]+\))'), (
      match,
    ) {
      final rawMarker = match.group(2)!;
      final markerContent = rawMarker.replaceAll(RegExp(r'[()]'), '');
      return ' $pauseToken blank $markerContent $pauseToken ';
    });

    // 2. Handle remaining List Items (a)
    out = out.replaceAllMapped(
      RegExp(r'\(([a-zA-Z0-9]+)\)'),
      (match) => ' $pauseToken ${match.group(1)} $pauseToken ',
    );

    // 3. Handle remaining standalone blanks
    out = out.replaceAll(
      RegExp(r'([_\-.]{2,}|[—–]+)'),
      ' $pauseToken blank $pauseToken ',
    );

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
    await _tts.setSpeechRate(v.clamp(0.1, 2.0));
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

  Future<void> saveHapticPreference(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('haptics', enabled);
  }

  Future<Map<String, dynamic>> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    double speed = prefs.getDouble('speed') ?? 1.0;
    double volume = prefs.getDouble('volume') ?? 0.7;

    await setSpeed(speed * 0.5); // Apply scaling to match UI
    await setVolume(volume);

    return {
      'speed': speed,
      'volume': volume,
      'haptics': prefs.getBool('haptics') ?? true,
    };
  }

  Future<void> resetPreferences() async {
    await savePreferences(speed: 1.0, volume: 0.7);
    await saveHapticPreference(true); // Default ON
    await setSpeed(1.0 * 0.5); // Apply scaling to match UI
    await setVolume(0.7);
  }
}

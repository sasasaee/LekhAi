import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';

enum SttIntendedState {
  stopped, // We WANT to be stopped
  listening, // We WANT to be listening
}

class SttService with WidgetsBindingObserver {
  late final stt.SpeechToText _speech;

  // ---------------- STATE MACHINE ----------------
  SttIntendedState _intendedStateValue = SttIntendedState.stopped;
  SttIntendedState get _intendedState => _intendedStateValue;
  set _intendedState(SttIntendedState value) {
    if (_intendedStateValue != value) {
      debugPrint(
        "STT: State changing $_intendedStateValue -> $value. Stack: ${StackTrace.current}",
      );
      _intendedStateValue = value;
    }
  }

  bool _pausedByTts = false;
  bool _pausedByLifecycle = false; // New flag for app background state

  // ---------------- CALLBACKS ----------------
  Function(String)? onStatusChange;
  Function(String)? onError;
  Function(String)? _savedOnResult;
  String? _savedLocaleId;

  // ---------------- INTERNAL FLAGS ----------------
  bool _isAvailable = false;
  bool _voiceEnabled = true;

  bool get isAvailable => _isAvailable;
  bool get isListening => _speech.isListening;
  bool get isActive => _intendedState == SttIntendedState.listening;

  // ---------------- LOOP CONTROL ----------------
  Timer? _loopTimer;
  Timer? _watchdogTimer; // New internal watchdog
  bool _didErrorOccur = false; // Prevents "done" from overriding error backoff

  // ---------------- TTS SUBSCRIPTION ----------------
  StreamSubscription<bool>? _ttsSubscription;

  static final SttService _instance = SttService._internal();

  factory SttService() {
    return _instance;
  }

  SttService._internal() {
    _speech = stt.SpeechToText();
    WidgetsBinding.instance.addObserver(this); // Register observer
  }

  // =================================================
  // INITIALIZATION
  // =================================================

  Future<bool> init({
    Function(String)? onStatus,
    Function(String)? onError,
    dynamic tts, // dynamic to avoid circular dependency
  }) async {
    onStatusChange = onStatus;
    this.onError = onError;

    await _loadSettings();

    // -------- TTS ↔ STT Coordination --------
    if (tts != null) {
      try {
        _ttsSubscription = (tts as dynamic).speakingStream.listen((
          bool isSpeaking,
        ) {

          if (isSpeaking) {
            _pausedByTts = true;
            if (_speech.isListening) {
              debugPrint("STT: Pausing due to TTS");
              _speech.stop();
            }
          } else {
            _pausedByTts = false;
            // Only resume if we are supposed to be listening
            if (_intendedState == SttIntendedState.listening) {
              _kickLoop(delay: 200);
            }
          }
        });
      } catch (e) {
        debugPrint("STT: Failed to bind TTS stream: $e");
      }
    }

    // -------- STT ENGINE INIT --------
    // Only initialize if not already available or if we want to force re-init
    // But speech_to_text initialize is usually safe to call repeatedly.
    // However, updating callbacks is crucial.
    
    // We strictly need to re-initialize to bind the new onStatus/onError callbacks 
    // to the speech instance if the plugin doesn't support hot-swapping callbacks easily.
    // Actually, initialize() accepts the callbacks. So calling it again updates them.
    
    try {
      _isAvailable = await _speech.initialize(
        debugLogging: true,
        onStatus: _handleStatus,
        onError: _handleError,
      );
    } catch (e) {
      debugPrint("STT: Init error (might be already initialized): $e");
      // Fallback: If error, maybe we are still good?
      // But typically we want _isAvailable to reflect true status.
    }

    debugPrint("STT: Init result: $_isAvailable");
    return _isAvailable;
  }

  // =================================================
  // PUBLIC API
  // =================================================

  Future<void> startListening({
    required Function(String) onResult,
    required String localeId,
  }) async {
    debugPrint("STT: Intended state → LISTENING");

    _savedOnResult = onResult;
    _savedLocaleId = localeId;
    _intendedState = SttIntendedState.listening;

    _kickLoop(delay: 0);
    _startWatchdog();
  }

  Future<void> stopListening() async {
    debugPrint(
      "STT: Intended state → STOPPED. CallerStack: ${StackTrace.current}",
    );

    _intendedState = SttIntendedState.stopped;
    _loopTimer?.cancel();
    _loopTimer = null;
    _stopWatchdog();

    if (_speech.isListening) {
      await _speech.stop();
    }

    await FlutterVolumeController.updateShowSystemUI(true);
    // Restore partial volume (optional, or rely on system UI restore)
    // Setting back to 0.5 or similar might be safer if we knew previous level
    // For now, let's just assume user manages volume, but we must unmute essentially
    // But FlutterVolumeController setVolume(0) actually changes the volume level, not just mute.
    // So we should ideally restore it. A safe reset is:
    await FlutterVolumeController.setVolume(
      0.5,
      stream: AudioStream.system,
    ); // Default-ish
    await FlutterVolumeController.setVolume(
      0.5,
      stream: AudioStream.notification,
    );
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Unregister
    _ttsSubscription?.cancel();
    stopListening();
  }

  // =================================================
  // LIFECYCLE HANDLER
  // =================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("STT: Lifecycle state changed to $state");
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App going to background (or picker opening) -> Pause STT
      _pausedByLifecycle = true;
      if (_speech.isListening) {
        _speech.stop();
      }
    } else if (state == AppLifecycleState.resumed) {
      // App coming back -> Resume if intended
      _pausedByLifecycle = false;
      if (_intendedState == SttIntendedState.listening) {
        _kickLoop(delay: 500);
      }
    }
  }

  // =================================================
  // CORE LOOP
  // =================================================

  void _kickLoop({int delay = 0}) {
    _loopTimer?.cancel();
    _loopTimer = Timer(Duration(milliseconds: delay), _evaluateAndRun);
  }

  // Mutex to prevent overlapping start attempts
  bool _isProcessActive = false;

  Future<void> _evaluateAndRun() async {
    // 1. Mutex Check: Don't run if already running
    if (_isProcessActive) {
      debugPrint("STT: Loop skipped - Process is active.");
      return;
    }
    _isProcessActive = true;

    try {
      // ---------- STATE CHECK ----------
      if (_intendedState != SttIntendedState.listening) {
        debugPrint("STT: Loop skipped - Intended state is $_intendedState.");
        return;
      }

      if (_pausedByTts || _pausedByLifecycle) {
        // If paused by TTS or App Lifecycle (background), verify again later
        debugPrint(
          "STT: Loop skipped - Paused by TTS($_pausedByTts) or Lifecycle($_pausedByLifecycle).",
        );
        _kickLoop(delay: 500);
        return;
      }

      // Check active status right before listening
      if (_speech.isListening) {
        debugPrint("STT: Loop skipped - Already listening.");
        return;
      }
      if (!_isAvailable) {
        debugPrint("STT: Loop skipped - Not available.");
        return;
      }

      if (!_voiceEnabled) {
        debugPrint("STT: Voice disabled via settings");
        _intendedState = SttIntendedState.stopped;
        return;
      }

      // ---------- START ENGINE ----------
      debugPrint("STT: Starting engine...");
      _didErrorOccur = false;

      // CRITICAL: Always forcing a stop ensures native layer is clean.
      // Even if isListening is false, native can be 'busy'.
      await _speech.stop();

      await _speech.listen(
        localeId: _savedLocaleId ?? 'en-US',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          partialResults: false,
        ),
        onResult: (SpeechRecognitionResult result) {
          debugPrint(">>> STT HEARD: '${result.recognizedWords}'");
          if (_intendedState != SttIntendedState.listening) return;
          _savedOnResult?.call(result.recognizedWords);
        },
      );
    } catch (e) {
      debugPrint("STT: Engine start exception: $e");
      _didErrorOccur = true;

      if (e.toString().contains('error_busy') ||
          e.toString().contains('busy')) {
        debugPrint("STT: Busy -> Force canceling and waiting.");
        _speech.cancel(); // Force reset
        _kickLoop(delay: 2000);
      } else {
        _kickLoop(delay: 2000);
      }
    } finally {
      // Release mutex
      _isProcessActive = false;
    }
  }

  // =================================================
  // ENGINE CALLBACKS
  // =================================================

  void _handleStatus(String status) {
    debugPrint("STT status: $status");
    onStatusChange?.call(status);

    if ((status == 'done' || status == 'notListening') &&
        _intendedState == SttIntendedState.listening &&
        !_pausedByTts) {
      // CRITICAL FIX: Only fast-restart if NO error occurred.
      // If an error happened, _handleError has already scheduled a backoff restart.
      if (!_didErrorOccur) {
        _kickLoop(delay: 100);
      } else {
        debugPrint(
          "STT: Status 'done' received after error. Respecting error backoff.",
        );
      }
    }
  }

  void _handleError(SpeechRecognitionError error) {
    debugPrint("STT error: ${error.errorMsg}");
    final msg = error.errorMsg.toLowerCase();

    _didErrorOccur = true; // Mark error so 'done' doesn't interfere

    // SUPPRESS BENIGN ERRORS from the UI
    if (!msg.contains('no_match') &&
        !msg.contains('speech_timeout') &&
        !msg.contains('busy') &&
        !msg.contains('client')) {
      onError?.call(error.errorMsg);
    } else {
      debugPrint("STT: Suppressed error '$msg'");
    }

    // RESTART STRATEGY
    int retryDelay = 1000;

    if (msg.contains('busy') || msg.contains('client')) {
      // Critical error: The engine might be stuck.
      // 'stop()' might not be enough. Use 'cancel()' to force native teardown.
      debugPrint(
        "STT: Critical error '$msg' -> performing hard reset (cancel).",
      );
      _speech.cancel();
      retryDelay = 2000;
    } else if (msg.contains('no_match') || msg.contains('speech_timeout')) {
      // Silence. Restart fast-ish (but not instant).
      retryDelay = 500;
    }

    _kickLoop(delay: retryDelay);
  }

  // =================================================
  // SETTINGS
  // =================================================

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _voiceEnabled = prefs.getBool('voice_commands_enabled') ?? true;
  }

  /// Call this when settings change
  Future<void> refreshSettings() async {
    await _loadSettings();
  }

  // =================================================
  // INTERNAL WATCHDOG
  // =================================================

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    // Check every 2 seconds if we should be listening but aren't
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_intendedState == SttIntendedState.listening &&
          !_speech.isListening &&
          !_isProcessActive && // Don't interfere if we are currently starting
          !_pausedByTts &&
          !_pausedByLifecycle) {
        debugPrint("STT Watchdog: Service seems dead. Kicking loop...");
        _kickLoop(delay: 0);
      }
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }
}

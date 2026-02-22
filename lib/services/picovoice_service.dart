import 'package:porcupine_flutter/porcupine_manager.dart';
import 'dart:async';
import 'package:porcupine_flutter/porcupine_error.dart';
// import 'package:porcupine_flutter/porcupine.dart';
import 'package:rhino_flutter/rhino_manager.dart';
import 'package:rhino_flutter/rhino_error.dart';
import 'package:rhino_flutter/rhino.dart'; // Added for RhinoInference type
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'voice_command_service.dart';
import 'accessibility_service.dart';
import 'tts_service.dart';
import 'package:permission_handler/permission_handler.dart';

enum PicovoiceState {
  idle, // Waiting for Wake Word (Porcupine running)
  wakeDetected, // Wake word heard (switching)
  commandListening, // Listening for Intent (Rhino running)
  processing, // Processing Intent (Rhino done)
  ttsSpeaking, // Paused due to TTS
  error, // Initialization or runtime error
  disabled, // Manually disabled
}

class PicovoiceService {
  static final PicovoiceService _instance = PicovoiceService._internal();

  factory PicovoiceService() => _instance;

  PorcupineManager? _porcupineManager;
  RhinoManager? _rhinoManager;

  final TtsService _tts = TtsService();
  final AccessibilityService _accessibility = AccessibilityService();
  VoiceCommandService? _voiceCommandService;

  StreamSubscription<bool>? _ttsSubscription;

  // State
  final ValueNotifier<PicovoiceState> stateNotifier = ValueNotifier(
    PicovoiceState.idle,
  );
  final ValueNotifier<String?> errorNotifier = ValueNotifier(
    null,
  ); // Added for detailed errors

  // Configuration
  String? _accessKey = "Access key Here";

  // Default models placeholders
  final String _keywordPath =
      "assets/picovoice/Hey-lek-ai_en_android_v4_0_0.ppn";
  final String _contextPath =
      "assets/picovoice/lekhai_commands_en_android_v4_0_0.rhn";

  bool _isInitialized = false;
  bool _isEnabled = true; // Default to true
  bool _isStarting = false; // Prevention latch for concurrent starts
  bool _isPorcupineRunning = false; // Internal tracking of Porcupine engine state

  PicovoiceService._internal();

  /// Initialize the service.
  /// Needs [voiceCommandService] to execute intents.
  Future<void> init(VoiceCommandService voiceService) async {
    _voiceCommandService = voiceService;
    await _loadSettings();

    // Subscribe to TTS to handle collisions
    _ttsSubscription?.cancel();
    _ttsSubscription = _tts.speakingStream.listen((isSpeaking) {
      debugPrint("Picovoice: TTS speakingStream received: $isSpeaking");
      if (isSpeaking) {
        _pauseForTts();
      } else {
        _resumeFromTts();
      }
    });

    // Check Microphone Permission
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      debugPrint("Picovoice: Requesting Microphone permission...");
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint("Picovoice: Microphone permission DENIED.");
        errorNotifier.value =
            "Microphone permission denied. Voice commands disabled.";
        stateNotifier.value = PicovoiceState.error;
        return;
      }
    }

    if (_accessKey != null && _accessKey!.isNotEmpty) {
      if (_isEnabled) {
        debugPrint("Picovoice: Initializing engines from init()...");
        await _initEngines();
      } else {
        debugPrint("Picovoice: Voice commands disabled in preferences.");
        stateNotifier.value = PicovoiceState.disabled;
      }
    } else {
      debugPrint("Picovoice: No AccessKey found in init(). State -> Error.");
      errorNotifier.value =
          "Picovoice AccessKey is missing. Please set it in Preferences.";
      stateNotifier.value = PicovoiceState.error;
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString('picovoice_access_key');
    if (storedKey != null && storedKey.isNotEmpty) {
      _accessKey = storedKey;
    }
    // Check if voice commands are enabled
    _isEnabled = prefs.getBool('voice_commands_enabled') ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    if (enabled) {
      if (_accessKey != null && !_isInitialized) {
        await _initEngines();
      } else if (_isInitialized) {
        // Already initialized, maybe just ensure Porcupine is running?
        // Assuming it's idle.
      }
    } else {
      await _stopEngines();
      stateNotifier.value = PicovoiceState.disabled;
    }
  }

  Future<void> updateAccessKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('picovoice_access_key', key);
    _accessKey = key;
    // Restart engines with new key
    errorNotifier.value = null; // Clear old error
    await _stopEngines();
    await _initEngines();
  }

  Future<void> _initEngines() async {
    debugPrint("Picovoice: Using AccessKey: ${_accessKey?.substring(0, 5)}...");

    if (_isPorcupineRunning) {
      debugPrint("Picovoice: Engines already running. Stopping before re-init.");
      await _stopEngines();
    }

    try {
      // Extract assets to local file system
      final keywordPath = await _extractAsset(_keywordPath);
      final contextPath = await _extractAsset(_contextPath);

      // If extraction returned the original path, it means it failed but we caught it.
      // But Picovoice can't use 'assets/...' paths directly on Android.
      if (keywordPath == _keywordPath || contextPath == _contextPath) {
        throw Exception(
          "Failed to prepare local model files. Check logs for details.",
        );
      }

      debugPrint("Picovoice: Local Keyword path: $keywordPath");
      debugPrint("Picovoice: Local Context path: $contextPath");

      // Initialize Porcupine (Wake Word)
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _accessKey!,
        [keywordPath],
        _wakeWordCallback,
        errorCallback: _errorCallback,
      );
      _isPorcupineRunning = true; // fromKeywordPaths automatically starts the engines
      debugPrint("Picovoice: Porcupine engine started.");

      // Initialize Rhino (Speech-to-Intent)
      _rhinoManager = await RhinoManager.create(
        _accessKey!,
        contextPath,
        _inferenceCallback,
        sensitivity:
            0.7, // Increased sensitivity for better short phrase recognition
        processErrorCallback: _errorCallback,
      );

      _isInitialized = true;
      stateNotifier.value = PicovoiceState.idle;
      debugPrint("Picovoice: Engines initialized. State -> Idle.");
      debugPrint(
        "Picovoice: Listening for Wake Word ONLY (Filename: ${keywordPath.split('/').last})",
      );
    } on PorcupineException catch (e) {
      debugPrint("Picovoice: Porcupine Init Error: ${e.message}");
      errorNotifier.value = e.message;
      stateNotifier.value = PicovoiceState.error;
    } on RhinoException catch (e) {
      debugPrint("Picovoice: Rhino Init Error: ${e.message}");
      errorNotifier.value = e.message;
      stateNotifier.value = PicovoiceState.error;
    } catch (e) {
      debugPrint("Picovoice: General Error: $e");
      errorNotifier.value = e.toString();
      stateNotifier.value = PicovoiceState.error;
    }
  }

  Future<void> _stopEngines() async {
    try {
      if (_isPorcupineRunning) {
        debugPrint("Picovoice: Stopping Porcupine...");
        await _porcupineManager?.stop();
        _isPorcupineRunning = false;
      }
      await _porcupineManager?.delete();
      await _rhinoManager?.delete();
      _porcupineManager = null;
      _rhinoManager = null;
    } catch (e) {
      debugPrint("Picovoice: Error stopping engines: $e");
    }
    _isInitialized = false;
  }

  // --- Callbacks ---

  Future<void> _wakeWordCallback(int keywordIndex) async {
    debugPrint("Picovoice: Wake Word Detected!");

    // 1. Update State
    stateNotifier.value = PicovoiceState.wakeDetected;
    _accessibility.trigger(AccessibilityEvent.action);

    // 2. Switch to Rhino
    try {
      await _porcupineManager?.stop();
      _isPorcupineRunning = false;
      stateNotifier.value = PicovoiceState.commandListening;
      debugPrint("Picovoice: Listening for command...");
      await _rhinoManager?.process();
    } catch (e) {
      debugPrint("Picovoice: Error switching to Rhino: $e");
      // Try to recover
      stateNotifier.value = PicovoiceState.error; // Changed from idle to error for better visibility
      // Attempt to restart Porcupine if it's not running
      if (!_isPorcupineRunning) {
        try {
          await _porcupineManager?.start();
          _isPorcupineRunning = true;
          stateNotifier.value = PicovoiceState.idle;
          debugPrint("Picovoice: Porcupine restarted after Rhino switch error.");
        } catch (restartError) {
          debugPrint("Picovoice: Error restarting Porcupine after Rhino switch error: $restartError");
          errorNotifier.value = "Failed to recover after Rhino switch error.";
        }
      }
    }
  }

  Future<void> _inferenceCallback(RhinoInference inference) async {
    final bool isUnderstood = inference.isUnderstood ?? false;
    debugPrint(
      "Picovoice: Inference Result -> Understood: $isUnderstood, Intent: ${inference.intent}",
    );

    if (isUnderstood) {
      stateNotifier.value = PicovoiceState.processing;

      final String? intent = inference.intent;
      final Map<String, String>? slots = inference.slots;

      // Delegate to VoiceCommandService for execution
      if (_voiceCommandService != null && intent != null) {
        _voiceCommandService!.executeIntent(intent, slots);
      }

      _accessibility.trigger(AccessibilityEvent.success);
    } else {
      // Not understood
      _accessibility.trigger(AccessibilityEvent.error);
    }

    // Check for Handoff Triggers (Intents that require microphone for other tasks)
    if (isUnderstood && inference.intent == 'formControl') {
      debugPrint(
        "Picovoice: Handoff Trigger detected (${inference.intent}). Pausing Porcupine for dictation.",
      );
      stateNotifier.value =
          PicovoiceState.processing; // or a new state like 'pausedForDictation'
      // DO NOT RESTART PORCUPINE HERE
    } else {
      // --- ROBUST STATE PROTECTION ---
      // If executeIntent triggered speech, state might already be ttsSpeaking.
      // Do NOT overwrite it to idle, otherwise _resumeFromTts will never fire.
      if (_tts.isSpeaking) {
        debugPrint(
          "Picovoice: Inference done but TTS is speaking. Switching to ttsSpeaking state.",
        );
        stateNotifier.value = PicovoiceState.ttsSpeaking;
        // The TTS listener will handle porcupine restarting.
        return;
      }

      // Return to Idle (Wake Word Listening)
      stateNotifier.value = PicovoiceState.idle;
      try {
        if (!_isPorcupineRunning) {
          debugPrint("Picovoice: Restarting Porcupine after inference.");
          await _porcupineManager?.start();
          _isPorcupineRunning = true;
        }
      } catch (e) {
        debugPrint("Picovoice: Error restarting Porcupine: $e");
        stateNotifier.value = PicovoiceState.error;
      }
    }
  }

  /// Call this when the external dictation/task is finished to resume listening.
  Future<void> resumeListening() async {
    if (!_isInitialized || !_isEnabled || _isStarting) return;

    if (_tts.isSpeaking) {
      debugPrint(
        "Picovoice: resumeListening called but TTS is speaking. Setting state to ttsSpeaking and waiting.",
      );
      stateNotifier.value = PicovoiceState.ttsSpeaking;
      // Porcupine should already be stopped via the speakingStream listener
      return;
    }

    debugPrint("Picovoice: Resuming listening after handoff.");
    stateNotifier.value = PicovoiceState.idle;
    _isStarting = true;
    try {
      if (!_isPorcupineRunning) {
        await _porcupineManager?.start();
        _isPorcupineRunning = true;
        debugPrint("Picovoice: Porcupine resumed.");
      } else {
        debugPrint("Picovoice: Porcupine already running.");
      }
    } catch (e) {
      debugPrint("Picovoice: Error resuming Porcupine: $e");
      stateNotifier.value = PicovoiceState.error;
    } finally {
      _isStarting = false;
    }
  }

  void _errorCallback(dynamic error) {
    debugPrint("Picovoice: Runtime Error: $error");
    stateNotifier.value = PicovoiceState.error;
  }

  // --- Controls ---

  Future<void> _pauseForTts() async {
    if (_isInitialized && _isPorcupineRunning) {
      debugPrint("Picovoice: Pausing for TTS");
      try {
        await _porcupineManager?.stop();
        _isPorcupineRunning = false;
        stateNotifier.value = PicovoiceState.ttsSpeaking;
      } catch (e) {
        debugPrint("Picovoice: Error pausing Porcupine: $e");
      }
    } else if (_isInitialized) {
      // Even if already stopped, we should be in ttsSpeaking state if TTS started
      stateNotifier.value = PicovoiceState.ttsSpeaking;
    }
  }

  Future<void> _resumeFromTts() async {
    if (_isInitialized &&
        stateNotifier.value == PicovoiceState.ttsSpeaking &&
        !_isStarting) {
      debugPrint("Picovoice: Resuming after TTS");
      // Add a stabilization delay to ensure native audio session is fully released
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_tts.isSpeaking && stateNotifier.value == PicovoiceState.ttsSpeaking) {
        _isStarting = true;
        try {
          if (!_isPorcupineRunning) {
            await _porcupineManager?.start();
            _isPorcupineRunning = true;
            stateNotifier.value = PicovoiceState.idle;
            debugPrint("Picovoice: Porcupine restarted after TTS.");
          } else {
            debugPrint("Picovoice: Porcupine already running after TTS.");
            stateNotifier.value = PicovoiceState.idle;
          }
        } catch (e) {
          debugPrint("Picovoice: Error resuming Porcupine after TTS: $e");
          stateNotifier.value = PicovoiceState.error;
        } finally {
          _isStarting = false;
        }
      }
    }
  }

  void dispose() {
    _stopEngines();
  }

  Future<String> _extractAsset(String assetPath) async {
    final docDir = await getApplicationDocumentsDirectory();
    final fileName = assetPath.split('/').last;
    final file = File('${docDir.path}/$fileName');

    try {
      debugPrint("Picovoice: Loading asset bundle: $assetPath");
      final ByteData data;
      try {
        data = await rootBundle.load(assetPath);
      } catch (e) {
        debugPrint("Picovoice: rootBundle.load FAILED for $assetPath: $e");
        errorNotifier.value = "Asset not found in bundle: $assetPath";
        return assetPath;
      }

      debugPrint("Picovoice: Writing to local file: ${file.path}");
      final bytes = data.buffer.asUint8List();
      await file.writeAsBytes(bytes, flush: true);

      final size = await file.length();
      debugPrint("Picovoice: Extraction complete. File size: $size bytes.");

      return file.path;
    } catch (e) {
      debugPrint(
        "Picovoice: File system error during extraction of $assetPath: $e",
      );
      errorNotifier.value = "File system error: $e";
      return assetPath;
    }
  }
}

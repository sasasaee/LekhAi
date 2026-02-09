import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine.dart';
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
  idle,           // Waiting for Wake Word (Porcupine running)
  wakeDetected,   // Wake word heard (switching)
  commandListening,// Listening for Intent (Rhino running)
  processing,     // Processing Intent (Rhino done)
  ttsSpeaking,    // Paused due to TTS
  error,          // Initialization or runtime error
  disabled,       // Manually disabled
}

class PicovoiceService {
  static final PicovoiceService _instance = PicovoiceService._internal();

  factory PicovoiceService() => _instance;

  PorcupineManager? _porcupineManager;
  RhinoManager? _rhinoManager;
  
  final TtsService _tts = TtsService();
  final AccessibilityService _accessibility = AccessibilityService();
  VoiceCommandService? _voiceCommandService;
  
  // State
  final ValueNotifier<PicovoiceState> stateNotifier = ValueNotifier(PicovoiceState.idle);
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null); // Added for detailed errors
  
  // Configuration
  String? _accessKey ="ACCESS KEY HERE";
  
  // Default models placeholders
  final String _keywordPath = "assets/picovoice/Lekhai_android.ppn"; 
  final String _contextPath = "assets/picovoice/Lekhai_android.rhn"; 

  bool _isInitialized = false;
  bool _isEnabled = true; // Default to true

  PicovoiceService._internal();

  /// Initialize the service.
  /// Needs [voiceCommandService] to execute intents.
  Future<void> init(VoiceCommandService voiceService) async {
    _voiceCommandService = voiceService;
    await _loadSettings();
    
    // Subscribe to TTS to handle collisions
    _tts.speakingStream.listen((isSpeaking) {
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
        errorNotifier.value = "Microphone permission denied. Voice commands disabled.";
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
      errorNotifier.value = "Picovoice AccessKey is missing. Please set it in Preferences.";
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
      
      try {
        // Extract assets to local file system
      final keywordPath = await _extractAsset(_keywordPath);
      final contextPath = await _extractAsset(_contextPath);
      
      // If extraction returned the original path, it means it failed but we caught it.
      // But Picovoice can't use 'assets/...' paths directly on Android.
      if (keywordPath == _keywordPath || contextPath == _contextPath) {
        throw Exception("Failed to prepare local model files. Check logs for details.");
      }

      debugPrint("Picovoice: Local Keyword path: $keywordPath");
      debugPrint("Picovoice: Local Context path: $contextPath");

      // Initialize Porcupine (Wake Word)
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _accessKey!,
        [keywordPath],
        _wakeWordCallback,
        errorCallback: (error) {
           debugPrint("Picovoice: Porcupine Error: $error");
           _errorCallback(error);
        },
      );

      // Initialize Rhino (Speech-to-Intent)
      _rhinoManager = await RhinoManager.create(
        _accessKey!,
        contextPath,
        _inferenceCallback,
        sensitivity: 0.7, // Increased sensitivity for better short phrase recognition
        processErrorCallback: (error) {
           debugPrint("Picovoice: Rhino Error: $error");
           _errorCallback(error);
        },
      );
      
      // Start Porcupine Loop
      await _porcupineManager?.start();
      _isInitialized = true;
      debugPrint("Picovoice: Engines Initialized successfully. State: ${stateNotifier.value}");
      debugPrint("Picovoice: Listening for Wake Word ONLY (Filename: ${keywordPath.split('/').last})");
      
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
    await _porcupineManager?.stop();
    await _porcupineManager?.delete();
    _porcupineManager = null;
    
    await _rhinoManager?.delete(); // Rhino doesn't have stop(), just delete/process
    _rhinoManager = null;
    
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
      stateNotifier.value = PicovoiceState.commandListening;
      debugPrint("Picovoice: Listening for command...");
      await _rhinoManager?.process();
    } catch (e) {
      debugPrint("Picovoice: Error switching to Rhino: $e");
      // Try to recover
      stateNotifier.value = PicovoiceState.idle;
      await _porcupineManager?.start();
    }
  }

  Future<void> _inferenceCallback(RhinoInference inference) async {
    final bool isUnderstood = inference.isUnderstood ?? false;
    debugPrint("Picovoice: Inference Result -> Understood: $isUnderstood, Intent: ${inference.intent}");
    
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
       debugPrint("Picovoice: Handoff Trigger detected (${inference.intent}). Pausing Porcupine for dictation.");
       stateNotifier.value = PicovoiceState.processing; // or a new state like 'pausedForDictation'
       // DO NOT RESTART PORCUPINE HERE
    } else {
       // Return to Idle (Wake Word Listening)
       stateNotifier.value = PicovoiceState.idle;
       try {
         await _porcupineManager?.start();
       } catch (e) {
         debugPrint("Picovoice: Error restarting Porcupine: $e");
         stateNotifier.value = PicovoiceState.error;
       }
    }
  }

  /// Call this when the external dictation/task is finished to resume listening.
  Future<void> resumeListening() async {
     if (!_isInitialized || !_isEnabled) return;
     
     debugPrint("Picovoice: Resuming listening after handoff.");
     stateNotifier.value = PicovoiceState.idle;
     try {
       await _porcupineManager?.start();
     } catch (e) {
       debugPrint("Picovoice: Error resuming Porcupine: $e");
       stateNotifier.value = PicovoiceState.error;
     }
  }

  void _errorCallback(dynamic error) {
    debugPrint("Picovoice: Runtime Error: $error");
    stateNotifier.value = PicovoiceState.error;
  }

  // --- Controls ---

  Future<void> _pauseForTts() async {
    if (_isInitialized) {
      debugPrint("Picovoice: Pausing for TTS");
      stateNotifier.value = PicovoiceState.ttsSpeaking;
      // Stop whichever is running
      // Usually Porcupine is running in Idle loop.
      await _porcupineManager?.stop(); 
      // Rhino usually stops itself after inference, so we assume we are in Idle or Listening.
      // If we are in Rhino mode, we can't easily "pause" it mid-inference without delete/create?
      // Rhino `process()` blocks? No, it's async but internally manages audio.
      // We'll assume Porcupine is the main one to pause. 
      // If Rhino is active, TTS hopefully won't trigger until inference is done? 
      // Or if TTS triggers, Rhino might just fail to hear?
    }
  }

  Future<void> _resumeFromTts() async {
    if (_isInitialized && stateNotifier.value == PicovoiceState.ttsSpeaking) {
       debugPrint("Picovoice: Resuming after TTS");
       await _porcupineManager?.start();
       stateNotifier.value = PicovoiceState.idle;
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
      debugPrint("Picovoice: File system error during extraction of $assetPath: $e");
      errorNotifier.value = "File system error: $e";
      return assetPath; 
    }
  }
}

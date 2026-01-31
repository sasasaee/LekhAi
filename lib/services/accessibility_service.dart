import 'package:vibration/vibration.dart'; // Upgrade to Vibration package
import 'package:flutter_tts/flutter_tts.dart'; // Add TTS support
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint

// import 'package:flutter/services.dart';
/// Defines semantic events for accessibility feedback.
enum AccessibilityEvent {
  navigation, // Screen transitions, dialogs opening
  success, // Action completed successfully
  error, // Operation failed
  warning, // Alerts, confirmations
  action, // Button clicks, toggles
  focus, // Navigation focus change
  loading, // Processing state
  general, // Default interaction
}

class AccessibilityService {
  // Configuration
  bool debugLogs = true;
  bool enabled = true; // NEW: Toggle master switch
  bool oneTapAnnounce =
      true; // Toggle for "Single Tap Announce + Double Tap Activate"
  static const Duration _debounceDuration = Duration(milliseconds: 100);

  DateTime? _lastFeedbackTime;
  Timer? _loadingTimer;
  bool? _hasVibrator;
  bool? _hasCustomVibrations;
  final FlutterTts _tts = FlutterTts(); // TTS Instance

  /// Singleton instance
  static final AccessibilityService _instance =
      AccessibilityService._internal();
  factory AccessibilityService() => _instance;
  AccessibilityService._internal() {
    _initCapabilities();
  }

  void _initCapabilities() async {
    _hasVibrator = await Vibration.hasVibrator();
    _hasCustomVibrations = await Vibration.hasCustomVibrationsSupport();

    // Load saved preference
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('haptics') ?? true;
    oneTapAnnounce = prefs.getBool('one_tap_announce') ?? true;

    if (debugLogs) {
      debugPrint(
        "Accessibility: Vibrator=$_hasVibrator, Custom=$_hasCustomVibrations, Enabled=$enabled, OneTapAnnounce=$oneTapAnnounce",
      );
    }
  }

  /// Toggles the haptic feedback on/off.
  void setEnabled(bool value) {
    enabled = value;
    if (debugLogs) debugPrint("Accessibility: Haptics Enabled = $enabled");
  }

  /// Toggles the "Single Tap Announce" behavior.
  void setOneTapAnnounce(bool value) {
    oneTapAnnounce = value;
    if (debugLogs) {
      debugPrint("Accessibility: One Tap Announce Enabled = $oneTapAnnounce");
    }
  }

  /// Triggers haptic feedback for a specific semantic event.
  /// Handles debounce and logging.
  Future<void> trigger(AccessibilityEvent event) async {
    if (!enabled) return; // Exit if disabled

    if (debugLogs) debugPrint("Accessibility Event: $event");

    // Debounce check
    final now = DateTime.now();
    if (_lastFeedbackTime != null &&
        now.difference(_lastFeedbackTime!) < _debounceDuration) {
      // if (debugLogs) debugPrint("Accessibility Event Debounced: $event");
      // return;
      // NOTE: Removing strict debounce for now to ensure user feels everything in testing
    }
    _lastFeedbackTime = now;

    // Execute Haptic
    try {
      if (event == AccessibilityEvent.loading) {
        _startLoadingHaptics();
      } else {
        _stopLoadingHaptics();
        await _executePattern(event);
      }
    } catch (e) {
      if (debugLogs) debugPrint("Accessibility Haptic Error: $e");
    }
  }

  Future<void> _executePattern(AccessibilityEvent event) async {
    // If device doesn't support vibration, fallback or exit
    if (_hasVibrator == false) return;

    // Custom Durations (The "Perfect" Feel)
    // - Low latency short bursts for UI
    // - Distinct heavy buzz for Errors
    switch (event) {
      case AccessibilityEvent.focus:
        // Subtle tick (increased from 10 to 40ms)
        await Vibration.vibrate(duration: 40);
        break;

      case AccessibilityEvent.navigation:
      case AccessibilityEvent.general:
        // Standard tick (increased from 15 to 60ms)
        await Vibration.vibrate(duration: 60);
        break;

      case AccessibilityEvent.action:
        // Strong click (increased from 25 to 80ms)
        await Vibration.vibrate(duration: 80);
        break;

      case AccessibilityEvent.success:
        // Distinct Pulse
        if (_hasCustomVibrations == true) {
          await Vibration.vibrate(pattern: [0, 50, 100, 50]);
        } else {
          await Vibration.vibrate(duration: 150); // Fallback
        }
        break;

      case AccessibilityEvent.warning:
        // Short buzz
        await Vibration.vibrate(duration: 250);
        break;

      case AccessibilityEvent.error:
        // Distinct heavy buzz
        await Vibration.vibrate(duration: 500);
        break;

      default:
        await Vibration.vibrate(duration: 40);
        break;
    }
  }

  /// Starts a rhythmic pulse for loading states.
  void _startLoadingHaptics() {
    if (_loadingTimer != null && _loadingTimer!.isActive) return;

    if (debugLogs) debugPrint("Accessibility: Starting Loading Pulse");

    // Initial pulse
    Vibration.vibrate(duration: 15);

    _loadingTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      Vibration.vibrate(duration: 15);
    });
  }

  /// Stops the loading pulse.
  void _stopLoadingHaptics() {
    if (_loadingTimer != null) {
      if (debugLogs) debugPrint("Accessibility: Stopping Loading Pulse");
      _loadingTimer!.cancel();
      _loadingTimer = null;
    }
  }

  // --- Voice Integration Stubs (Future Proofing) ---

  Future<void> speak(String message) async {
    if (debugLogs) debugPrint("Accessibility: Speaking '$message'");
    if (enabled) {
      await _tts.setLanguage("en-US");
      await _tts.speak(message);
    }
  }

  Future<void> announce(String message, AccessibilityEvent event) async {
    await trigger(event); // Haptic first
    await speak(message); // Then Audio
  }
}

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class KioskService extends WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('com.example.lekhai/kiosk');
  
  // Singleton pattern
  static final KioskService _instance = KioskService._internal();
  factory KioskService() => _instance;
  KioskService._internal();

  bool _isKioskActive = false;
  int _violationCount = 0;

  bool get isKioskActive => _isKioskActive;
  int get violationCount => _violationCount;

  // Initialize lifecycle observer
  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Enables Kiosk Mode by calling the native Android `startLockTask`.
  Future<bool> enableKioskMode() async {
    try {
      final bool success = await _channel.invokeMethod('startKioskMode');
      if (success) {
        _isKioskActive = true;
        _violationCount = 0; // Reset violations on new session
        print("Kiosk Mode Enabled: SUCCESS");
        return true;
      }
    } on PlatformException catch (e) {
      print("Kiosk Mode Enable Failed: ${e.message}");
    }
    return false;
  }

  /// Disables Kiosk Mode by calling the native Android `stopLockTask`.
  Future<bool> disableKioskMode() async {
    try {
      final bool success = await _channel.invokeMethod('stopKioskMode');
      if (success) {
        _isKioskActive = false;
        print("Kiosk Mode Disabled: SUCCESS");
        return true;
      }
    } on PlatformException catch (e) {
      print("Kiosk Mode Disable Failed: ${e.message}");
    }
    return false;
  }

  // --- Violation Monitoring ---

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isKioskActive) return;

    // If the app is paused or inactive while Kiosk Mode is supposed to be active,
    // it means the user might be trying to leave or an overlay popped up.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _handleViolation(state);
    }
  }

  void _handleViolation(AppLifecycleState state) {
    _violationCount++;
    print("KIOSK VIOLATION #$_violationCount DETECTED: App State changed to $state");
    
    // In a real scenario, you might want to auto-submit or lock the screen further.
    // For now, we just log it. The PaperDetailScreen could poll this count.
  }
}

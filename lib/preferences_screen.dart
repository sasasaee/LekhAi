import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/tts_service.dart';
import 'widgets/picovoice_mic_icon.dart'; // Added
import 'services/voice_command_service.dart';
import 'services/accessibility_service.dart';
import 'services/picovoice_service.dart'; // Added
import 'services/screen_description_service.dart'; // Added
import 'widgets/accessible_widgets.dart'; // Added
// import 'services/stt_service.dart'; // Removed

class PreferencesScreen extends StatefulWidget {
  final TtsService ttsService;
  final VoiceCommandService voiceService;
  final AccessibilityService? accessibilityService;
  final PicovoiceService? picovoiceService; // Added

  const PreferencesScreen({
    super.key,
    required this.ttsService,
    required this.voiceService,
    this.accessibilityService,
    this.picovoiceService, // Added
  });

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  bool _voiceCommandsEnabled = true; // Default ON

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    ScreenDescriptionService().announceScreen('settings', widget.ttsService);

    // Subscribe to voice command stream
    _commandSubscription = widget.voiceService.commandStream.listen((result) {
      if (mounted) _executeVoiceCommand(result);
    });
  }

  StreamSubscription? _commandSubscription;

  @override
  void dispose() {
    _commandSubscription?.cancel();
    super.dispose();
  }

  // SttService listener methods removed

  void _executeVoiceCommand(CommandResult result) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    switch (result.action) {
      case VoiceAction.increaseVolume:
        _changeVolume(true);
        break;

      case VoiceAction.decreaseVolume:
        _changeVolume(false);
        break;

      case VoiceAction.increaseSpeed:
        _changeSpeed(true);
        break;

      case VoiceAction.decreaseSpeed:
        _changeSpeed(false);
        break;

      case VoiceAction.goBack:
        widget.ttsService.speak("Exiting settings.");
        Navigator.pop(context);
        break;

      case VoiceAction.saveResult:
        _savePreferences();
        break;

      case VoiceAction.resetPreferences:
        _reset();
        break;

      case VoiceAction.enableFeature:
        final feature = result.payload as String?;
        if (feature == 'haptics') {
          _setHaptics(true);
        } else if (feature == 'voice commands') {
          _setVoiceCommands(true);
        }
        break;

      case VoiceAction.disableFeature:
        final feature = result.payload as String?;
        if (feature == 'haptics') {
          _setHaptics(false);
        } else if (feature == 'voice commands') {
          _setVoiceCommands(false);
        }
        break;

      case VoiceAction.toggleHaptic:
        _setHaptics(!AccessibilityService().enabled);
        break;

      case VoiceAction.toggleVoiceCommands:
        _setVoiceCommands(!_voiceCommandsEnabled);
        break;

      case VoiceAction.describeScreen:
        ScreenDescriptionService().describeScreen(
          'settings',
          widget.ttsService,
        );
        break;

      default:
        widget.voiceService.performGlobalNavigation(result);
        break;
    }
  }

  void _reset() async {
    // 1. Reset Global Notifiers (This will sync other screens)
    widget.voiceService.speedNotifier.value = 1.0;
    widget.voiceService.volumeNotifier.value = 0.7;

    // 2. Local State Reset
    // State cleared.

    // 3. Service/Pref Reset
    await widget.ttsService
        .resetPreferences(); // Resets speed/volume in prefs/engine

    widget.ttsService.speak("Settings have been reset.");
    AccessibilityService().trigger(AccessibilityEvent.warning);
  }

  void _changeVolume(bool increase) async {
    double oldVol = widget.voiceService.volumeNotifier.value;
    double newVolume = (oldVol + (increase ? 0.1 : -0.1)).clamp(0.0, 1.0);
    widget.voiceService.volumeNotifier.value = newVolume;
    await widget.ttsService.setVolume(newVolume);
    _persistSettings(); // Auto-save
    widget.ttsService.speak(
      "Volume ${increase ? 'increased' : 'decreased'} to ${(newVolume * 100).toInt()} percent.",
    );
  }

  void _changeSpeed(bool increase) async {
    double oldSpeed = widget.voiceService.speedNotifier.value;
    double newSpeed = (oldSpeed + (increase ? 0.25 : -0.25)).clamp(0.5, 2.0);
    widget.voiceService.speedNotifier.value = newSpeed;
    await widget.ttsService.setSpeed(newSpeed * 0.5);
    _persistSettings(); // Auto-save
    widget.ttsService.speak(
      "Speed ${increase ? 'increased' : 'decreased'} to ${newSpeed.toStringAsFixed(2)}.",
    );
  }

  void _setHaptics(bool enabled) {
    if (enabled == AccessibilityService().enabled) {
      widget.ttsService.speak(
        "Haptic feedback is already ${enabled ? 'enabled' : 'disabled'}.",
      );
      return;
    }
    setState(() {
      AccessibilityService().setEnabled(enabled);
    });
    _persistSettings(); // Auto-save
    if (enabled) AccessibilityService().trigger(AccessibilityEvent.action);
    widget.ttsService.speak(
      "Haptic feedback ${enabled ? 'enabled' : 'disabled'}.",
    );
  }

  void _setVoiceCommands(bool enabled) async {
    if (enabled == _voiceCommandsEnabled) {
      widget.ttsService.speak(
        "Voice commands are already ${enabled ? 'enabled' : 'disabled'}.",
      );
      return;
    }
    setState(() => _voiceCommandsEnabled = enabled);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('voice_commands_enabled', enabled);
    await widget.picovoiceService?.setEnabled(enabled);
    _persistSettings(); // Auto-save
    widget.ttsService.speak(
      "Voice commands ${enabled ? 'enabled' : 'disabled'}.",
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await widget.ttsService.loadPreferences();
    final sp = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // Load into notifiers
        widget.voiceService.speedNotifier.value =
            (prefs['speed'] as num?)?.toDouble() ?? 1.0;
        widget.voiceService.volumeNotifier.value =
            (prefs['volume'] as num?)?.toDouble() ?? 0.7;

        // Load Haptics
        bool hapticsEnabled = prefs['haptics'] as bool? ?? true;
        AccessibilityService().setEnabled(hapticsEnabled);

        // Load One Tap Announce (still needed for AccessibilityService)
        bool oneTapAnnounce = prefs['one_tap_announce'] as bool? ?? true;
        AccessibilityService().setOneTapAnnounce(oneTapAnnounce);

        _voiceCommandsEnabled = sp.getBool('voice_commands_enabled') ?? true;
      });
      // Ensure engine is synced
      await widget.ttsService.setSpeed(
        widget.voiceService.speedNotifier.value * 0.5,
      );
      await widget.ttsService.setVolume(
        widget.voiceService.volumeNotifier.value,
      );
    }
  }

  Future<void> _persistSettings() async {
    final speed = widget.voiceService.speedNotifier.value;
    final volume = widget.voiceService.volumeNotifier.value;

    await widget.ttsService.savePreferences(speed: speed, volume: volume);
    await widget.ttsService.saveHapticPreference(
      AccessibilityService().enabled,
    );
    await widget.ttsService.saveOneTapAnnouncePreference(
      AccessibilityService().oneTapAnnounce,
    );
  }

  Future<void> _savePreferences() async {
    await _persistSettings();
    widget.ttsService.speak("Settings saved successfully.");
    AccessibilityService().trigger(AccessibilityEvent.success);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (widget.picovoiceService != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: PicovoiceMicIcon(service: widget.picovoiceService!),
            ),
        ],
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: "Back",
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).cardTheme.color!.withValues(alpha: 0.8),
              Theme.of(context).scaffoldBackgroundColor,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Speed Card
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: widget.voiceService.speedNotifier,
                        builder: (context, speed, child) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Speed: ${speed.toStringAsFixed(2)}x',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              AccessibleSlider(
                                min: 0.5,
                                max: 2.0,
                                value: speed,
                                divisions: 6,
                                onChanged: (v) {
                                  widget.voiceService.speedNotifier.value = v;
                                  widget.ttsService.setSpeed(v * 0.5);
                                  _persistSettings(); // Auto-save
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Volume Card
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: widget.voiceService.volumeNotifier,
                        builder: (context, volume, child) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Volume: ${(volume * 100).toInt()}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              AccessibleSlider(
                                min: 0.0,
                                max: 1.0,
                                value: volume,
                                divisions: 10,
                                onChanged: (v) {
                                  widget.voiceService.volumeNotifier.value = v;
                                  widget.ttsService.setVolume(v);
                                  _persistSettings(); // Auto-save
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Haptic Feedback Toggle
                _GlassCard(
                  child: SwitchListTile(
                    value: AccessibilityService().enabled,
                    activeThumbColor: Theme.of(context).primaryColor,
                    title: Text(
                      "Haptic Feedback",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      "Vibrate on interactions",
                      style: GoogleFonts.outfit(color: Colors.white54),
                    ),
                    onChanged: (val) {
                      setState(() {
                        AccessibilityService().setEnabled(val);
                      });
                      _persistSettings(); // Auto-save
                      if (val) {
                        AccessibilityService().trigger(
                          AccessibilityEvent.action,
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Single Tap Announce Toggle
                const SizedBox(height: 20),

                // Voice Commands Toggle
                _GlassCard(
                  child: SwitchListTile(
                    value: _voiceCommandsEnabled,
                    activeThumbColor: Theme.of(context).primaryColor,
                    title: Text(
                      "Voice Commands",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      "Enable always-on voice control",
                      style: GoogleFonts.outfit(color: Colors.white54),
                    ),
                    onChanged: (val) async {
                      setState(() => _voiceCommandsEnabled = val);
                      final sp = await SharedPreferences.getInstance();
                      await sp.setBool('voice_commands_enabled', val);
                      await widget.picovoiceService?.setEnabled(val);
                      _persistSettings(); // Auto-save
                      if (val) {
                        widget.ttsService.speak("Voice commands enabled.");
                      } else {
                        widget.ttsService.speak("Voice commands disabled.");
                      }
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _reset,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(
                            color: Colors.redAccent,
                            width: 2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Reset',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

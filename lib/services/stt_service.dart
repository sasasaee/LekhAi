import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class SttService {
  late stt.SpeechToText _speech;
  bool _isAvailable = false;
  
  // Callback for status updates (listening, notListening, done)
  Function(String)? onStatusChange;
  // Callback for errors
  Function(String)? onError;

  bool get isAvailable => _isAvailable;
  bool get isListening => _speech.isListening;

  SttService() {
    _speech = stt.SpeechToText();
  }

  Future<bool> init({Function(String)? onStatus, Function(String)? onError}) async {
    this.onStatusChange = onStatus;
    this.onError = onError;
    
    _isAvailable = await _speech.initialize(
      onError: (error) {
        print('STT Error: ${error.errorMsg}');
        if (this.onError != null) this.onError!(error.errorMsg);
      },
      onStatus: (status) {
        print('STT Status: $status');
        if (this.onStatusChange != null) this.onStatusChange!(status);
      },
      debugLogging: false,
    );
    return _isAvailable;
  }

  Future<void> startListening({
    required Function(String) onResult,
    required String localeId,
  }) async {
    if (!_isAvailable) return;
    
    // 1. MUTE SYSTEM SOUNDS (To hide the "ding")
    double? originalSystemVol;
    double? originalNotifVol;
    try {
      originalSystemVol = await FlutterVolumeController.getVolume(stream: AudioStream.system);
      originalNotifVol = await FlutterVolumeController.getVolume(stream: AudioStream.notification);
      
      await FlutterVolumeController.updateShowSystemUI(false);
      await FlutterVolumeController.setVolume(0, stream: AudioStream.system);
      await FlutterVolumeController.setVolume(0, stream: AudioStream.notification);
    } catch (e) {
      print("Error muting for STT: $e");
    }

    // 2. START LISTENING
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords),
      listenFor: const Duration(seconds: 300), 
      pauseFor: const Duration(seconds: 30),   
      partialResults: true,
      localeId: localeId,
      cancelOnError: false, 
      listenMode: stt.ListenMode.dictation, 
    );
    
    // 3. RESTORE VOLUME (After delay to ensure beep didn't play)
    Future.delayed(const Duration(milliseconds: 600), () async {
      try {
        if (originalSystemVol != null) {
          await FlutterVolumeController.setVolume(originalSystemVol, stream: AudioStream.system);
        }
        if (originalNotifVol != null) {
            await FlutterVolumeController.setVolume(originalNotifVol, stream: AudioStream.notification);
        }
      } catch (e) {
        print("Error restoring volume: $e");
      }
    });
  }

  Future<void> stopListening() async {
    await _speech.stop();
    await FlutterVolumeController.updateShowSystemUI(true);
  }

  void dispose() {
    _speech.stop();
    FlutterVolumeController.updateShowSystemUI(true);
  }
}

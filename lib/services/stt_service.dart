import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

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
      debugLogging: true,
    );
    return _isAvailable;
  }

  Future<void> startListening({
    required Function(String) onResult,
    required String localeId,
  }) async {
    if (!_isAvailable) return;
    
    // For exams:
    // listenFor: Max duration (e.g., 30s or minute before it might auto-cut, depending on OS limits)
    // pauseFor: How long to wait for silence before stopping (set high for thinking time, e.g., 5s)
    // partialResults: true (to see text as speaking)
    // listenMode: dictation (optimized for longer speech)
    
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords),
      listenFor: const Duration(seconds: 60), 
      pauseFor: const Duration(seconds: 10), 
      partialResults: true,
      localeId: localeId,
      cancelOnError: false, // Don't stop on minor errors
      listenMode: stt.ListenMode.dictation, 
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  void dispose() {
    _speech.stop();
  }
}

import 'package:flutter/widgets.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<bool> hasPermission() async {
    // Check permission using permission_handler for reliable results
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    return status.isGranted;
  }

  Future<void> startRecording(String path) async {
    try {
      if (await hasPermission()) {
        // Ensure directory exists
        final file = File(path);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }

        // Start recording to file
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc, // Good balance of quality/size
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );
        _isRecording = true;
      } else {
        throw Exception("Microphone permission not granted");
      }
    } catch (e) {
      debugPrint("Error starting record: $e");
      rethrow;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      return path;
    } catch (e) {
      debugPrint("Error stopping record: $e");
      return null;
    }
  }

  Future<void> dispose() async {
    _audioRecorder.dispose();
  }
}

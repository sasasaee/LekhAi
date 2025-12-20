import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart'; // Add this

class AudioRecorderService {
  final Record _recorder = Record();
  final AudioPlayer _audioPlayer = AudioPlayer(); // Create a player instance
  String? _filePath;

  Future<void> init() async {
    await _recorder.hasPermission();
  }

  // --- RECORDING LOGIC ---
  Future<String> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) throw Exception('Microphone permission not granted');

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _filePath = path;

    await _recorder.start(
      path: path,
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      samplingRate: 44100,
    );
    return path;
  }

  Future<String?> stopRecording() async {
    if (!await _recorder.isRecording()) return null;
    return await _recorder.stop();
  }

  // --- PLAYBACK LOGIC ---
  Future<void> playRecordedFile(String path) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
  }

  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose(); // Clean up player
  }
}
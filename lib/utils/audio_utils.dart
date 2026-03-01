import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class AudioUtils {
  /// Merges two standard PCM WAV files into a third destination file.
  /// Assumes both files have the same format (channels, sample rate, bits per sample).
  static Future<bool> mergeWavFiles(
      String path1, String path2, String destPath) async {
    try {
      final file1 = File(path1);
      final file2 = File(path2);

      if (!await file1.exists() || !await file2.exists()) {
        debugPrint('AudioUtils: One or both source files do not exist.');
        return false;
      }

      final bytes1 = await file1.readAsBytes();
      final bytes2 = await file2.readAsBytes();

      // WAV header is typically 44 bytes.
      if (bytes1.length < 44 || bytes2.length < 44) {
        debugPrint('AudioUtils: Invalid WAV file size.');
        return false;
      }

      // Extract the data chunks (everything after the 44-byte header).
      final data1 = bytes1.sublist(44);
      final data2 = bytes2.sublist(44);

      // Create a new file for the merged audio.
      final destFile = File(destPath);
      if (await destFile.exists()) {
        await destFile.delete();
      }

      final sink = destFile.openWrite();

      // 1. Write the 44-byte header from the first file.
      sink.add(bytes1.sublist(0, 44));

      // 2. Write the data from the first file.
      sink.add(data1);

      // 3. Write the data from the second file.
      sink.add(data2);

      await sink.flush();
      await sink.close();

      // 4. Update the header size fields in the destination file.
      final totalDataLength = data1.length + data2.length;
      final fileSize = totalDataLength + 36; // Data length + 36

      final randomAccessFile = await destFile.open(mode: FileMode.append);

      // Update RIFF chunk size (bytes 4-7)
      final riffSizeBuffer = ByteData(4)..setUint32(0, fileSize, Endian.little);
      await randomAccessFile.setPosition(4);
      await randomAccessFile.writeFrom(riffSizeBuffer.buffer.asUint8List());

      // Update data chunk size (bytes 40-43)
      final dataSizeBuffer = ByteData(4)
        ..setUint32(0, totalDataLength, Endian.little);
      await randomAccessFile.setPosition(40);
      await randomAccessFile.writeFrom(dataSizeBuffer.buffer.asUint8List());

      await randomAccessFile.close();

      return true;
    } catch (e) {
      debugPrint('AudioUtils: Error merging wav files: $e');
      return false;
    }
  }
}

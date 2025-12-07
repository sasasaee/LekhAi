import 'package:flutter/material.dart';
import 'services/tts_service.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter_pdf_text/flutter_pdf_text.dart';
import 'dart:io';

class PdfViewerScreen extends StatefulWidget {
  final String path;
  final TtsService ttsService;
  const PdfViewerScreen({
    super.key,
    required this.path,
    required this.ttsService,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PDFDoc? _doc;
  List<String> _sentences = [];
  int _currentIndex = 0;
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    _doc = await PDFDoc.fromPath(widget.path);
    String text = await _doc!.text;
    _sentences = text.split(RegExp(r'(?<=[.!?])\s+')); // split by sentence
    _currentIndex = 0;
    _startReading();
  }

  void _startReading() async {
    if (_isReading) return;
    _isReading = true;

    while (_currentIndex < _sentences.length) {
      if (!mounted) break;

      if (widget.ttsService.isPaused) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue; // wait while paused
      }

      String sentence = _sentences[_currentIndex].trim();
      if (sentence.isNotEmpty) {
        await widget.ttsService.speakAndWait(sentence);
      }

      _currentIndex++;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _isReading = false;
  }

  void _stopReading() async {
    _currentIndex = 0;
    _isReading = false;
    await widget.ttsService.stop();
  }

  void _pauseReading() async {
    await widget.ttsService.pause();
  }

  void _resumeReading() async {
    await widget.ttsService.resume();
    _startReading(); // Continue reading where left off
  }

  void _restartReading() async {
    await widget.ttsService.stop();
    _currentIndex = 0;
    _isReading = false;
    _startReading();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Viewer')),
      body: Column(
        children: [
          Expanded(child: SfPdfViewer.file(File(widget.path))),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: _pauseReading,
                  child: const Text('Pause'),
                ),
                ElevatedButton(
                  onPressed: _resumeReading,
                  child: const Text('Resume'),
                ),
                ElevatedButton(
                  onPressed: _stopReading,
                  child: const Text('Stop'),
                ),
                ElevatedButton(
                  onPressed: _restartReading,
                  child: const Text('Restart'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

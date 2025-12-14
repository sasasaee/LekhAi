import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'services/ocr_service.dart';
import 'services/question_storage_service.dart';
import 'services/tts_service.dart';
import 'services/question_segmentation_service.dart';
import 'models/question_model.dart';
import 'questions_screen.dart';

class OcrScreen extends StatefulWidget {
  final TtsService ttsService;
  const OcrScreen({super.key, required this.ttsService});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final OcrService _ocrService = OcrService();
  final QuestionStorageService _storageService = QuestionStorageService();
  final QuestionSegmentationService _segmenter = QuestionSegmentationService();
  final ImagePicker _picker = ImagePicker();

  bool _isProcessing = false;
  File? _imageFile;

  // NEW: structured output
  ParsedDocument? _doc;

  // Optional: also keep raw lines for debugging
  List<OcrLine> _rawLines = [];

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak(
      "Welcome to the OCR screen. You can scan from camera or select from gallery.",
    );
    _retrieveLostData();
  }

  Future<void> _retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) return;
    if (response.file != null) {
      setState(() {
        _imageFile = File(response.file!.path);
        _isProcessing = true;
        _doc = null;
        _rawLines = [];
      });
      await _processImage(response.file!.path);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _imageFile = File(image.path);
        _isProcessing = true;
        _doc = null;
        _rawLines = [];
      });

      await _processImage(image.path);
    } catch (e) {
      widget.ttsService.speak("Error picking image");
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processImage(String path) async {
    try {
      // 1) OCR -> lines
      final lines = await _ocrService.processImageLines(path);

      // 2) Rule-based segmentation
      final doc = _segmenter.segment(lines);

      setState(() {
        _rawLines = lines;
        _doc = doc;
      });

      final qCount = doc.sections.fold<int>(
        0,
        (sum, s) => sum + s.questions.length,
      );

      widget.ttsService.speak(
        qCount == 0
            ? "Text extracted, but I could not detect questions clearly."
            : "Extracted and segmented $qCount questions. Tap save to store.",
      );
    } catch (e) {
      widget.ttsService.speak("Error processing image");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveParsed() async {
    final doc = _doc;
    if (doc == null) return;

    // Save as JSON string for now (so you don't need to change storage yet)
    // Use model serialization
    final docJson = doc.toJson();
    // Add timestamp for "Paper" grouping
    docJson['timestamp'] = DateTime.now().toIso8601String();

    final jsonString = jsonEncode(docJson);

    await _storageService.saveQuestion(jsonString);

    widget.ttsService.speak("Saved successfully");
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionsScreen(ttsService: widget.ttsService),
      ),
    );
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Question')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 24),
                textStyle: const TextStyle(fontSize: 20),
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed:
                  _isProcessing ? null : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt, size: 32),
              label: const Text('Camera'),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 24),
                textStyle: const TextStyle(fontSize: 20),
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed:
                  _isProcessing ? null : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library, size: 32),
              label: const Text('Gallery'),
            ),
            const SizedBox(height: 24),

            if (_imageFile != null)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_imageFile!, fit: BoxFit.contain),
                ),
              ),
            const SizedBox(height: 16),

            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else if (doc != null) ...[
              const Text(
                'Detected Header:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _BoxText(doc.header.join("\n")),

              const SizedBox(height: 16),
              const Text(
                'Detected Questions:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              if (doc.sections.isEmpty)
                _BoxText("No sections/questions detected.")
              else
                ...doc.sections.map((s) {
                  return _SectionPreview(section: s);
                }),

              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saveParsed,
                icon: const Icon(Icons.save),
                label: const Text('Save Segmented Result'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),

              const SizedBox(height: 12),
              Text(
                "Debug: OCR lines = ${_rawLines.length}",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoxText extends StatelessWidget {
  final String text;
  const _BoxText(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }
}

class _SectionPreview extends StatelessWidget {
  final ParsedSection section;
  const _SectionPreview({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (section.title != null && section.title!.trim().isNotEmpty) ...[
              Text(
                section.title!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ],
            if (section.questions.isEmpty)
              const Text("No questions found in this section.")
            else
              ...section.questions.take(6).map((q) {
                final title = q.number != null ? "Q${q.number}" : "Q";
                final marks = (q.marks != null && q.marks!.trim().isNotEmpty)
                    ? "   (${q.marks})"
                    : "";
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$title$marks: ${q.prompt}",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (q.body.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            q.body.join("\n"),
                            style: TextStyle(color: Colors.grey.shade800),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            if (section.questions.length > 6)
              Text(
                "…and ${section.questions.length - 6} more",
                style: TextStyle(color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }
}

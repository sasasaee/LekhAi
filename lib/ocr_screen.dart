import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'services/ocr_service.dart';
import 'services/question_storage_service.dart';
import 'services/tts_service.dart';
import 'questions_screen.dart';
import 'package:flutter/services.dart';

class OcrScreen extends StatefulWidget {
  final TtsService ttsService;
  const OcrScreen({super.key, required this.ttsService});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final OcrService _ocrService = OcrService();
  final QuestionStorageService _storageService = QuestionStorageService();
  final ImagePicker _picker = ImagePicker();

  String? _extractedText;
  bool _isProcessing = false;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    widget.ttsService.speak(
      "Welcome to the OCR screen. Here you can scan questions using your camera or select images from your gallery.",
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
      });
      _processImage(response.file!.path);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _imageFile = File(image.path);
          _isProcessing = true;
          _extractedText = null;
        });
        await _processImage(image.path);
      }
    } catch (e) {
      widget.ttsService.speak("Error picking image");
    }
  }

  Future<void> _processImage(String path) async {
    try {
      final text = await _ocrService.processImage(path);
      setState(() {
        _extractedText = text;
      });
      widget.ttsService.speak("Text extracted. Tap save to store question.");
    } catch (e) {
      widget.ttsService.speak("Error processing image");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _saveQuestion() async {
    if (_extractedText != null && _extractedText!.isNotEmpty) {
      await _storageService.saveQuestion(_extractedText!);
      widget.ttsService.speak("Question saved successfully");
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuestionsScreen(ttsService: widget.ttsService),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Question')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Big Camera Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 24),
                textStyle: const TextStyle(fontSize: 20),
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _isProcessing
                  ? null
                  : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt, size: 32),
              label: const Text('Camera'),
            ),
            const SizedBox(height: 16),

            // Big Gallery Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 24),
                textStyle: const TextStyle(fontSize: 20),
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _isProcessing
                  ? null
                  : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library, size: 32),
              label: const Text('Gallery'),
            ),
            const SizedBox(height: 24),

            // Image preview
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

            // Loading indicator or extracted text
            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else if (_extractedText != null) ...[
              const Text(
                'Extracted Text:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_extractedText!),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saveQuestion,
                icon: const Icon(Icons.save),
                label: const Text('Save Question'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'services/ocr_service.dart';
import 'services/question_storage_service.dart';
import 'questions_screen.dart';
import 'services/stt_service.dart';


class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

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
    _retrieveLostData();
  }
  /*
  Future<void> _initializeStt() async {
  await _sttService.init();
  if (!_sttService.isAvailable) {
    widget.ttsService.speak("Speech recognition is not available on this device.");
  }
} */

  Future<void> _retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) {
      return;
    }
    if (response.file != null) {
      setState(() {
        _imageFile = File(response.file!.path);
        _isProcessing = true;
      });
      _processImage(response.file!.path);
    } else {
      // Handle error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recovering image: ${response.exception?.code}')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _processImage(String path) async {
    try {
      final text = await _ocrService.processImage(path);
      if (mounted) {
        setState(() {
          _extractedText = text;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _saveQuestion() async {
    if (_extractedText != null && _extractedText!.isNotEmpty) {
      await _storageService.saveQuestion(_extractedText!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question saved!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const QuestionsScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _ocrService.dispose();
   // _sttService.dispose(); 
    super.dispose();
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
            if (_imageFile != null)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: Image.file(_imageFile!, fit: BoxFit.contain),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else if (_extractedText != null) ...[
              const Text(
                'Extracted Text:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_extractedText!),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saveQuestion,
                child: const Text('Save to Questions'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

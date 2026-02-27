import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import '../models/paper_model.dart';
import 'package:flutter/foundation.dart';

class GeminiPaperService {
  static final GeminiPaperService _instance = GeminiPaperService._internal();
  factory GeminiPaperService() => _instance;
  GeminiPaperService._internal();

  static String? _cachedModelName;

  Future<ParsedDocument> processImage(String imagePath, String apiKey) async {
    // 1. Find a valid model name dynamically
    final modelName = _cachedModelName ?? await _findValidModel(apiKey) ?? 'gemini-1.5-flash';
    _cachedModelName = modelName;
    debugPrint("GeminiService using model: $modelName");

    final model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    final imageBytes = await File(imagePath).readAsBytes();
    final prompt = _buildPrompt();

    try {
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(
            'image/jpeg',
            imageBytes,
          ), // Assuming JPEG, but API is flexible
        ]),
      ]);

      if (response.text == null) {
        throw Exception("Empty response from Gemini");
      }

      return _parseResponse(response.text!);
    } catch (e) {
      debugPrint("Gemini Processing Error: $e");
      rethrow;
    }
  }

  Future<String?> _findValidModel(String apiKey) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final models = json['models'] as List;

        final availableModels = models.map((m) {
          final name = m['name'].toString().replaceFirst('models/', '');
          final supportedMethods = m['supportedGenerationMethods'] as List?;
          return {
            'name': name,
            'supportsGenerate': supportedMethods?.contains('generateContent') ?? false,
          };
        }).where((m) => m['supportsGenerate'] == true).map((m) => m['name'] as String).toList();

        debugPrint("Available Gemini models: $availableModels");

        // Prioritized list of stable models
        const prioritizedModels = [
          'gemini-1.5-flash',
          'gemini-1.5-pro',
          'gemini-1.0-pro',
        ];

        for (final pModel in prioritizedModels) {
          if (availableModels.contains(pModel)) {
            debugPrint("Selected prioritized model: $pModel");
            return pModel;
          }
        }

        // Fallback to any 'flash' model if prioritized ones aren't available
        final flashFallback = availableModels.firstWhere(
          (m) => m.contains('flash'),
          orElse: () => '',
        );
        if (flashFallback.isNotEmpty) {
          debugPrint("Priority match failed, falling back to flash: $flashFallback");
          return flashFallback;
        }

        // Final fallback
        if (availableModels.isNotEmpty) {
          debugPrint("Final fallback to first available: ${availableModels.first}");
          return availableModels.first;
        }
      }
    } catch (e) {
      debugPrint("Error listing models: $e");
    }
    return null; // Fallback to default in processImage
  }


  String _buildPrompt() {
    return """
    Analyze this exam paper image and extract the questions into a structured JSON format. 
    
    Requirements:
    1. Extract all questions, including their numbers, text, and marks.
    2. Correct any OCR errors or typos clearly visible in the image.
    3. For accessibility: Replace visuals like dashes or underscores in fill-in-the-blanks with "... blank ...".
    
    4. **BOX & TABLE CONTENT (CRITICAL)**:
       - If there is a "Word Box", "Matching Column", or any boxed content associated with a question, you MUST format it using **strict delimiters**.
       - Use `[[BOX: <Title of Box>]]` to start a box.
       - Use `[[BOX END]]` to end a box.
       - INSIDE the box, list each item on a new line. Number them if they are part of a list (1., 2.).
       
       **Example of Box Format**:
       Question: Match the columns.
       Body List:
       [
         "[[BOX: Column A]]",
         "1. The Taj",
         "2. It",
         "3. Emperor Shahjahan",
         "[[BOX END]]",
         "[[BOX: Column B]]",
         "1. built",
         "2. stands",
         "3. is built",
         "[[BOX END]]",
         "[[BOX: Column C]]",
         "1. at Agra in India.",
         "2. as a tomb for his wife.",
         "[[BOX END]]"
       ]

    5. **CONTEXT vs CONTENT**:
       - Shared Context (passage for multiple questions) -> `context` field.
       - Specific Content (Box, word bank, diagram label for ONE question) -> `body` list (using the BOX format above).
    
    Output JSON Schema:
    {
      "name": "A short, descriptive title for the document (e.g., 'Class 10 History Term 1', 'Physics Quiz - Chapter 3')",
      "sections": [
        {
          "title": "Section Title",
          "context": "Shared context...",
          "questions": [
            {
              "number": "1",
              "prompt": "Make five sentences...",
              "body": ["[[BOX: Column A]]", "1. Item 1", "[[BOX END]]", "Normal text line"], 
              "marks": "5"
            }
          ]
        }
      ]
    }
    """;
  }

  ParsedDocument _parseResponse(String jsonString) {
    // Clean up potential markdown blocks if API returns ```json ... ```
    final initialClean = jsonString.replaceAll(
      RegExp(r'^```json\s*'),
      '',
    ); // Remove start
    final cleanJson = initialClean
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim(); // Remove end

    final Map<String, dynamic> data = jsonDecode(cleanJson);
    final sectionsList = data['sections'] as List;
    final String? docName = data['name']; // Extract auto-generated name

    List<ParsedSection> parsedSections = [];

    for (var sec in sectionsList) {
      String? title = sec['title'];
      String? context = sec['context']; // Extract context
      List<ParsedQuestion> questions = [];

      if (sec['questions'] != null) {
        for (var q in sec['questions']) {
          questions.add(
            ParsedQuestion(
              number: q['number']?.toString() ?? '',
              prompt: q['prompt']?.toString() ?? '',
              body:
                  (q['body'] as List?)?.map((e) => e.toString()).toList() ?? [],
              marks: q['marks']?.toString(),
              sourceLineIndices: [], // No source lines from Gemini
            ),
          );
        }
      }
      parsedSections.add(
        ParsedSection(title: title, context: context, questions: questions),
      );
    }
    return ParsedDocument(
      header: [],
      sections: parsedSections,
      name: docName, // Pass to constructor
    );
  }

  Future<String> transcribeAudio(String audioPath, String apiKey) async {
    final modelName = _cachedModelName ?? await _findValidModel(apiKey) ?? 'gemini-1.5-flash';
    _cachedModelName = modelName;
    final model = GenerativeModel(model: modelName, apiKey: apiKey);

    final audioBytes = await File(audioPath).readAsBytes();
    final prompt =
        "Transcribe the following audio exactly as spoken. Do not add any commentary or extra text.";

    try {
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(
            'audio/mp4',
            audioBytes,
          ), // Assuming standard format, Gemini handles most
        ]),
      ]);

      if (response.text == null) {
        throw Exception("Empty transcription from Gemini");
      }
      return response.text!;
    } catch (e) {
      debugPrint("Gemini Transcription Error: $e");
      rethrow;
    }
  }
}

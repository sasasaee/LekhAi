import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import '../models/paper_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiPaperService {
  static final GeminiPaperService _instance = GeminiPaperService._internal();
  factory GeminiPaperService() => _instance;
  GeminiPaperService._internal();

  static String? _cachedModelName;

  /// Processes multiple images in parallel and merges their sections
  /// into a single [ParsedDocument], sorted by question number.
  Future<ParsedDocument> processMultipleImages(
    List<String> imagePaths,
    String apiKey,
  ) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('imagePaths must not be empty');
    }
    if (imagePaths.length == 1) {
      return processImage(imagePaths.first, apiKey);
    }

    // Process all images concurrently
    final results = await Future.wait(
      imagePaths.map((path) => processImage(path, apiKey)),
    );

    // Collect all sections
    final mergedSections = <ParsedSection>[];
    for (final doc in results) {
      mergedSections.addAll(doc.sections);
    }

    // Sort sections by the minimum numeric question number they contain,
    // so that selecting images in any order still produces correct sequence.
    mergedSections.sort((a, b) {
      int minNum(ParsedSection s) {
        if (s.questions.isEmpty) return 999999;
        return s.questions
            .map((q) => int.tryParse(q.number ?? '') ?? 999999)
            .reduce((v, e) => v < e ? v : e);
      }

      return minNum(a).compareTo(minNum(b));
    });

    return ParsedDocument(
      header: results.first.header,
      sections: mergedSections,
      name: results.first.name,
    );
  }

  Future<ParsedDocument> processImage(String imagePath, String apiKey) async {
    final modelName = await _getModelName(apiKey);
    debugPrint("Gemini: Using model: $modelName");

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
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final models = json['models'] as List;

        final availableModels = models
            .map((m) {
              final name = m['name'].toString().replaceFirst('models/', '');
              final supportedMethods = m['supportedGenerationMethods'] as List?;
              return {
                'name': name,
                'supportsGenerate':
                    supportedMethods?.contains('generateContent') ?? false,
              };
            })
            .where((m) => m['supportsGenerate'] == true)
            .map((m) => m['name'] as String)
            .toList();

        debugPrint(
          "Gemini: Found ${availableModels.length} models: $availableModels",
        );

        // Prioritized list of stable models
        const prioritizedModels = [
          'gemini-2.5-flash',
          'gemini-1.5-flash',
          'gemini-2.0-flash-exp',
          'gemini-2.0-flash',
          'gemini-1.5-pro',
        ];

        for (final pModel in prioritizedModels) {
          if (availableModels.contains(pModel)) {
            debugPrint("Gemini: Selected prioritized model: $pModel");
            return pModel;
          }
        }

        if (availableModels.isNotEmpty) {
          debugPrint(
            "Gemini: Falling back to first available: ${availableModels.first}",
          );
          return availableModels.first;
        }
      } else {
        debugPrint(
          "Gemini: Failed to list models (${response.statusCode}): ${response.body}",
        );
      }
    } catch (e) {
      debugPrint("Gemini: Error listing models: $e");
    }
    return 'gemini-2.5-flash'; // Return a hard default
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

  /// Strips leading 'Q' or 'q' characters that Gemini may include in numbers.
  /// e.g. "Q9" → "9", "Q10" → "10", "1" → "1"
  String _normalizeNumber(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
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
              number: _normalizeNumber(q['number']?.toString() ?? ''),
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

  Future<String> transcribeAudio(
    String audioPath,
    String apiKey, {
    String? contextPrompt,
  }) async {
    final modelName = await _getModelName(apiKey);
    debugPrint("Gemini: Using model for transcription: $modelName");
    final model = GenerativeModel(model: modelName, apiKey: apiKey);

    final audioBytes = await File(audioPath).readAsBytes();
    String prompt =
        "Transcribe the following audio. Add appropriate punctuation and capitalization. Do not add any commentary or extra text.";
    if (contextPrompt != null && contextPrompt.isNotEmpty) {
      prompt += "\n\nCRITICAL INSTRUCTIONS:\n$contextPrompt";
    }

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

  Future<String> _getModelName(String apiKey) async {
    final envModel = dotenv.env['GEMINI_MODEL'];
    if (envModel != null && envModel.isNotEmpty) {
      return envModel;
    }
    if (_cachedModelName != null) {
      return _cachedModelName!;
    }
    _cachedModelName = await _findValidModel(apiKey);
    return _cachedModelName ?? 'gemini-2.5-flash';
  }
}

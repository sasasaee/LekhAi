import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import '../models/question_model.dart';

class GeminiQuestionService {
  Future<ParsedDocument> processImage(String imagePath, String apiKey) async {
    // 1. Find a valid model name dynamically
    final modelName = await _findValidModel(apiKey) ?? 'gemini-1.5-flash';
    print("GeminiService using model: $modelName");

    final model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );

    final imageBytes = await File(imagePath).readAsBytes();
    final prompt = _buildPrompt();

    try {
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes), // Assuming JPEG, but API is flexible
        ])
      ]);

      if (response.text == null) {
        throw Exception("Empty response from Gemini");
      }

      return _parseResponse(response.text!);
    } catch (e) {
      print("Gemini Processing Error: $e");
      rethrow;
    }
  }

  Future<String?> _findValidModel(String apiKey) async {
    try {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final models = json['models'] as List;
        
        String? bestMatch;
        
        for (final m in models) {
          final name = m['name'].toString(); // e.g. models/gemini-1.5-flash
          final supportedMethods = m['supportedGenerationMethods'] as List?;
          
          if (supportedMethods != null && supportedMethods.contains('generateContent')) {
             // Clean name
             final cleanName = name.replaceFirst('models/', '');
             
             // Prefer flash
             if (cleanName.contains('flash')) {
               // If we already have a flash match, maybe check for 'latest' or versions? 
               // For now, just taking the first 'flash' or updating if we find a '1.5-flash' specifically
               bestMatch = cleanName;
               if (cleanName == 'gemini-1.5-flash') return cleanName; // Perfect match
             }
             
             bestMatch ??= cleanName; // Fallback to any valid model
          }
        }
        return bestMatch;
      }
    } catch (e) {
      print("Error listing models: $e");
    }
    return null; // Fallback to default
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
    final cleanJson = jsonString.replaceAll(RegExp(r'^```json|```$'), '').trim();
    
    final Map<String, dynamic> data = jsonDecode(cleanJson);
    final sectionsList = data['sections'] as List;

    List<ParsedSection> parsedSections = [];

    for (var sec in sectionsList) {
      String? title = sec['title'];
      String? context = sec['context']; // Extract context
      List<ParsedQuestion> questions = [];
      
      if (sec['questions'] != null) {
        for (var q in sec['questions']) {
          questions.add(ParsedQuestion(
            number: q['number']?.toString() ?? '',
            prompt: q['prompt']?.toString() ?? '',
            body: (q['body'] as List?)?.map((e) => e.toString()).toList() ?? [],
            marks: q['marks']?.toString(),
            sourceLineIndices: [], // No source lines from Gemini
          ));
        }
      }
      parsedSections.add(ParsedSection(title: title, context: context, questions: questions));
    }
    return ParsedDocument(
      header: [], 
      sections: parsedSections,
    );
  }
}

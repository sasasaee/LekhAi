import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  // Access your API key as an environment variable
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null) {
    stderr.writeln(r'No $GEMINI_API_KEY environment variable setup');
    exit(1);
  }

  stdout.writeln("Querying API for available models...");
  String? validModelName;

  try {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
    );
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final models = json['models'] as List;
      stdout.writeln("Found ${models.length} models.");

      for (final m in models) {
        final name = m['name'].toString(); // e.g., models/gemini-1.5-flash
        final supportedMethods = m['supportedGenerationMethods'] as List?;

        // We need a model that supports 'generateContent'
        if (supportedMethods != null &&
            supportedMethods.contains('generateContent')) {
          // Prefer flash if available, otherwise take the first valid one
          if (validModelName == null || name.contains('flash')) {
            validModelName = name;
          }
        }
      }
    } else {
      stderr.writeln(
        "Failed to list models. Status: ${response.statusCode}, Body: ${response.body}",
      );
    }
  } catch (e) {
    stderr.writeln("Error listing models: $e");
  }

  if (validModelName == null) {
    stderr.writeln("No valid models found. Exiting.");
    return;
  }

  // Clean up model name from 'models/gemini-1.5-flash' to 'gemini-1.5-flash' if needed by SDK
  final cleanModelName = validModelName.replaceFirst('models/', '');
  stdout.writeln("Using model: $cleanModelName");

  final model = GenerativeModel(model: cleanModelName, apiKey: apiKey);

  final testCases = [
    "I am fond (a) — angling.",
    "(a) The bee is one of the busiest insects.",
    "turned (c) – a great",
    "Table | row | data",
  ];

  stdout.writeln("\nRunning Gemini Prototype for TTS Preprocessing...\n");

  for (final text in testCases) {
    stdout.writeln("Input: '$text'");
    try {
      final response = await model.generateContent([
        Content.text(_buildPrompt(text)),
      ]);
      stdout.writeln("Output: '${response.text?.trim()}'");
    } catch (e) {
      stderr.writeln("Error: $e");
    }
    stdout.writeln("---");
  }
}

String _buildPrompt(String text) {
  return """
You are a text preprocessor for a Text-to-Speech (TTS) engine.
Your goal is to make the text sound natural when read aloud, specifically handling exam question formats.

Rules:
1. If you see a fill-in-the-blank item like "(a) -", "(a) ____", or "- (a)", replace the dash/underscore with "... blank a ...".
2. If you see a list enumerator like "(a)" at the start of a sentence (without a blank), replace it with "... a ..." (just the letter with pauses).
3. If you see standalone blanks "____", replace with "... blank ...".
4. Replace vertical bars "|" with commas ",".
5. Keep the rest of the text mostly as is, but you can add commas for pauses where natural.

Input Text:
$text

Output Text (just the processed string):
""";
}

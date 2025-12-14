import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/question_model.dart';

class QuestionStorageService {
  static const String _keyDocs = 'parsed_documents';

  // Save a full segmented document locally
  Future<void> saveDocument(ParsedDocument doc) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> docs = prefs.getStringList(_keyDocs) ?? [];
    docs.add(jsonEncode({
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "createdAt": DateTime.now().toIso8601String(),
      "data": doc.toJson(),
    }));

    await prefs.setStringList(_keyDocs, docs);
  }

  // Load all saved documents
  Future<List<ParsedDocument>> getDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> docs = prefs.getStringList(_keyDocs) ?? [];

    return docs.map((e) {
      final decoded = jsonDecode(e);
      return ParsedDocument.fromJson(decoded['data']);
    }).toList();
  }

  // Delete all saved documents
  Future<void> clearDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDocs);
  }
}

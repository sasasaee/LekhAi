import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/paper_model.dart';

class PaperStorageService {
  static const String _keyDocs = 'parsed_documents';

  // Save or Update a full segmented document locally
  Future<void> saveDocument(ParsedDocument doc) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawDocs = prefs.getStringList(_keyDocs) ?? [];

    // Create the new entry JSON
    final newEntryJson = jsonEncode({
      "id": doc.id, // Ensure we store the ID at top level
      "createdAt": DateTime.now().toIso8601String(),
      "data": doc.toJson(),
    });

    List<String> updatedDocs = [];
    bool replaced = false;

    // Rebuild existing list, replacing match and skipping duplicates
    for (String raw in rawDocs) {
      try {
        final decoded = jsonDecode(raw);
        final innerId = decoded['data']?['id'];
        final wrapperId = decoded['id'];

        // Check for match
        if ((innerId != null && innerId == doc.id) ||
            (innerId == null && wrapperId == doc.id)) {
          if (!replaced) {
            updatedDocs.add(newEntryJson);
            replaced = true;
          } else {
            // Already replaced one instance, this is a duplicate -> remove it (skip)
            continue;
          }
        } else {
          updatedDocs.add(raw);
        }
      } catch (e) {
        // Corrupt entry, skip
      }
    }

    if (!replaced) {
      updatedDocs.add(newEntryJson);
    }

    await prefs.setStringList(_keyDocs, updatedDocs);
  }

  // Load all saved documents (with deduplication)
  Future<List<ParsedDocument>> getDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> docs = prefs.getStringList(_keyDocs) ?? [];

    final uniqueDocs = <String, ParsedDocument>{};
    final orderedDocs = <ParsedDocument>[];

    for (String raw in docs) {
      try {
        final decoded = jsonDecode(raw);
        // Pass the wrapper's 'id' as fallback for older documents
        final parsed = ParsedDocument.fromJson(
          decoded['data'],
          fallbackId: decoded['id'],
        );

        // Deduplicate: If we already have this ID, skip (or overwrite? usually keep first found or last?
        // simple map replace keeps last. list check keeps first.)
        // Let's keep the FIRST occurrence to preserve order in the list, but ignore subsequent duplicates.
        if (!uniqueDocs.containsKey(parsed.id)) {
          uniqueDocs[parsed.id] = parsed;
          orderedDocs.add(parsed);
        }
      } catch (e) {
        // ignore error
      }
    }

    return orderedDocs;
  }

  // Delete all saved documents
  Future<void> clearDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDocs);
  }
}

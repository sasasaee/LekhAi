import 'package:string_similarity/string_similarity.dart';

class StringUtils {
  // Common variations of the wake word
  static const List<String> wakeWordVariations = [
    "hey lekhai",
    "hey likhai",
    "he lekhai",
    "hey lekai",
    "a lekhai",
    "hai lekhai",
    "hey leekhai"
  ];

  static const List<String> stopCommandVariations = [
    "stop answering",
    "stop writing",
    "stop dictation",
    "pause writing",
    "pause dictation",
    "stop answer",
    "stop listening",
    "hey lekhai stop",
    "hey lekhai stop listening",
    "hey lekhai stop answering",
    "lekhai stop",
    "stop",
    "hey likhai stop",
    "finish",
  ];

  /// Strips wake words from the beginning and stop commands from the end
  /// using fuzzy string matching (Levenshtein similarity).
  static String stripWakeWordsAndCommands(String input) {
    String processed = input.trim();
    if (processed.isEmpty) return processed;

    // First do exact case-insensitive regex replacements for wake words anywhere
    // just to be completely safe against rogue "hey lekhai"s in the text.
    for (var wakeWord in wakeWordVariations) {
      processed = processed.replaceAll(RegExp(wakeWord, caseSensitive: false), "");
    }
    processed = processed.trim();

    // 1. Strip Wake Word from the beginning using fuzzy match (for misspellings missed by regex)
    final words = processed.split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      if (words.length >= 2) {
        String firstTwo = "${words[0]} ${words[1]}".toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
        for (var variation in wakeWordVariations) {
          if (firstTwo.similarityTo(variation) > 0.75) {
            processed = words.sublist(2).join(" ");
            break;
          }
        }
      }
      
      // Try first 1 word in case it got grouped (e.g. "heylekhai")
      if (words.isNotEmpty && processed == words.join(" ")) {
        String firstOne = words[0].toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
        for (var variation in wakeWordVariations) {
          if (firstOne.similarityTo(variation) > 0.8) { 
            processed = words.sublist(1).join(" ");
            break;
          }
        }
      }
    }

    List<String> endStripVariations = [...stopCommandVariations, ...wakeWordVariations];

    // 2. Strip Wake Word or Stop Command from the end using fuzzy match
    final processedWords = processed.split(RegExp(r'\s+'));
    
    // Check last 1 word (e.g., "stop" or "lekhai")
    if (processedWords.isNotEmpty) {
      String lastOne = processedWords.last.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
      if (lastOne.similarityTo("stop") > 0.75 || lastOne == "finish") {
         processed = processedWords.sublist(0, processedWords.length - 1).join(" ");
      }
    }

    // Re-split in case it changed
    final updatedWords = processed.split(RegExp(r'\s+'));
    
    // Check last 2 words
    if (updatedWords.length >= 2) {
      String lastTwo = "${updatedWords[updatedWords.length - 2]} ${updatedWords[updatedWords.length - 1]}".toLowerCase();
      lastTwo = lastTwo.replaceAll(RegExp(r'[^\w\s]'), '');
      
      for (var variation in endStripVariations) {
        if (lastTwo.similarityTo(variation) > 0.75) {
          processed = updatedWords.sublist(0, updatedWords.length - 2).join(" ");
          break;
        }
      }
    }

    // Re-split and check last 3 words
    final finalWords = processed.split(RegExp(r'\s+'));
    if (finalWords.length >= 3) {
      String lastThree = "${finalWords[finalWords.length - 3]} ${finalWords[finalWords.length - 2]} ${finalWords[finalWords.length - 1]}".toLowerCase();
      lastThree = lastThree.replaceAll(RegExp(r'[^\w\s]'), '');
      
      for (var variation in endStripVariations) {
        if (lastThree.similarityTo(variation) > 0.75) {
          processed = finalWords.sublist(0, finalWords.length - 3).join(" ");
          break;
        }
      }
    }

    // Remove any trailing punctuation
    processed = processed.trim();
    while (processed.endsWith(',') || processed.endsWith('.')) {
      processed = processed.substring(0, processed.length - 1).trim();
    }

    // Final sweeps
    if (processed.toLowerCase().endsWith(" stop")) {
      processed = processed.substring(0, processed.length - 5).trim();
    }
    for (var wakeWord in wakeWordVariations) {
      if (processed.toLowerCase().endsWith(" $wakeWord")) {
         processed = processed.substring(0, processed.length - (wakeWord.length + 1)).trim();
      }
    }

    return processed.trim();
  }

  /// Extracts digits from a string, parsing words like "one, two" to "1, 2".
  static String extractDigits(String input) {
    if (input.isEmpty) return input;
    
    // Basic word to digit mapping
    final Map<String, String> wordToDigit = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'oh': '0',
    };
    
    String processed = input.toLowerCase();
    wordToDigit.forEach((word, digit) {
      processed = processed.replaceAll(RegExp(r'\b' + word + r'\b'), digit);
    });
    
    // Extract only digits
    processed = processed.replaceAll(RegExp(r'[^0-9]'), '');
    return processed;
  }
}

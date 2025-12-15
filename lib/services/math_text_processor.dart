// services/math_text_processor.dart

class MathTextProcessor {
  // Detects if a line contains math symbols, fractions, or algebraic structure.
  static bool isMathLine(String line) {
    final hasMathSymbols = RegExp(r'[+\-×÷=<>≤≥≠√^°%‰]').hasMatch(line);
    final hasFraction = RegExp(r'\d+/\d+').hasMatch(line);

    if (hasFraction) return true;
    if (RegExp(r'[=<>≤≥≠√^°]').hasMatch(line)) return true;
    
    if (RegExp(r'[+\-×÷]').hasMatch(line)) {
        return RegExp(r'\d').hasMatch(line) || RegExp(r'\b[a-zA-Z]\b').hasMatch(line);
    }
    
    if (line.contains('%')) return true;

    return false;
  }

  // Converts math notation (fractions, exponents, operators) to spoken English.
  static String prepareForSpeech(String text) {
    String processed = text;

    processed = processed.replaceAll(RegExp(r'\s+'), ' ');

    // Fractions
    processed = processed.replaceAllMapped(
      RegExp(r'(\d+)\s*/\s*(\d+)'),
      (m) {
        final num = m[1]!;
        final den = m[2]!;
        if (den == "2") return "$num half ";
        if (den == "4") return "$num quarter ";
        return "$num over $den ";
      }
    );
    
    // Exponents
    processed = processed.replaceAllMapped(
      RegExp(r'([a-zA-Z\)])2(?![0-9])'), 
      (m) => "${m[1]} squared "
    );
    processed = processed.replaceAllMapped(
      RegExp(r'([a-zA-Z\)])3(?![0-9])'), 
      (m) => "${m[1]} cubed "
    );

    // Symbols & Operators
    processed = processed.replaceAll('√', ' square root of ');

    processed = processed.replaceAll('is less than', 'is less than');
    processed = processed.replaceAll('<=', ' is less than or equal to ');
    processed = processed.replaceAll('>=', ' is greater than or equal to ');
    processed = processed.replaceAll('<', ' is less than ');
    processed = processed.replaceAll('>', ' is greater than ');
    processed = processed.replaceAll('!=', ' is not equal to ');
    processed = processed.replaceAll('≠', ' is not equal to ');

    processed = processed.replaceAll('+', ' plus ');
    processed = processed.replaceAll('−', ' minus ');
    processed = processed.replaceAll('-', ' minus ');
    processed = processed.replaceAll('×', ' multiplied by ');
    processed = processed.replaceAll('*', ' multiplied by ');
    processed = processed.replaceAll('÷', ' divided by ');
    processed = processed.replaceAll('=', ' equals ');
    processed = processed.replaceAll('°', ' degrees ');
    processed = processed.replaceAll('%', ' percent ');

    return processed.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

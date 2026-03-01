import '../services/tts_service.dart';

/// Service that manages screen descriptions for blind-navigation accessibility.
///
/// - Tracks which screens have been visited (per session).
/// - On first visit, announces a full description of the screen content.
/// - On revisit, announces just the screen name.
/// - `describeScreen()` always reads the full description ("what's on my screen?").
class ScreenDescriptionService {
  // Singleton
  static final ScreenDescriptionService _instance =
      ScreenDescriptionService._internal();
  factory ScreenDescriptionService() => _instance;
  ScreenDescriptionService._internal();

  final Set<String> _visitedScreens = {};

  // ─── Full descriptions (first visit + "what's on my screen?") ───

  static const Map<String, String> _fullDescriptions = {
    'start':
        "Welcome to LekhAi, your intelligent study companion. Say 'Hey LekhAi' before every voice command. Say 'Start App' to begin.",
    'home':
        "Home Screen. You have three options: Take Exam, Read PDF, and Settings. "
        "Say 'go to' followed by where you want to go, or say 'what is on my screen' anytime for help.",
    'take_exam':
        "Take Exam screen. "
        "You can scan Papers, go to saved papers, or access settings."
        "Say 'go to' followed by where you want to go.",
    'saved_papers':
        "Saved Papers screen. Your saved documents are listed here. "
        "Say 'open paper' followed by a number to view one, or 'delete paper' followed by a number to remove it.",
    'settings':
        "Settings screen. You can adjust speech speed and volume, toggle haptic feedback, "
        "and enable or disable voice commands. Say 'reset' to restore defaults.",
    'exam_info':
        "Exam Setup screen. You need to set your name, student ID, and exam time before starting. "
        "Say 'set name', 'set ID', or 'set time' followed by the value. "
        "When ready, say 'start exam' to begin.",
    'answer_sheet':
        "Answer Sheet screen. You can read questions, write answers, and navigate between pages. "
        "Say 'read question' to hear the current question, 'start' to begin writing your answer, "
        "or 'next question' and 'previous question' to navigate.",
    'pdf_viewer':
        "PDF Viewer screen. ",
    'ocr':
        "OCR Processing screen. The scanned document is being processed. "
        "Once complete, you can save or rename the file.",
  };

  // ─── Short names (revisit announcements) ───

  static const Map<String, String> _shortNames = {
    'start': "Start screen.",
    'home': "Home Screen.",
    'take_exam': "Take Exam.",
    'saved_papers': "Saved Papers.",
    'settings': "Settings.",
    'exam_info': "Exam Setup.",
    'answer_sheet': "Paper Detail.",
    'pdf_viewer': "PDF Viewer.",
    'ocr': "OCR Processing.",
  };

  /// Called when entering a screen.
  /// First visit → full description. Revisit → short name only.
  void announceScreen(
    String screenId,
    TtsService tts, {
    String? dynamicDetail,
  }) {
    final isFirstVisit = !_visitedScreens.contains(screenId);
    _visitedScreens.add(screenId);

    if (isFirstVisit) {
      String desc = _fullDescriptions[screenId] ?? "Screen: $screenId.";
      if (dynamicDetail != null) desc = "$desc $dynamicDetail";
      tts.speak(desc);
    } else {
      String shortName = _shortNames[screenId] ?? screenId;
      if (dynamicDetail != null) shortName = "$shortName $dynamicDetail";
      tts.speak(shortName);
    }
  }

  /// Always reads the full description (for "what's on my screen?" command).
  void describeScreen(
    String screenId,
    TtsService tts, {
    String? dynamicDetail,
  }) {
    String desc =
        _fullDescriptions[screenId] ??
        "No description available for this screen.";
    if (dynamicDetail != null) desc = "$desc $dynamicDetail";
    tts.speak(desc);
  }

  /// Reset visit history (e.g. on app restart — already automatic since in-memory).
  void resetVisits() => _visitedScreens.clear();

  /// Check if a screen was visited.
  bool hasVisited(String screenId) => _visitedScreens.contains(screenId);
}

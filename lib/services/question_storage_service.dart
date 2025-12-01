import 'package:shared_preferences/shared_preferences.dart';

class QuestionStorageService {
  static const String _keyQuestions = 'questions';

  Future<void> saveQuestion(String question) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> questions = await getQuestions();
    questions.add(question);
    await prefs.setStringList(_keyQuestions, questions);
  }

  Future<List<String>> getQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyQuestions) ?? [];
  }

  Future<void> clearQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyQuestions);
  }
}

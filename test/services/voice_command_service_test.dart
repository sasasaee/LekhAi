import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lekhai/services/voice_command_service.dart';
import 'package:lekhai/services/tts_service.dart';
import 'package:lekhai/services/picovoice_service.dart';
import 'package:lekhai/services/paper_storage_service.dart';
import 'package:lekhai/services/gemini_paper_service.dart';
import 'package:lekhai/models/paper_model.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Manual Mocks

class MockTtsService extends Mock implements TtsService {
  String? lastSpoken;

  @override
  Future<void> speak(String text) async {
    lastSpoken = text;
  }

  @override
  Future<void> speakAndWait(String text) async {
    lastSpoken = text;
  }
}

class MockPicovoiceService extends Mock implements PicovoiceService {
  @override
  final ValueNotifier<PicovoiceState> stateNotifier = ValueNotifier(
    PicovoiceState.idle,
  );
}

class MockPaperStorageService extends Mock implements PaperStorageService {
  @override
  Future<List<ParsedDocument>> getDocuments() async {
    return [];
  }
}

class MockGeminiPaperService extends Mock implements GeminiPaperService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceCommandService voiceService;
  late MockTtsService mockTts;
  late MockPicovoiceService mockPicovoice;
  late MockPaperStorageService mockStorage;
  late MockGeminiPaperService mockGemini;

  setUp(() {
    mockTts = MockTtsService();
    mockPicovoice = MockPicovoiceService();
    mockStorage = MockPaperStorageService();
    mockGemini = MockGeminiPaperService();

    // We need to pass null for SharedPreferences to avoid errors in initSettings if not mocked,
    // but initSettings calls SharedPreferences.getInstance().
    // We can use SharedPreferences.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

    voiceService = VoiceCommandService(
      mockTts,
      mockPicovoice,
      geminiService: mockGemini,
      storageService: mockStorage,
    );
  });

  test(
    'VoiceCommandService broadcasts correct action for navigation home',
    () async {
      // Expect the stream to emit a specific value
      expectLater(
        voiceService.commandStream,
        emits(
          predicate<CommandResult>(
            (result) => result.action == VoiceAction.goToHome,
          ),
        ),
      );

      // Trigger the intent
      // Use the public executeIntent method (if it was public, but it is!).
      // Wait, let's verify if executeIntent is public.
      voiceService.executeIntent('navigation', {'destination': 'home'});
    },
  );

  test(
    'VoiceCommandService broadcasts correct action for set exam time',
    () async {
      expectLater(
        voiceService.commandStream,
        emits(
          predicate<CommandResult>(
            (result) =>
                result.action == VoiceAction.setExamTime &&
                result.payload == 45,
          ),
        ),
      );

      voiceService.executeIntent('formControl', {'minutes': '45'});
    },
  );

  test(
    'VoiceCommandService broadcasts correct action for settings control enable',
    () async {
      expectLater(
        voiceService.commandStream,
        emits(
          predicate<CommandResult>(
            (result) =>
                result.action == VoiceAction.enableFeature &&
                result.payload == 'haptic',
          ),
        ),
      );

      voiceService.executeIntent('settingsControl', {
        'feature': 'haptic',
        'state': 'on',
      });
    },
  );

  test('VoiceCommandService maps "paper X" to openPaper', () async {
    expectLater(
      voiceService.commandStream,
      emits(
        predicate<CommandResult>(
          (result) =>
              result.action == VoiceAction.openPaper && result.payload == 5,
        ),
      ),
    );

    voiceService.executeIntent('navigation', {
      'itemNumber': '5',
    }, 'Open paper 5');
  });

  test('VoiceCommandService maps "question X" to goToQuestion', () async {
    expectLater(
      voiceService.commandStream,
      emits(
        predicate<CommandResult>(
          (result) =>
              result.action == VoiceAction.goToQuestion && result.payload == 3,
        ),
      ),
    );

    voiceService.executeIntent('navigation', {
      'itemNumber': '3',
    }, 'Go to question 3');
  });

  test(
    'VoiceCommandService broadcasts correct action for PDF page navigation',
    () async {
      expectLater(
        voiceService.commandStream,
        emits(
          predicate<CommandResult>(
            (result) =>
                result.action == VoiceAction.goToPage && result.payload == 10,
          ),
        ),
      );

      voiceService.executeIntent('navigation', {'pageNumber': '10'});
    },
  );
}

import 'dart:async'; // Added
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';
import 'gemini_paper_service.dart';
import 'paper_storage_service.dart'; // Added
import '../pdf_viewer_screen.dart';
// import '../take_exam_screen.dart';
import '../ocr_screen.dart';
import '../paper_detail_screen.dart';
import '../widgets/accessible_widgets.dart';
import 'kiosk_service.dart'; // Added
import 'picovoice_service.dart';
import 'accessibility_service.dart'; // Added fix for missing class
import '../widgets/voice_alert_dialog.dart';

enum VoiceContext {
  global,
  ocr,
  savedPapers,
  settings,
  pdfViewer,
  takeExam,
  scanQuestions,
  confirmExamStart,
  paperDetail, // New context
  question, // New context
}

enum VoiceAction {
  goToSavedPapers,
  goToTakeExam,
  goToHome,
  goToSettings,
  goToQuestion,
  startDictation,
  goToReadPDF,
  viewPdf, // Added for post-exam dialog
  stopDictation,
  readQuestion,
  readAnswer,
  changeSpeed,
  goBack,
  submitExam,
  exitExam,
  // Editing Actions
  appendAnswer,
  overwriteAnswer,
  clearAnswer,
  readLastSentence,
  // New Context Specific Actions
  scanCamera,
  scanGallery,
  saveResult,
  nextPage,
  previousPage,
  useGemini,
  useLocalOcr,
  scanQuestions,
  openPaper, // Added Action for selecting item from list
  // Confirmation Actions
  confirmExamStart,
  cancelExamStart,
  // Settings Actions
  toggleHaptic,
  toggleVoiceCommands,
  deletePaper, // Added Action for deleting item
  increaseVolume,
  decreaseVolume,
  increaseSpeed,
  decreaseSpeed,
  // New Actions
  startApp,
  clearAllPapers,
  enterExamMode,
  submitForm,
  confirmAction,
  cancelAction,
  resetPreferences,
  pauseReading,
  resumeReading,
  restartReading,
  playAudioAnswer,
  toggleReadContext,
  // PDF Actions
  zoomIn,
  zoomOut,
  resetZoom,
  goToPage,
  // Feature Control
  enableFeature,
  disableFeature,
  // Form Control
  setStudentName,
  setStudentID,
  setExamTime,
  renameFile,

  // Scroll Control
  scrollUp,
  scrollDown,
  scrollToTop,
  scrollToBottom,

  // File Actions
  saveFile,
  convertFile,
  shareFile,
  search,

  // Status Queries (from main)
  checkTime,
  checkTotalQuestions,
  checkRemainingQuestions,
  unknown,
  // Dialog Actions
  skip,
  selectOption,
}

class CommandResult {
  final VoiceAction action;
  final dynamic payload;
  final dynamic
  payload2; // Added for extra params (e.g. feature name + state, or just use a Map payload)
  CommandResult(this.action, {this.payload, this.payload2});
}

// ... existing enum ...

class VoiceCommandService {
  final TtsService tts;
  final PicovoiceService picovoiceService;
  final GeminiPaperService _geminiService;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final PaperStorageService _storageService;
  bool _isScanDialogOpen = false;

  final StreamController<CommandResult> _commandStream =
      StreamController.broadcast();
  Stream<CommandResult> get commandStream => _commandStream.stream;

  void broadcastCommand(CommandResult result) {
    _commandStream.add(result);
  }

  VoiceCommandService(
    this.tts,
    this.picovoiceService, {
    GeminiPaperService? geminiService,
    PaperStorageService? storageService,
  }) : _geminiService = geminiService ?? GeminiPaperService(),
       _storageService = storageService ?? PaperStorageService() {
    _initSettings();
  }

  final ValueNotifier<double> volumeNotifier = ValueNotifier(0.7);
  final ValueNotifier<double> speedNotifier = ValueNotifier(1.0);

  Future<void> _initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    volumeNotifier.value = prefs.getDouble('volume') ?? 0.7;
    speedNotifier.value = prefs.getDouble('speed') ?? 1.0;
  }

  Future<void> _changeVolume(bool increase) async {
    volumeNotifier.value = (volumeNotifier.value + (increase ? 0.1 : -0.1))
        .clamp(0.0, 1.0);
    await tts.setVolume(volumeNotifier.value);
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('volume', volumeNotifier.value);
    tts.speak(
      "Volume ${increase ? 'increased' : 'decreased'} to ${(volumeNotifier.value * 100).toInt()} percent.",
    );
  }

  Future<void> _changeSpeed(bool increase) async {
    speedNotifier.value = (speedNotifier.value + (increase ? 0.25 : -0.25))
        .clamp(0.5, 2.0);
    await tts.setSpeed(speedNotifier.value * 0.5);
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('speed', speedNotifier.value);
    tts.speak(
      "Speed ${increase ? 'increased' : 'decreased'} to ${speedNotifier.value.toStringAsFixed(2)}.",
    );
  }

  CommandResult parse(
    String text, {
    VoiceContext context = VoiceContext.global,
  }) {
    debugPrint(
      "VoiceCommandService.parse called with text: '$text', context: $context",
    );
    text = text.toLowerCase();

    // --- CONTEXT SPECIFIC COMMANDS ---

    // Take Exam Choice Context
    if (context == VoiceContext.takeExam) {
      // "Scan Questions" triggers the process (showing options)
      if (text.contains("scan questions") ||
          text.contains("can questions") ||
          text.contains("scan")) {
        return CommandResult(VoiceAction.scanQuestions);
      }
      if (text.contains("gemini") ||
          text.contains("ai") ||
          text.contains("artificial intelligence")) {
        return CommandResult(VoiceAction.useGemini);
      }
      if (text.contains("local") ||
          text.contains("ocr") ||
          text.contains("standard")) {
        return CommandResult(VoiceAction.useLocalOcr);
      }

      // Removed "camera"/"gallery" shortcuts as requested, to enforce the flow.
    }
    // Scan Questions Context
    // if (context == VoiceContext.scanQuestions) {

    // }

    // Confirm Exam Start Context
    if (context == VoiceContext.confirmExamStart) {
      if (text.contains("start") ||
          text.contains("confirm") ||
          text.contains("yes")) {
        return CommandResult(VoiceAction.confirmExamStart);
      }
      if (text.contains("cancel") ||
          text.contains("stop") ||
          text.contains("no")) {
        return CommandResult(VoiceAction.cancelExamStart);
      }
    }

    // Paper Detail Context
    if (context == VoiceContext.paperDetail) {
      // "Add Page" / "Scan Page"
      if (text.contains("add page") ||
          text.contains("scan page") ||
          text.contains("add photo")) {
        return CommandResult(VoiceAction.scanQuestions);
      }

      // "Question X"
      final RegExp selectionRegex = RegExp(r"(question|number)\s+([a-z0-9]+)");
      final match = selectionRegex.firstMatch(text);
      if (match != null) {
        String rawNumber = match.group(2)!;
        int? index = int.tryParse(rawNumber);
        if (index == null) {
          const numberMap = {
            'one': 1,
            'two': 2,
            'three': 3,
            'four': 4,
            'five': 5,
            'six': 6,
            'seven': 7,
            'eight': 8,
            'nine': 9,
            'ten': 10,
          };
          index = numberMap[rawNumber];
        }
        if (index != null) {
          return CommandResult(VoiceAction.goToQuestion, payload: index);
        }
      }
    }

    // Single Question Context
    if (context == VoiceContext.question) {
      // ... Generic Navigation ...
      if (text.contains("next") || text.contains("next question")) {
        return CommandResult(VoiceAction.nextPage);
      }
      if (text.contains("previous") ||
          text.contains("previous question") ||
          text.contains("back")) {
        return CommandResult(VoiceAction.previousPage);
      }

      // ... Feature Toggle ...
      if (text.contains("play audio") ||
          text.contains("play answer") ||
          text.contains("listen") ||
          text.contains("play the answer")) {
        return CommandResult(VoiceAction.readAnswer);
      }
      if (text.contains("context") || text.contains("read context")) {
        return CommandResult(VoiceAction.toggleReadContext);
      }

      // ... Answer Dictation ...
      if (text.contains("start answer") ||
          text.contains("start") ||
          text.contains("answer question")) {
        return CommandResult(VoiceAction.startDictation);
      }
      if (text.contains("stop answer") ||
          text.contains("stop") ||
          text.contains("finish answer")) {
        return CommandResult(VoiceAction.stopDictation);
      }

      if (text.contains("pause")) {
        return CommandResult(VoiceAction.pauseReading);
      }

      // ... Status Queries ...
      if (text.contains("how many questions left") ||
          text.contains("questions left") ||
          text.contains("remaining questions")) {
        return CommandResult(VoiceAction.checkRemainingQuestions);
      }
      if (text.contains("how many questions") ||
          text.contains("total questions")) {
        return CommandResult(VoiceAction.checkTotalQuestions);
      }
      if (text.contains("how much time") ||
          text.contains("time left") ||
          text.contains("remaining time")) {
        return CommandResult(VoiceAction.checkTime);
      }

      // ... Direct Jump (New) ...
      final RegExp selectionRegex = RegExp(r"(question|number)\s+([a-z0-9]+)");
      final match = selectionRegex.firstMatch(text);
      if (match != null) {
        String rawNumber = match.group(2)!;
        int? index = int.tryParse(rawNumber);
        if (index == null) {
          const numberMap = {
            'one': 1,
            'two': 2,
            'three': 3,
            'four': 4,
            'five': 5,
            'six': 6,
            'seven': 7,
            'eight': 8,
            'nine': 9,
            'ten': 10,
          };
          index = numberMap[rawNumber];
        }
        if (index != null) {
          return CommandResult(VoiceAction.goToQuestion, payload: index);
        }
      }
    }

    // OCR / Take Exam Context
    if (context == VoiceContext.ocr) {
      if (text.contains("camera") ||
          text.contains("take photo") ||
          text.contains("capture")) {
        return CommandResult(VoiceAction.scanCamera);
      }
      if (text.contains("gallery") ||
          text.contains("pick image") ||
          text.contains("choose photo")) {
        return CommandResult(VoiceAction.scanGallery);
      }
      if (text.contains("save") || text.contains("save result")) {
        return CommandResult(VoiceAction.saveResult);
      }
      if (text.contains("enter exam mode") || text.contains("start exam")) {
        return CommandResult(VoiceAction.enterExamMode);
      }
    }

    // Saved Papers Context
    if (context == VoiceContext.savedPapers) {
      debugPrint("Saved Papers Context Parsing: '$text'");

      if (text.contains("clear all") ||
          text.contains("delete all") ||
          text.contains("remove all")) {
        return CommandResult(VoiceAction.clearAllPapers);
      }

      // Parsing for DELETE commands (Check first!)
      final RegExp deleteRegex = RegExp(
        r"(delete|remove)\s+(paper|question|scan|number)\s+([a-z0-9]+)",
      );
      final deleteMatch = deleteRegex.firstMatch(text);
      if (deleteMatch != null) {
        String rawNumber = deleteMatch.group(3)!;
        debugPrint("DELETE MATCH FOUND: rawNumber='$rawNumber'");
        int? index = int.tryParse(rawNumber);

        if (index == null) {
          const numberMap = {
            'one': 1,
            'two': 2,
            'three': 3,
            'four': 4,
            'five': 5,
            'six': 6,
            'seven': 7,
            'eight': 8,
            'nine': 9,
            'ten': 10,
          };
          index = numberMap[rawNumber];
        }

        if (index != null) {
          return CommandResult(VoiceAction.deletePaper, payload: index);
        }
      }

      // Matches "question 1", "paper two", "scan 3", "number four"
      // Added [a-z0-9]+ to capture "one", "two" etc.
      final RegExp selectionRegex = RegExp(
        r"(question|paper|scan|number)\s+([a-z0-9]+)",
      );
      final match = selectionRegex.firstMatch(text);
      if (match != null) {
        String rawNumber = match.group(2)!;
        debugPrint("MATCH FOUND: rawNumber='$rawNumber'");
        int? index = int.tryParse(rawNumber); // Try parsing digit

        if (index == null) {
          // Try parsing word
          const numberMap = {
            'one': 1,
            'two': 2,
            'three': 3,
            'four': 4,
            'five': 5,
            'six': 6,
            'seven': 7,
            'eight': 8,
            'nine': 9,
            'ten': 10,
          };
          index = numberMap[rawNumber];
        }

        debugPrint("PARSED INDEX: $index");

        if (index != null) {
          return CommandResult(VoiceAction.openPaper, payload: index);
        }
      } else {
        debugPrint("NO MATCH for regex in Saved Papers");
      }
    }

    // Settings Context
    if (context == VoiceContext.settings) {
      if (text.contains("save")) {
        return CommandResult(VoiceAction.saveResult);
      }
      if (text.contains("haptic") || text.contains("vibration")) {
        return CommandResult(VoiceAction.toggleHaptic);
      }

      // Speed
      if (text.contains("speed up") ||
          text.contains("increase speed") ||
          text.contains("faster")) {
        return CommandResult(VoiceAction.increaseSpeed);
      }
      if (text.contains("speed down") ||
          text.contains("decrease speed") ||
          text.contains("slower")) {
        return CommandResult(VoiceAction.decreaseSpeed);
      }

      // Volume
      if (text.contains("volume up") ||
          text.contains("increase volume") ||
          text.contains("louder")) {
        return CommandResult(VoiceAction.increaseVolume);
      }
      if (text.contains("volume down") ||
          text.contains("decrease volume") ||
          text.contains("quieter")) {
        return CommandResult(VoiceAction.decreaseVolume);
      }

      // Toggle Voice Commands
      if (text.contains("voice command") ||
          text.contains("mute") ||
          text.contains("unmute")) {
        return CommandResult(VoiceAction.toggleVoiceCommands);
      }

      if (text.contains("previous page") ||
          text.contains("previous") ||
          text.contains("back page")) {
        return CommandResult(VoiceAction.previousPage);
      }
      if (text.contains("reset") || text.contains("default")) {
        return CommandResult(VoiceAction.resetPreferences);
      }
    }

    // PDF Viewer Context
    if (context == VoiceContext.pdfViewer) {
      if (text.contains("next page") || text.contains("next")) {
        return CommandResult(VoiceAction.nextPage);
      }
      if (text.contains("previous page") ||
          text.contains("previous") ||
          text.contains("back page")) {
        return CommandResult(VoiceAction.previousPage);
      }
      if (text.contains("pause")) {
        return CommandResult(VoiceAction.pauseReading);
      }
      if (text.contains("resume") ||
          text.contains("continue") ||
          text.contains("play")) {
        return CommandResult(VoiceAction.resumeReading);
      }
      if (text.contains("restart") || text.contains("replay")) {
        return CommandResult(VoiceAction.restartReading);
      }
      if (text.contains("stop")) {
        return CommandResult(VoiceAction.stopDictation);
      }
    }

    // --- GLOBAL COMMANDS (Fallback) ---

    // Exam
    if (text.contains("take exam") ||
        text.contains("start exam") ||
        text.contains("open exam")) {
      return CommandResult(VoiceAction.goToTakeExam);
    }

    // Home
    if (text.contains("go home") ||
        text.contains("home screen") ||
        text.contains("main menu")) {
      return CommandResult(VoiceAction.goToHome);
    }

    // Settings
    if (text.contains("settings") ||
        text.contains("preferences") ||
        text.contains("options") ||
        text.contains("setting")) {
      return CommandResult(VoiceAction.goToSettings);
    }

    // Saved Papers
    if (text.contains("saved papers") ||
        text.contains("saved questions") ||
        text.contains("my questions") ||
        text.contains("go back to papers")) {
      return CommandResult(VoiceAction.goToSavedPapers);
    }

    // Read PDF
    if (text.contains("read pdf") ||
        text.contains("open pdf") ||
        text.contains("read document")) {
      return CommandResult(VoiceAction.goToReadPDF);
    }

    if (text.contains("go back")) return CommandResult(VoiceAction.goBack);

    if (text.contains("append") || text.contains("add to answer")) {
      return CommandResult(VoiceAction.appendAnswer);
    }
    if (text.contains("write the answer") || text.contains("write answer")) {
      return CommandResult(VoiceAction.appendAnswer);
    }
    if (text.contains("overwrite") || text.contains("replace answer")) {
      return CommandResult(VoiceAction.overwriteAnswer);
    }
    if (text.contains("clear answer") || text.contains("delete answer")) {
      return CommandResult(VoiceAction.clearAnswer);
    }
    if (text.contains("read last") || text.contains("last sentence")) {
      return CommandResult(VoiceAction.readLastSentence);
    }

    if (text.contains("start dictation") || text.contains("start writing")) {
      return CommandResult(VoiceAction.startDictation);
    }
    if (text.contains("stop dictation") ||
        text.contains("stop answering") ||
        text.contains("stop writing") ||
        text.contains("pause writing") ||
        text.contains("pause dictation")) {
      return CommandResult(VoiceAction.stopDictation);
    }
    if (text.contains("read question") || text.contains("repeat question")) {
      return CommandResult(VoiceAction.readQuestion);
    }
    if (text.contains("read my answer") || text.contains("read answer")) {
      return CommandResult(VoiceAction.readAnswer);
    }
    if (text.contains("change speed") ||
        text.contains("faster") ||
        text.contains("slower")) {
      return CommandResult(VoiceAction.changeSpeed);
    }

    if (text.contains("get started") || text.contains("start app")) {
      return CommandResult(VoiceAction.startApp);
    }

    if (text.contains("confirm")) {
      return CommandResult(VoiceAction.confirmAction);
    }
    if (text.contains("cancel")) return CommandResult(VoiceAction.cancelAction);

    if (text.contains("student name") || text.contains("my name")) {
      return CommandResult(VoiceAction.setStudentName);
    }
    if (text.contains("student id") || text.contains("my id")) {
      return CommandResult(VoiceAction.setStudentID);
    }
    if (text.contains("exam time") || text.contains("set time")) {
      return CommandResult(VoiceAction.setExamTime);
    }
    if (text.contains("rename") || text.contains("change filename")) {
      return CommandResult(VoiceAction.renameFile);
    }

    if (text.contains("zoom in")) return CommandResult(VoiceAction.zoomIn);
    if (text.contains("zoom out")) return CommandResult(VoiceAction.zoomOut);
    if (text.contains("reset zoom")) {
      return CommandResult(VoiceAction.resetZoom);
    }

    // Settings
    if (text.contains("haptic")) {
      if (text.contains("on") || text.contains("enable")) {
        return CommandResult(VoiceAction.enableFeature, payload: 'haptics');
      }
      if (text.contains("off") || text.contains("disable")) {
        return CommandResult(VoiceAction.disableFeature, payload: 'haptics');
      }
    }
    if (text.contains("voice command")) {
      if (text.contains("on") || text.contains("enable")) {
        return CommandResult(
          VoiceAction.enableFeature,
          payload: 'voice commands',
        );
      }
      if (text.contains("off") || text.contains("disable")) {
        return CommandResult(
          VoiceAction.disableFeature,
          payload: 'voice commands',
        );
      }
    }

    return CommandResult(VoiceAction.unknown);
  }

  Future<void> performGlobalNavigation(CommandResult result) async {
    // NOTE: Do NOT add to _commandStream here. It causes an infinite loop
    // if screens call this method from their stream listener.

    final context = navigatorKey.currentContext;

    // Kiosk Mode Security Check
    if (KioskService().isKioskActive) {
      // Allowed actions in Kiosk Mode (if any) could be checked here.
      // Generally, we want to BLOCK leaving the screen.
      bool isRestricted =
          result.action == VoiceAction.goToHome ||
          result.action == VoiceAction.goToSettings ||
          result.action == VoiceAction.goToSavedPapers ||
          result.action == VoiceAction.goToTakeExam ||
          result.action == VoiceAction.goToReadPDF; // Add others if needed

      if (isRestricted) {
        tts.speak("Exam execution in progress. Navigation is locked.");
        return;
      }
    }

    debugPrint("VoiceCommandService - Global Navigation: ${result.action}");
    switch (result.action) {
      case VoiceAction.goBack:
        final context = navigatorKey.currentContext;
        if (context != null && KioskService().isKioskActive) {
          final routeName = ModalRoute.of(context)?.settings.name;
          if (routeName == '/paper_detail' || routeName == '/question_detail') {
            tts.speak("Navigation is locked during exam.");
            return;
          }
        }

        final canPop = await navigatorKey.currentState?.maybePop() ?? false;
        if (!canPop) {
          tts.speak("You are already on the home screen.");
        }
        break;
      case VoiceAction.submitExam:
        // Do not re-broadcast. If we are here, no active screen handled it locally
        // or a background screen delegated it.
        tts.speak("Cannot submit exam from this screen.");
        break;
      case VoiceAction.previousPage:
        // Generic fallback for previous page
        final canPop = await navigatorKey.currentState?.maybePop() ?? false;
        if (!canPop) {
          tts.speak("No previous page found.");
        }
        break;
      case VoiceAction.goToSavedPapers:
        await navigatorKey.currentState?.pushNamed('/saved_papers');
        break;
      case VoiceAction.enterExamMode: // Added as fallback
      case VoiceAction.goToTakeExam:
        await navigatorKey.currentState?.pushNamed('/take_exam');
        break;
      case VoiceAction.goToHome:
      case VoiceAction.startApp:
        // Try to get current route name
        final context = navigatorKey.currentContext;
        String? currentRoute;
        if (context != null) {
          try {
            currentRoute = ModalRoute.of(context)?.settings.name;
          } catch (_) {}
        }

        // If we are likely on an intro screen or we can't determine route, try to push replacement
        if (currentRoute == null ||
            currentRoute == '/' ||
            currentRoute == '/start') {
          navigatorKey.currentState?.pushReplacementNamed('/home');
        } else {
          // If already deep, pop until home
          navigatorKey.currentState?.popUntil((route) {
            return route.settings.name == '/home' || route.isFirst;
          });
        }
        break;
      case VoiceAction.goToSettings:
        await navigatorKey.currentState?.pushNamed('/settings');
        break;
      case VoiceAction.openPaper:
        if (result.payload is int) {
          await _handleOpenPaper(result.payload as int);
        }
        break;
      case VoiceAction.goToReadPDF:
        await _pickAndOpenPdf();
        break;
      case VoiceAction.scrollToTop:
        // Handled by screens
        break;
      case VoiceAction.scrollToBottom:
        // Handled by screens
        break;
      case VoiceAction.saveFile:
        tts.speak("Saving file.");
        break;
      case VoiceAction.convertFile:
        tts.speak("Converting file.");
        break;
      case VoiceAction.scanQuestions:
        await _handleScan();
        break;
      case VoiceAction.useGemini:
        await _handleGeminiSelection();
        break;
      case VoiceAction.useLocalOcr:
        _navigateToOcr();
        break;
      case VoiceAction.increaseVolume:
        await _changeVolume(true);
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Volume Increased"),
              duration: const Duration(milliseconds: 1000),
            ),
          );
        }
        break;
      case VoiceAction.decreaseVolume:
        await _changeVolume(false);
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Volume Decreased"),
              duration: const Duration(milliseconds: 1000),
            ),
          );
        }
        break;
      case VoiceAction.increaseSpeed:
        await _changeSpeed(true);
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Speed Increased"),
              duration: const Duration(milliseconds: 1000),
            ),
          );
        }
        break;
      case VoiceAction.decreaseSpeed:
        await _changeSpeed(false);
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Speed Decreased"),
              duration: const Duration(milliseconds: 1000),
            ),
          );
        }
        break;
      case VoiceAction.enableFeature:
        final feat = result.payload.toString().toLowerCase();
        if (feat.contains('haptic')) {
          AccessibilityService().setEnabled(true);
          AccessibilityService().trigger(AccessibilityEvent.action);
          tts.speak("Haptic feedback enabled.");
        } else if (feat.contains('single tap')) {
          AccessibilityService().setOneTapAnnounce(true);
          tts.speak("Single tap to announce enabled.");
        } else if (feat.contains('voice command')) {
          final sp = await SharedPreferences.getInstance();
          await sp.setBool('voice_commands_enabled', true);
          await picovoiceService.setEnabled(true);
          tts.speak("Voice commands enabled.");
        }
        break;
      case VoiceAction.disableFeature:
        final featOff = result.payload.toString().toLowerCase();
        if (featOff.contains('haptic')) {
          AccessibilityService().setEnabled(false);
          tts.speak("Haptic feedback disabled.");
        } else if (featOff.contains('single tap')) {
          AccessibilityService().setOneTapAnnounce(false);
          tts.speak("Single tap to announce disabled.");
        } else if (featOff.contains('voice command')) {
          final sp = await SharedPreferences.getInstance();
          await sp.setBool('voice_commands_enabled', false);
          await picovoiceService.setEnabled(false);
          tts.speak("Voice commands disabled.");
        }
        break;
      default:
        // Unknown global action
        break;
    }
  }

  int? _parseNumber(String raw) {
    // Rhino now handles number parsing via $pv.TwoDigitInteger
    return int.tryParse(raw);
  }

  bool intentStringContains(String intent, List<String> substrs) {
    for (var s in substrs) {
      if (intent.toLowerCase().contains(s.toLowerCase())) return true;
    }
    return false;
  }

  void executeIntent(
    String intent,
    Map<String, String>? slots, [
    String? speech,
  ]) {
    VoiceAction action = VoiceAction.unknown;
    dynamic payload;
    dynamic payload2;

    debugPrint(
      "VoiceCommandService: Received Intent: '$intent', Slots: $slots",
    );

    // Helper to get normalized slot value
    String? getVal(List<String> keys) {
      if (slots == null) return null;
      for (var k in keys) {
        if (slots.containsKey(k)) return slots[k]?.toLowerCase().trim();
      }
      // Fallback: Check if any key contains the slot name (fuzzy match for Rhino slot keys)
      for (var k in keys) {
        for (var slotKey in slots.keys) {
          if (slotKey.toLowerCase().contains(k.toLowerCase())) {
            return slots[slotKey]?.toLowerCase().trim();
          }
        }
      }
      return null;
    }

    switch (intent) {
      // --- USER YAML INTENTS ---
      // --- USER YAML INTENTS ---
      case 'navigation':
        final dest = getVal(['destination']);
        final itemNumStr = getVal(['itemNumber']);
        final pageNumStr = getVal(['pageNumber']);

        if (dest != null) {
          if (intentStringContains(dest, ['home', 'main menu'])) {
            action = VoiceAction.goToHome;
          } else if (intentStringContains(dest, ['exam', 'take'])) {
            action = VoiceAction.goToTakeExam;
          } else if (intentStringContains(dest, ['saved', 'cards'])) {
            action = VoiceAction.goToSavedPapers;
          } else if (intentStringContains(dest, ['pdf', 'read'])) {
            action = VoiceAction.goToReadPDF;
          } else if (intentStringContains(dest, ['setting', 'preference'])) {
            action = VoiceAction.goToSettings;
          } else if (intentStringContains(dest, ['scan'])) {
            action = VoiceAction.scanQuestions;
          } else if (intentStringContains(dest, ['back', 'previous'])) {
            action = VoiceAction.goBack;
          } else if (intentStringContains(dest, [
            'start',
            'app',
            'get started',
          ])) {
            action = VoiceAction.startApp;
          }
        }

        if (itemNumStr != null) {
          int? num = int.tryParse(itemNumStr);
          if (num != null) {
            final lowerSpeech = speech?.toLowerCase() ?? "";
            // Use speech context to distinguish paper vs question
            if (lowerSpeech.contains('paper') ||
                lowerSpeech.contains('file') ||
                (dest != null &&
                    intentStringContains(dest, ['paper', 'file']))) {
              action = VoiceAction.openPaper;
              payload = num;
            } else {
              // Default to question navigation
              action = VoiceAction.goToQuestion;
              payload = num;
            }
          }
        } else if (pageNumStr != null) {
          int? p = int.tryParse(pageNumStr);
          if (p != null) {
            action = VoiceAction.goToPage;
            payload = p;
          }
        }
        break;

      // --- NEW INTENTS ---
      case 'pdfControl':
        final pdfAct = getVal(['pdf_action']);
        if (pdfAct == 'zoom in') action = VoiceAction.zoomIn;
        if (pdfAct == 'zoom out') action = VoiceAction.zoomOut;
        if (pdfAct == 'reset zoom') action = VoiceAction.resetZoom;

        final pageNumStr = getVal(['number']);
        if (pageNumStr != null) {
          int? p = _parseNumber(pageNumStr);
          if (p != null) {
            action = VoiceAction.goToPage;
            payload = p;
          }
        }
        break;

      case 'settingsControl':
        final feat = getVal(['feature']);
        final state = getVal(['state', 'status', 'action', 'turn']);

        if (feat != null) {
          if (state == 'off' || state == 'disable' || state == 'stop') {
            action = VoiceAction.disableFeature;
          } else {
            action = VoiceAction.enableFeature;
          }
          payload = feat;
        }
        break;

      case 'formControl':
        final minutesStr = getVal(['minutes']);
        final lowerSpeech = speech?.toLowerCase() ?? "";

        if (minutesStr != null) {
          int? m = int.tryParse(minutesStr);
          if (m != null) {
            action = VoiceAction.setExamTime;
            payload = m;
            tts.speak("Setting exam time to $m minutes.");
          }
        } else if (lowerSpeech.contains('name')) {
          // Heuristic: "set name John Doe" -> "John Doe"
          // "my name is John" -> "John"
          final parts = lowerSpeech.split('name');
          if (parts.length > 1) {
            String extracted = parts[1].trim();
            // Remove common filler words
            extracted = extracted
                .replaceFirst(RegExp(r'^(is|set|to|as)\s+'), '')
                .trim();
            if (extracted.isNotEmpty) {
              action = VoiceAction.setStudentName;
              payload = extracted;
            }
          }
          if (action == VoiceAction.unknown) {
            action = VoiceAction.setStudentName;
            payload = null; // Trigger prompt
          }
        } else if (lowerSpeech.contains('id')) {
          // Heuristic: "set student id 123" -> "123"
          final parts = lowerSpeech.split('id');
          if (parts.length > 1) {
            String extracted = parts[1].trim();
            extracted = extracted
                .replaceFirst(RegExp(r'^(is|set|to|as)\s+'), '')
                .trim();
            if (extracted.isNotEmpty) {
              action = VoiceAction.setStudentID;
              payload = extracted;
            }
          }
          if (action == VoiceAction.unknown) {
            action = VoiceAction.setStudentID;
            payload = null; // Trigger prompt
          }
        } else {
          // Fallback for other form commands
          action = VoiceAction.unknown;
          tts.speak("Please use manual input for form fields.");
        }
        break;

      case 'AppControl':
        final actionSlot = getVal(['action']);
        final scrollDir = getVal(['scroll_direction']);

        if (actionSlot != null) {
          if (actionSlot == 'start') {
            action = VoiceAction
                .appendAnswer; // Mapping 'start' to 'appendAnswer' (dictation)
          } else if (actionSlot == 'stop')
            action = VoiceAction.stopDictation;
          else if (actionSlot == 'pause')
            action = VoiceAction.pauseReading;
          else if (actionSlot == 'resume')
            action = VoiceAction.resumeReading;
          else if (actionSlot == 'clear answer')
            action = VoiceAction.clearAnswer;
          else if (actionSlot == 'read answer')
            action = VoiceAction.readAnswer;
          else if (actionSlot == 'edit answer')
            action = VoiceAction.appendAnswer;
          else if (actionSlot == 'open question')
            action = VoiceAction.goToQuestion;
          else if (actionSlot == 'open paper' || actionSlot == 'select paper')
            action = VoiceAction.openPaper;
          else if (actionSlot == 'exit' ||
              actionSlot == 'close' ||
              actionSlot == 'stop app')
            action = VoiceAction.goBack;
          else if (actionSlot == 'start app')
            action = VoiceAction.startApp;
          else if (actionSlot == 'confirm')
            action = VoiceAction.confirmAction;
          else if (actionSlot == 'cancel')
            action = VoiceAction.cancelAction;
          else if (actionSlot == 'skip' || actionSlot == 'skip naming')
            action = VoiceAction.skip;
          else if (actionSlot == 'save')
            action = VoiceAction
                .saveResult; // Map 'save' to saveResult for dialogs/forms
          else if (actionSlot == 'save to downloads' ||
              actionSlot == 'download')
            action = VoiceAction.saveFile;
        } else if (scrollDir != null) {
          if (scrollDir == 'up') {
            action = VoiceAction.scrollUp;
          } else if (scrollDir == 'down')
            action = VoiceAction.scrollDown;
          else if (scrollDir == 'top')
            action = VoiceAction.scrollToTop;
          else if (scrollDir == 'bottom')
            action = VoiceAction.scrollToBottom;
        }
        break;

      case 'ChangePages':
        final dir = getVal(['direction']);
        if (dir == 'next' || dir == 'forward') action = VoiceAction.nextPage;
        if (dir == 'previous' || dir == 'back') {
          action = VoiceAction.previousPage;
        }
        break;

      case 'readContent':
        final ra = getVal(['readAction']);
        if (ra == 'stop' || ra == 'pause') {
          // If we are in 'question' context, 'stop' usually means stop dictation
          // Global navigation will handle the fallback if no screen captures it.
          action = VoiceAction.stopDictation;
        } else if (ra == 'resume')
          action = VoiceAction.resumeReading;
        else if (ra == 'start')
          action = VoiceAction
              .appendAnswer; // Map 'start answering' etc to dictation
        else if (ra == 'restart')
          action = VoiceAction.restartReading;
        else {
          // Case for "Read question", "Read this page", "Repeat question"
          action = VoiceAction.readQuestion;
        }
        break;

      case 'examControl':
        final e = getVal(['exam']);
        if (e == 'start exam' || e == 'start') {
          action = VoiceAction.enterExamMode;
        } else if (e == 'finish exam' ||
            e == 'submit exam' ||
            e == 'finish' ||
            e == 'end' ||
            e == 'end exam' ||
            e == 'stop exam') {
          action = VoiceAction.submitExam;
        } else if (e == 'exit exam') {
          action = VoiceAction.exitExam;
        } else if (e == 'cancel exam' || e == 'stop') {
          action = VoiceAction.goBack;
        } else if (e == 'confirm') {
          action = VoiceAction.confirmExamStart;
        }
        break;

      case 'capture':
        final src = getVal(['source']);
        final choice = getVal(['scan_choice']);
        if (src == 'camera' || src == 'photo') {
          action = VoiceAction.scanCamera;
        } else if (src == 'gallery' || src == 'image')
          action = VoiceAction.scanGallery;
        else if (choice == 'gemini')
          action = VoiceAction.useGemini;
        else if (choice == 'local')
          action = VoiceAction.useLocalOcr;
        else
          action = VoiceAction.scanQuestions;
        break;

      case 'process':
        final act = getVal(['processAction']);
        if (act != null) {
          if (act.contains('increase volume') || act.contains('turn up')) {
            action = VoiceAction.increaseVolume;
          } else if (act.contains('decrease volume') ||
              act.contains('turn down'))
            action = VoiceAction.decreaseVolume;
          else if (act.contains('increase speed'))
            action = VoiceAction.increaseSpeed;
          else if (act.contains('decrease speed'))
            action = VoiceAction.decreaseSpeed;
          else if (act.contains('enter exam mode'))
            action = VoiceAction.enterExamMode;
          else if (act == 'convert') {
            action = VoiceAction.convertFile;
          } else if (act == 'save') {
            action = VoiceAction.saveFile;
          } else if (act == 'reset') {
            action = VoiceAction.resetPreferences;
          } else if (act.contains('view pdf') || act.contains('open pdf')) {
            action = VoiceAction.viewPdf;
          }
        }
        break;

      case 'deleteItem':
        final itemNumStr = getVal(['itemNumber']);
        if (itemNumStr != null) {
          int? num = int.tryParse(itemNumStr);
          if (num != null) {
            action = VoiceAction.deletePaper;
            payload = num;
          }
        }
        break;

      case 'clearHistory':
        action = VoiceAction.clearAllPapers;
        break;

      case 'shareContent':
        action = VoiceAction.shareFile;
        break;

      case 'searchContent':
        action = VoiceAction.search;
        break;

      case 'dialogControl':
        final resp = getVal(['dialog_response']);
        final optionNumStr = getVal(['optionNumber']);

        if (resp != null) {
          if (['yes', 'sure', 'okay'].contains(resp)) {
            action = VoiceAction.confirmAction;
          } else if (['no'].contains(resp)) {
            action = VoiceAction.cancelAction;
          }
        }

        if (optionNumStr != null) {
          int? opt = int.tryParse(optionNumStr);
          if (opt != null) {
            action = VoiceAction.selectOption;
            payload = opt;
          }
        }
        break;

      // --- GLOBAL FALLBACKS ---
      case 'stop':
        // If no context caught it, default to pause reading
        action = VoiceAction.stopDictation;
        break;

      default:
        // Try fuzzy matching all slots if no specific intent matched above
        if (slots != null && action == VoiceAction.unknown) {
          for (var val in slots.values) {
            final v = val.toLowerCase();
            if (v.contains('home')) action = VoiceAction.goToHome;
            if (v.contains('setting')) action = VoiceAction.goToSettings;
            if (v.contains('exam')) action = VoiceAction.goToTakeExam;
            if (v.contains('back') ||
                v.contains('exit') ||
                v.contains('close')) {
              action = VoiceAction.goBack;
            }
            if (v.contains('finish') ||
                v.contains('submit') ||
                v.contains('end')) {
              action = VoiceAction.submitExam;
            }
          }
        }
        break;
    }

    if (intent == 'formControl') {
      // Check for time slots first
      final hourStr = getVal(['hour']);
      final minuteStr = getVal(['minute', 'minutes']); // Handle both keys
      final itemStr = getVal(
        ['item'],
      ); // 'formItem' slot mapped to 'item' in YAML regex? No, just use getVal with 'item'

      if (hourStr != null || minuteStr != null) {
        int totalMinutes = 0;
        if (hourStr != null) {
          totalMinutes += (int.tryParse(hourStr) ?? 0) * 60;
        }
        if (minuteStr != null) {
          totalMinutes += int.tryParse(minuteStr) ?? 0;
        }

        if (totalMinutes > 0) {
          action = VoiceAction.setExamTime;
          payload = totalMinutes;
        }
      } else if (itemStr != null) {
        // Handle student name / ID from 'formItem' slot
        if (itemStr.contains('name')) {
          action = VoiceAction.setStudentName;
        } else if (itemStr.contains('id')) {
          action = VoiceAction.setStudentID;
        } else if (itemStr.contains('filename') || itemStr.contains('file')) {
          action = VoiceAction.renameFile;
        }
      }

      // Fallback if no slots found
      if (action == VoiceAction.unknown && speech != null) {
        // ... (keep speech fallback if needed, or remove)
        final lowerSpeech = speech.toLowerCase();
        if (lowerSpeech.contains('name')) {
          action = VoiceAction.setStudentName;
        } else if (lowerSpeech.contains('id') ||
            lowerSpeech.contains('identifier')) {
          action = VoiceAction.setStudentID;
        }
      }
    }

    if (action != VoiceAction.unknown) {
      final result = CommandResult(
        action,
        payload: payload,
        payload2: payload2,
      );
      // Broadcast to UI. Screens will handle or delegate back to performGlobalNavigation.
      _commandStream.add(result);

      // Fallback: If no screen is listening (e.g. transition state), execute global logic directly.
      if (!_commandStream.hasListener) {
        debugPrint(
          "VoiceCommandService: No listeners found. Executing global fallback immediately.",
        );
        performGlobalNavigation(result);
      }
    } else {
      tts.speak("I didn't understand that command.");
    }
  }

  Future<void> _handleOpenPaper(int targetIndex) async {
    // 1-based index from voice -> 0-based for list
    final actualIndex = targetIndex - 1;
    if (actualIndex < 0) {
      if (tts.isSpeaking) await tts.stop();
      tts.speak("Invalid number.");
      return;
    }

    try {
      if (tts.isSpeaking) await tts.stop();
      tts.speak("Checking papers...");

      final storage = PaperStorageService(); // Import required
      final docs = await storage.getDocuments();
      // Papers are displayed reversed in SavedPapers screen: newest first.
      // So index 0 matches the LAST element of the stored list.
      // actually, QuestionsScreen does: _papers = docs.reversed.toList();
      // So "Paper 1" (index 0) corresponds to docs.last.

      final reversedDocs = docs.reversed.toList();

      if (actualIndex < reversedDocs.length) {
        final doc = reversedDocs[actualIndex];
        tts.speak("Opening paper $targetIndex.");

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PaperDetailScreen(
              document: doc,
              ttsService: tts,
              voiceService: this,
              picovoiceService: picovoiceService,
              // accessibilityService is not available here, passed as null or we could inject it
              timestamp: DateTime.now().toString(),
            ),
          ),
        );
      } else {
        tts.speak("Paper $targetIndex not found.");
      }
    } catch (e) {
      debugPrint("Error opening paper via voice: $e");
      tts.speak("Could not open paper.");
    }
  }

  Future<void> _handleScan() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');
    final context = navigatorKey.currentContext;

    if (context == null || !context.mounted) return;

    _isScanDialogOpen = true;
    showDialog(
      context: context,
      builder: (ctx) => VoiceAlertDialog(
        title: const Text('Scan Options'),
        voiceService: this,
        content: const Text("Choose your preferred scanning method."),
        onSelectOption: (option) {
          Navigator.pop(ctx);
          if (option == 1) {
            // Gemini
            if (apiKey != null && apiKey.isNotEmpty) {
              _processGeminiFlow(apiKey);
            } else {
              tts.speak("Gemini API Key missing.");
            }
          } else if (option == 2) {
            // Local
            _navigateToOcr();
          }
        },
        onCancel: () {
          Navigator.pop(ctx);
        },
        actions: [
          AccessibleTextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (apiKey != null && apiKey.isNotEmpty) {
                _processGeminiFlow(apiKey);
              } else {
                tts.speak(
                  "Gemini API Key missing. Please set it in preferences.",
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Gemini API Key missing. Please set in Preferences.",
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text("Use Gemini AI"),
          ),
          AccessibleTextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToOcr();
            },
            child: const Text("Use Local OCR"),
          ),
        ],
      ),
    ).then((_) => _isScanDialogOpen = false); // Reset flag when dialog closes
  }

  Future<void> _handleGeminiSelection() async {
    // If specifically selecting Gemini via voice, close the dialog if it's open
    if (_isScanDialogOpen) {
      navigatorKey.currentState?.pop();
      // The pop will trigger the .then() above, setting _isScanDialogOpen = false
    }

    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key');
    if (apiKey != null && apiKey.isNotEmpty) {
      tts.speak("Selecting Gemini AI.");
      _processGeminiFlow(apiKey);
    } else {
      tts.speak("Gemini API Key missing. Please set it in preferences.");
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Gemini API Key missing. Please set in Preferences."),
          ),
        );
      }
    }
  }

  Future<void> _processGeminiFlow(String apiKey) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Cancellation flag
    bool isCancelled = false;

    if (context.mounted) {
      // Show blocking progress dialog with Cancel button
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Processing Paper"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text("Asking Gemini to analyze..."),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                isCancelled = true;
                Navigator.pop(ctx); // Close dialog
              },
              child: const Text("Cancel"),
            ),
          ],
        ),
      );
    } else {
      return;
    }

    try {
      // We pass the cancellation check inside? No, Gemini service is future-based.
      // We wait for it, then check flag. Ideally we could cancel the request,
      // but standard http/dio futures are hard to cancel without CancelToken.
      // For now, we just ignore the result if cancelled.

      final doc = await _geminiService.processImage(image.path, apiKey);

      // Close the Progress Dialog if it's still open (and not cancelled via button which closes it)
      // Actually, if we are here, the dialog is still open unless cancelled.
      if (!isCancelled) {
        if (context.mounted) Navigator.pop(context); // Close Progress Dialog
      } else {
        // Was cancelled, just return
        return;
      }

      if (isCancelled || !context.mounted) return;

      // Ask for Rename
      // Using VoiceAlertDialog
      String? paperName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final TextEditingController nameController = TextEditingController(
            text: doc.name,
          );
          return VoiceAlertDialog(
            title: const Text("Name this Paper"),
            voiceService: this,
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "e.g. Physics Midterm",
                labelText: "Paper Name",
              ),
            ),
            onConfirm: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, nameController.text.trim());
              } else {
                Navigator.pop(ctx, null);
              }
            },
            onSkip: () => Navigator.pop(ctx, null),
            onCancel: () => Navigator.pop(ctx, null),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null), // Skip/Default
                child: const Text("Skip"),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, nameController.text.trim());
                  }
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      );

      if (paperName != null && paperName.isNotEmpty) {
        doc.name = paperName;
      } else {
        doc.name =
            "Scanned Doc ${DateTime.now().hour}:${DateTime.now().minute}";
      }

      // Auto-save the document
      await _storageService.saveDocument(doc);
      tts.speak("Saved as ${doc.name}");

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => PaperDetailScreen(
            document: doc,
            ttsService: tts,
            voiceService: this,
            picovoiceService: picovoiceService,
            timestamp: DateTime.now().toString(),
          ),
        ),
      );
    } catch (e) {
      if (!isCancelled && context.mounted) {
        Navigator.pop(context); // Close dialog on error
      }
      if (!isCancelled && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateToOcr() {
    // If specifically selecting OCR via voice, close the dialog if it's open
    if (_isScanDialogOpen) {
      navigatorKey.currentState?.pop();
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => OcrScreen(
          ttsService: tts,
          voiceService: this,
          picovoiceService: picovoiceService,
        ),
      ),
    );
  }

  Future<void> _pickAndOpenPdf() async {
    try {
      tts.speak("Please select a PDF file.");
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(
              path: path,
              ttsService: tts,
              voiceService: this,
              picovoiceService: picovoiceService,
            ),
          ),
        );
      } else {
        tts.speak("No file selected.");
      }
    } catch (e) {
      debugPrint("Error picking PDF: $e");
      tts.speak("Sorry, I couldn't open the file picker.");
    }
  }
}

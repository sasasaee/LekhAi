import 'dart:async'; // Added
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Added
import 'gemini_paper_service.dart';
import 'paper_storage_service.dart'; // Added
import '../pdf_viewer_screen.dart';
import '../take_exam_screen.dart'; // Uncommented
import '../ocr_screen.dart';
import '../answer_sheet_screen.dart';
import '../widgets/accessible_widgets.dart';
import 'kiosk_service.dart'; // Added
import 'picovoice_service.dart';
import 'accessibility_service.dart'; // Added fix for missing class
import '../widgets/voice_alert_dialog.dart';
import '../widgets/paper_name_dialog.dart'; // Added
import 'screen_description_service.dart'; // Added

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
  undo,
  redo,
  deleteLastWord,
  deleteLastSentence,
  deleteLastLine,
  deleteLastParagraph,
  newParagraph,
  uppercaseLastWord,
  capitalizeLastWord,
  lowercaseLastWord,
  goToStart,
  goToEnd,
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
  checkQuestionStatus,
  help,
  readLastWord,
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

  // File/Document Actions
  saveFile,
  convertFile,
  shareFile,
  search,
  sharePdf,
  savePdfToDownloads,

  // Status Queries (from main)
  checkTime,
  checkTotalQuestions,
  checkRemainingQuestions,
  unknown,
  // Dialog Actions
  skip,
  selectOption,
  confirmExit,
  cancelExam,
  retry,
  // Screen Reader
  describeScreen,
  readContext,
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
        return CommandResult(VoiceAction.playAudioAnswer);
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
    if (text.contains("scroll up")) return CommandResult(VoiceAction.scrollUp);
    if (text.contains("scroll down"))
      return CommandResult(VoiceAction.scrollDown);
    if (text.contains("scroll to top") || text.contains("scroll top")) {
      return CommandResult(VoiceAction.scrollToTop);
    }
    if (text.contains("scroll to bottom") || text.contains("scroll bottom")) {
      return CommandResult(VoiceAction.scrollToBottom);
    }

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

    if (text.contains("start dictation") ||
        text.contains("start writing") ||
        text.contains("start answer")) {
      return CommandResult(VoiceAction.startDictation);
    }
    if (text.contains("stop dictation") ||
        text.contains("stop answering") ||
        text.contains("stop writing") ||
        text.contains("pause writing") ||
        text.contains("pause dictation") ||
        text.contains("stop answer")) {
      return CommandResult(VoiceAction.stopDictation);
    }
    if (text.contains("read question") || text.contains("repeat question")) {
      return CommandResult(VoiceAction.readQuestion);
    }
    if (text.contains("play audio") ||
        text.contains("play answer") ||
        text.contains("listen")) {
      return CommandResult(VoiceAction.playAudioAnswer);
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

    if (text.contains("confirm") ||
        text.contains("yes") ||
        text.contains("correct")) {
      return CommandResult(VoiceAction.confirmAction);
    }
    if (text.contains("cancel") ||
        text.contains("no") ||
        text.contains("retry"))
      return CommandResult(VoiceAction.cancelAction);

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
      case VoiceAction.resetPreferences:
        await _resetPreferences();
        break;
      case VoiceAction.saveResult:
        // Already auto-saved to SharedPreferences in _changeVolume/_changeSpeed
        tts.speak("Settings saved.");
        break;
      case VoiceAction.describeScreen:
        // Determine current screen from route
        final ctx = navigatorKey.currentContext;
        String screenId = 'home';
        if (ctx != null) {
          final routeName = ModalRoute.of(ctx)?.settings.name;
          if (routeName == '/home' || routeName == null)
            screenId = 'home';
          else if (routeName == '/take_exam')
            screenId = 'take_exam';
          else if (routeName == '/saved_papers')
            screenId = 'saved_papers';
          else if (routeName == '/settings')
            screenId = 'settings';
          else if (routeName == '/start')
            screenId = 'start';
          else if (routeName == '/paper_detail')
            screenId = 'paper_detail';
          else if (routeName == '/exam_info')
            screenId = 'exam_info';
          else if (routeName == '/pdf_viewer')
            screenId = 'pdf_viewer';
        }
        ScreenDescriptionService().describeScreen(screenId, tts);
        break;
      default:
        // Unknown global action
        break;
    }
  }

  Future<void> _resetPreferences() async {
    volumeNotifier.value = 0.7;
    speedNotifier.value = 1.0;
    await tts.setVolume(0.7);
    await tts.setSpeed(0.5); // 1.0 displayed = 0.5 internal
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('volume', 0.7);
    await sp.setDouble('speed', 1.0);
    tts.speak("Preferences reset to defaults.");

    // Sync UI if listeners are attached
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preferences Reset"),
          duration: Duration(seconds: 1),
        ),
      );
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
        final itemType = getVal(['itemType']);
        final itemNumStr = getVal(['itemNumber']);
        final pageNumStr = getVal(['pageNumber']);
        final lowerSpeech = speech?.toLowerCase() ?? "";

        if (dest != null) {
          if (dest == 'home')
            action = VoiceAction.goToHome;
          else if (dest == 'saved papers' || dest == 'saved_papers')
            action = VoiceAction.goToSavedPapers;
          else if (dest == 'take exam' || dest == 'take_exam')
            action = VoiceAction.goToTakeExam;
          else if (dest == 'settings' || dest == 'preferences')
            action = VoiceAction.goToSettings;
          else if (dest == 'read p d f' || dest == 'read_pdf')
            action = VoiceAction.goToReadPDF;
          else if (dest == 'scan paper' ||
              dest == 'scan questions' ||
              dest == 'scan_paper' ||
              dest == 'scan_questions')
            action = VoiceAction.scanQuestions;
          else if (dest == 'back')
            action = VoiceAction.goBack;
        } else if (itemNumStr != null) {
          int? num = int.tryParse(itemNumStr);
          if (num != null) {
            // Check itemType slot first, then fallback to speech context
            if (itemType != null &&
                (itemType == 'paper' ||
                    itemType == 'file' ||
                    itemType == 'document')) {
              action = VoiceAction.openPaper;
              payload = num;
            } else if (lowerSpeech.contains('paper') ||
                lowerSpeech.contains('file')) {
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
        } else if (lowerSpeech.contains('get started')) {
          action = VoiceAction.startApp;
        } else if (lowerSpeech.contains('summary') ||
            lowerSpeech.contains('back to list')) {
          action = VoiceAction.goBack;
        } else if (lowerSpeech.contains('next') ||
            lowerSpeech.contains('forward')) {
          action = VoiceAction.nextPage;
        } else if (lowerSpeech.contains('previous') ||
            lowerSpeech.contains('back')) {
          action = VoiceAction.previousPage;
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
        final lowerSpeech = speech?.toLowerCase() ?? "";

        if (feat != null) {
          if (state == 'off' ||
              state == 'disable' ||
              state == 'stop' ||
              lowerSpeech.contains('off') ||
              lowerSpeech.contains('disable')) {
            action = VoiceAction.disableFeature;
          } else if (state == 'on' ||
              state == 'enable' ||
              lowerSpeech.contains('on') ||
              lowerSpeech.contains('enable')) {
            action = VoiceAction.enableFeature;
          } else {
            // No explicit state provided, use toggle if available
            if (feat.contains('haptic')) {
              action = VoiceAction.toggleHaptic;
            } else if (feat.contains('voice command')) {
              action = VoiceAction.toggleVoiceCommands;
            } else {
              action = VoiceAction.enableFeature; // Default fallback
            }
          }
          payload = feat;

          if (feat.contains('context')) {
            action = VoiceAction.toggleReadContext;
            if (state == 'off' ||
                state == 'disable' ||
                lowerSpeech.contains('off') ||
                lowerSpeech.contains('disable')) {
              payload = false;
            } else if (state == 'on' ||
                state == 'enable' ||
                lowerSpeech.contains('on') ||
                lowerSpeech.contains('enable')) {
              payload = true;
            } else {
              payload = null; // Triggers toggle in UI
            }
          }
        } else if (state != null || lowerSpeech.isNotEmpty) {
          final lower = (state ?? lowerSpeech).toLowerCase();
          if (lower.contains('reset')) {
            action = VoiceAction.resetPreferences;
          } else if (lower.contains('save')) {
            action = VoiceAction.saveResult;
          }
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
        final scrollSlot = getVal([
          'scroll',
          'scroll_action',
          'scroll_direction',
          'scrollAction',
        ]);
        final actionSlot = getVal(['action']);

        if (scrollSlot != null) {
          if (scrollSlot.contains('up') || scrollSlot == 'scroll up') {
            action = VoiceAction.scrollUp;
          } else if (scrollSlot.contains('down') || scrollSlot == 'scroll down')
            action = VoiceAction.scrollDown;
          else if (scrollSlot.contains('top'))
            action = VoiceAction.scrollToTop;
          else if (scrollSlot.contains('bottom'))
            action = VoiceAction.scrollToBottom;
        } else if (actionSlot != null) {
          if (actionSlot == 'start') {
            final lowerSpeech = speech?.toLowerCase() ?? "";
            if (lowerSpeech.contains('app') ||
                lowerSpeech.contains('get started')) {
              action = VoiceAction.startApp;
            } else {
              action = VoiceAction
                  .appendAnswer; // Mapping 'start' to 'appendAnswer' (dictation)
            }
          } else if (actionSlot == 'stop')
            action = VoiceAction.stopDictation;
          else if (actionSlot == 'pause')
            action = VoiceAction.pauseReading;
          else if (actionSlot == 'resume')
            action = VoiceAction.resumeReading;
          else if (actionSlot == 'clear answer')
            action = VoiceAction.clearAnswer;
          else if (actionSlot == 'undo')
            action = VoiceAction.undo;
          else if (actionSlot == 'redo')
            action = VoiceAction.redo;
          else if (actionSlot == 'uppercase')
            action = VoiceAction.uppercaseLastWord;
          else if (actionSlot == 'capitalize')
            action = VoiceAction.capitalizeLastWord;
          else if (actionSlot == 'lowercase')
            action = VoiceAction.lowercaseLastWord;
          else if (actionSlot == 'new paragraph')
            action = VoiceAction.newParagraph;
          else if (actionSlot == 'read answer')
            action = VoiceAction.readAnswer;
          else if (actionSlot == 'edit answer' ||
              actionSlot == 'modify' ||
              actionSlot == 'append')
            action = VoiceAction.appendAnswer;
          else if (actionSlot == 'rewrite' ||
              actionSlot == 'overwrite' ||
              actionSlot == 'replace')
            action = VoiceAction.overwriteAnswer;
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
          else if (actionSlot == 'confirm' || actionSlot == 'submit')
            action = VoiceAction.confirmAction;
          else if (actionSlot == 'cancel')
            action = VoiceAction.cancelAction;
          else if (actionSlot == 'skip' || actionSlot == 'skip naming')
            action = VoiceAction.skip;
          else if (actionSlot == 'save')
            action = VoiceAction
                .saveResult; // Map 'save' to saveResult for dialogs/forms
          else if (actionSlot == 'save to downloads' ||
              actionSlot == 'save to download' ||
              actionSlot == 'download')
            action = VoiceAction
                .savePdfToDownloads; // Standardize to savePdfToDownloads
          else if (actionSlot.contains('screen'))
            action = VoiceAction.describeScreen;
          else if (actionSlot == 'go back' || actionSlot == 'return')
            action = VoiceAction.goBack;
          else if (actionSlot == 'read context')
            action = VoiceAction.readContext;
          else if (actionSlot == 'view pdf' || actionSlot == 'view p d f')
            action = VoiceAction.viewPdf;
          else if (actionSlot == 'share pdf' || actionSlot == 'share p d f')
            action = VoiceAction.sharePdf;
        }
        break;

      case 'ChangePages':
        final dir = getVal(['direction']);
        final dirAct = getVal(['direction_action']);

        String directionStr = (dir ?? dirAct ?? '').toLowerCase();

        // Also check speech fallback if slots are missing due to loose pronunciation
        if (directionStr.isEmpty && speech != null) {
          directionStr = speech.toLowerCase();
        }

        if (directionStr.contains('next') || directionStr.contains('forward')) {
          action = VoiceAction.nextPage;
        } else if (directionStr.contains('previous') ||
            directionStr.contains('back')) {
          action = VoiceAction.previousPage;
        }
        break;

      case 'readContent':
        final ra = getVal(['readAction']);
        if (ra == 'stop' || ra == 'pause') {
          action = VoiceAction.stopDictation;
        } else if (ra == 'resume') {
          action = VoiceAction.resumeReading;
        } else if (ra == 'start') {
          action = VoiceAction.appendAnswer;
        } else if (ra == 'restart') {
          action = VoiceAction.restartReading;
        } else {
          final target = getVal(['read_target']);
          final lowerSpeech = speech?.toLowerCase() ?? "";

          if (target == 'answer' ||
              target == 'my answer' ||
              target == 'what I wrote' ||
              (lowerSpeech.contains('answer') &&
                  !lowerSpeech.contains('clear') &&
                  !lowerSpeech.contains('erase') &&
                  !lowerSpeech.contains('play')) ||
              lowerSpeech.contains('wrote')) {
            action = VoiceAction.readAnswer;
          } else if (lowerSpeech.contains('play audio') ||
              lowerSpeech.contains('play answer') ||
              lowerSpeech.contains('listen')) {
            action = VoiceAction.playAudioAnswer;
          } else if (target == 'this page' ||
              lowerSpeech.contains('this page')) {
            action = VoiceAction.readQuestion;
          } else if (target == 'context' || lowerSpeech.contains('context')) {
            action = VoiceAction.readContext;
          } else if (target == 'last sentence' ||
              lowerSpeech.contains('last sentence')) {
            action = VoiceAction.readLastSentence;
          } else if (target == 'last word' ||
              lowerSpeech.contains('last word')) {
            action = VoiceAction.readLastWord;
          } else if (target == 'question') {
            action = VoiceAction.readQuestion;
          } else {
            // Literal "play audio" or "read answer" with no slots
            // In Rhino, 'play audio' might result in readContent intent with no slots.
            action = VoiceAction.playAudioAnswer;
          }
          final itemNumStr = getVal(['itemNumber']);
          if (itemNumStr != null) {
            int? num = int.tryParse(itemNumStr);
            if (num != null) {
              action = VoiceAction.goToQuestion;
              payload = num;
              payload2 =
                  true; // Use payload2 as a flag to "read after navigating"
            }
          } else if (lowerSpeech.contains('next') ||
              lowerSpeech.contains('forward')) {
            action = VoiceAction.nextPage;
          } else if (lowerSpeech.contains('previous') ||
              lowerSpeech.contains('back')) {
            action = VoiceAction.previousPage;
          }
        }
        break;

      case 'examControl':
        final e = getVal(['exam']);
        final lowerSpeech = speech?.toLowerCase() ?? "";

        if (e != null) {
          if (e == 'start exam' || e == 'start') {
            action = VoiceAction
                .confirmExamStart; // Or enterExamMode? usually confirmed first
          } else if (e.contains('finish') ||
              e.contains('submit') ||
              e.contains('end')) {
            action = VoiceAction.submitExam;
          } else if (e.contains('exit')) {
            action = VoiceAction.goBack;
          } else if (e.contains('cancel')) {
            action = VoiceAction.cancelExam; // Or goBack
          } else if (e.contains('confirm exit')) {
            action = VoiceAction.confirmExit;
          } else if (e.contains('confirm')) {
            action = VoiceAction.confirmExamStart;
          }
        } else {
          // No slots found for examControl intent
          // Heuristic: Rhino 'confirm exit' usually has no slots
          action = VoiceAction.confirmExit;
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
          } else if (act == 'save' ||
              act == 'save to downloads' ||
              act == 'save to download') {
            action = VoiceAction.savePdfToDownloads;
          } else if (act == 'reset') {
            action = VoiceAction.resetPreferences;
          } else if (act.contains('view pdf') ||
              act.contains('view p d f') ||
              act.contains('open pdf')) {
            action = VoiceAction.viewPdf;
          } else if (act.contains('share pdf') || act.contains('share p d f')) {
            action = VoiceAction.sharePdf;
          }
        }
        break;

      case 'EditingControl':
        final unit = getVal(['edit_unit']);
        final pos = getVal(['text_position']);
        final lowerSpeech = speech?.toLowerCase() ?? "";

        if (lowerSpeech.contains('undo')) {
          action = VoiceAction.undo;
        } else if (lowerSpeech.contains('redo')) {
          action = VoiceAction.redo;
        } else if (lowerSpeech.contains('clear answer') ||
            lowerSpeech.contains('erase answer') ||
            lowerSpeech.contains('remove answer') ||
            lowerSpeech.contains('discard answer')) {
          action = VoiceAction.clearAnswer;
        } else if (lowerSpeech.contains('new paragraph')) {
          action = VoiceAction.newParagraph;
        } else if (lowerSpeech.contains('uppercase')) {
          action = VoiceAction.uppercaseLastWord;
        } else if (lowerSpeech.contains('capitalize')) {
          action = VoiceAction.capitalizeLastWord;
        } else if (lowerSpeech.contains('lowercase')) {
          action = VoiceAction.lowercaseLastWord;
        } else if (unit != null) {
          if (unit == 'word') action = VoiceAction.deleteLastWord;
          if (unit == 'sentence') action = VoiceAction.deleteLastSentence;
          if (unit == 'line') action = VoiceAction.deleteLastLine;
          if (unit == 'paragraph') action = VoiceAction.deleteLastParagraph;
        } else if (pos != null) {
          if (pos == 'start' || pos == 'beginning' || pos == 'top')
            action = VoiceAction.goToStart;
          if (pos == 'end' || pos == 'bottom') action = VoiceAction.goToEnd;
        } else {
          // Fallback for speech if slots missed
          if (lowerSpeech.contains('delete') ||
              lowerSpeech.contains('remove') ||
              lowerSpeech.contains('clear') ||
              lowerSpeech.contains('erase')) {
            if (lowerSpeech.contains('word'))
              action = VoiceAction.deleteLastWord;
            else if (lowerSpeech.contains('sentence'))
              action = VoiceAction.deleteLastSentence;
            else if (lowerSpeech.contains('paragraph'))
              action = VoiceAction.deleteLastParagraph;
            else if (lowerSpeech.contains('answer'))
              action = VoiceAction.clearAnswer;
            else
              action = VoiceAction.deleteLastWord; // Default
          } else if (lowerSpeech.contains('undo')) {
            action = VoiceAction.undo;
          } else if (lowerSpeech.contains('redo')) {
            action = VoiceAction.redo;
          } else if (lowerSpeech.contains('new paragraph')) {
            action = VoiceAction.newParagraph;
          } else if (lowerSpeech.contains('uppercase')) {
            action = VoiceAction.uppercaseLastWord;
          } else if (lowerSpeech.contains('capitalize')) {
            action = VoiceAction.capitalizeLastWord;
          } else if (lowerSpeech.contains('lowercase')) {
            action = VoiceAction.lowercaseLastWord;
          } else if (lowerSpeech.contains('go to')) {
            if (lowerSpeech.contains('start') ||
                lowerSpeech.contains('beginning'))
              action = VoiceAction.goToStart;
            else if (lowerSpeech.contains('end') ||
                lowerSpeech.contains('bottom'))
              action = VoiceAction.goToEnd;
          }
        }

        // If we caught the EditingControl intent but no action determined via slots/speech,
        // it means Rhino matched a slotless rule like 'undo' or 'redo' while speech fallback is null.
        if (action == VoiceAction.unknown) {
          debugPrint(
            "VoiceCommandService: EditingControl intent matched but no slots or speech data to disambiguate.",
          );
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
          } else if (['no', 'retry', 'discard'].contains(resp)) {
            action = VoiceAction.retry;
          } else if (['cancel'].contains(resp)) {
            action = VoiceAction.cancelAction;
          } else if (['view pdf', 'view p d f'].contains(resp)) {
            action = VoiceAction.viewPdf;
          } else if (['share pdf', 'share p d f', 'share'].contains(resp)) {
            action = VoiceAction.sharePdf;
          } else if ([
            'save to downloads',
            'save to download',
            'save',
          ].contains(resp)) {
            action = VoiceAction.savePdfToDownloads;
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

      case 'questionStatus':
        action = VoiceAction.checkQuestionStatus;
        break;

      case 'helpQuery':
        action = VoiceAction.help;
        break;

      case 'examProgress':
        final state = getVal(['state', 'progress_state']);
        if (state != null) {
          if (state == 'remaining' || state == 'left') {
            action = VoiceAction.checkRemainingQuestions;
          } else if (state == 'answered' ||
              state == 'completed' ||
              state == 'done') {
            // Usually we announce "X answered out of Y total" for all these queries.
            action = VoiceAction.checkRemainingQuestions;
          } else if (state == 'total') {
            action = VoiceAction.checkTotalQuestions;
          } else if (state.contains('time')) {
            // "time has passed", "time passed", "time remaining"
            action = VoiceAction.checkTime;
          }
        } else {
          // Default to general progress
          action = VoiceAction.checkTotalQuestions;
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
            builder: (_) => AnswerSheetScreen(
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
    final String? apiKey = dotenv.env['GEMINI_API_KEY'];
    final context = navigatorKey.currentContext;

    if (context == null || !context.mounted) return;

    _isScanDialogOpen = true;
    showDialog(
      context: context,
      builder: (ctx) => VoiceAlertDialog(
        title: const Text('Scan Options'),
        voiceService: this,
        ttsService: tts,
        voiceDescription:
            "Scan Options. Say 'use Gemini' for AI scanning, or 'use local' for offline OCR.",
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

    final String? apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey != null && apiKey.isNotEmpty) {
      tts.speak("Selecting Gemini AI.");
      _processGeminiFlow(apiKey);
    } else {
      tts.speak("Gemini API Key missing. Please set it in your dotenv file.");
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Gemini API Key missing. Please set in .env file."),
          ),
        );
      }
    }
  }

  Future<void> _processGeminiFlow(String apiKey) async {
    // Use FilePicker for reliable multi-select on all Android OEMs
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result == null || result.files.isEmpty) return;

    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();

    if (paths.isEmpty) return;

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
              Text(
                paths.length == 1
                    ? "Asking Gemini to analyze..."
                    : "Asking Gemini to analyze ${paths.length} images...",
              ),
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
      final doc = await _geminiService.processMultipleImages(paths, apiKey);

      // Close the Progress Dialog
      if (!isCancelled) {
        if (context.mounted) Navigator.pop(context);
      } else {
        return;
      }

      if (isCancelled || !context.mounted) return;

      // Announce the generated name and ask for confirmation
      tts.speak(
        "Paper named ${doc.name}. Say 'Confirm' to save, or dictate a new name.",
      );

      // Ask for Name via voice-enabled dialog
      String? paperName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PaperNameDialog(
          initialName: doc.name ?? '',
          ttsService: tts,
          picovoiceService: picovoiceService,
          voiceService: this,
        ),
      );

      if (paperName != null && paperName.isNotEmpty) {
        doc.name = paperName;
      } else {
        doc.name =
            "Scanned Doc ${DateTime.now().hour}:${DateTime.now().minute}";
      }

      // Auto-save the document
      await _storageService.saveDocument(doc);
      tts.speak("The scanned paper is saved.");

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => TakeExamScreen(
            ttsService: tts,
            voiceService: this,
            accessibilityService: AccessibilityService(),
            picovoiceService: picovoiceService,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted && !isCancelled) {
        Navigator.pop(context); // Close Progress Dialog
      }

      String userMessage = "Error processing paper with Gemini AI.";
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains("quota") ||
          errorStr.contains("429") ||
          errorStr.contains("limit")) {
        userMessage =
            "Gemini API quota exceeded or rate limited. Please check your billing or wait a few minutes before trying again.";
      } else if (errorStr.contains("key")) {
        userMessage = "Invalid Gemini API key. Please check your settings.";
      }

      tts.speak(userMessage);

      if (context.mounted && !isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      debugPrint("Gemini Flow Error: $e");
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

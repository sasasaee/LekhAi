import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';
import 'gemini_question_service.dart';
import 'question_storage_service.dart'; // Added
import '../pdf_viewer_screen.dart';
// import '../take_exam_screen.dart';
import '../ocr_screen.dart';
import '../paper_detail_screen.dart';
import '../widgets/accessible_widgets.dart';
import 'kiosk_service.dart'; // Added

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
  stopDictation,
  readQuestion,
  readAnswer,
  changeSpeed,
  goBack,
  submitExam,
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
  unknown,
}

class CommandResult {
  final VoiceAction action;
  final dynamic payload;
  CommandResult(this.action, {this.payload});
}

// ... existing enum ...

class VoiceCommandService {
  final TtsService tts;
  final GeminiQuestionService _geminiService = GeminiQuestionService();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final QuestionStorageService _storageService = QuestionStorageService();
  bool _isScanDialogOpen = false;

  VoiceCommandService(this.tts);

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
       if (text.contains("add page") || text.contains("scan page") || text.contains("add photo")) {
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
            'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
            'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
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
        if (text.contains("previous") || text.contains("previous question") || text.contains("back")) {
             return CommandResult(VoiceAction.previousPage);
        }
        
        // ... Feature Toggle ...
        if (text.contains("play audio") || text.contains("play answer") || text.contains("listen")) {
            return CommandResult(VoiceAction.playAudioAnswer);
        }
        if (text.contains("context") || text.contains("read context")) {
            return CommandResult(VoiceAction.toggleReadContext);
        }
        if (text.contains("stop") || text.contains("pause")) {
            return CommandResult(VoiceAction.pauseReading);
        }

        // ... Direct Jump (New) ...
        // Logic reused from paperDetail - ideally refactor to helper, but copy-paste for safety now
        final RegExp selectionRegex = RegExp(r"(question|number)\s+([a-z0-9]+)");
        final match = selectionRegex.firstMatch(text);
        if (match != null) {
           String rawNumber = match.group(2)!;
           int? index = int.tryParse(rawNumber);
           if (index == null) {
              const numberMap = {
             'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
             'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
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
      if (text.contains("pause")) return CommandResult(VoiceAction.pauseReading);
      if (text.contains("resume") || text.contains("continue") || text.contains("play")) {
          return CommandResult(VoiceAction.resumeReading);
      }
      if (text.contains("restart") || text.contains("replay")) {
          return CommandResult(VoiceAction.restartReading);
      }
      if (text.contains("stop")) return CommandResult(VoiceAction.stopDictation);
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
    if (text.contains("stop dictation") || text.contains("pause writing")) {
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

    if (text.contains("confirm")) return CommandResult(VoiceAction.confirmAction);
    if (text.contains("cancel")) return CommandResult(VoiceAction.cancelAction);

    return CommandResult(VoiceAction.unknown);
  }

  Future<void> performGlobalNavigation(CommandResult result) async {
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
        final canPop = await navigatorKey.currentState?.maybePop() ?? false;
        if (!canPop) {
          tts.speak("You are already on the home screen.");
        }
        break;
      case VoiceAction.goToSavedPapers:
        await navigatorKey.currentState?.pushNamed('/saved_papers');
        break;
      case VoiceAction.goToTakeExam:
        await navigatorKey.currentState?.pushNamed('/take_exam');
        break;
      case VoiceAction.goToHome:
        // Use popUntil to return to the existing HomeScreen instance.
        // This triggers the .then() callback in HomeScreen, which resumes STT.
        // Using pushNamedAndRemoveUntil was destroying the STT controller.
        navigatorKey.currentState?.popUntil((route) {
          return route.settings.name == '/home' || route.isFirst;
        });
        break;
      case VoiceAction.goToSettings:
        await navigatorKey.currentState?.pushNamed('/settings');
        break;
      case VoiceAction.goToReadPDF:
        await _pickAndOpenPdf();
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
      case VoiceAction.openPaper:
        if (result.payload is int) {
          _handleOpenPaper(result.payload);
        }
        break;
      default:
        break;
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

      final storage = QuestionStorageService(); // Import required
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
      builder: (ctx) => AlertDialog(
        title: const Text('Scan Options'),
        content: const Text("Choose your preferred scanning method."),
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
      String? paperName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final TextEditingController nameController = TextEditingController();
          return AlertDialog(
            title: const Text("Name this Paper"),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "e.g. Physics Midterm",
                labelText: "Paper Name",
              ),
            ),
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
        builder: (_) => OcrScreen(ttsService: tts, voiceService: this),
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

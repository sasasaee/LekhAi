import 'package:flutter/material.dart';
import 'tts_service.dart';

enum VoiceAction {
  goToSavedPapers,
  goToTakeExam,
  goToQuestion,
  startDictation,
  stopDictation,
  readQuestion,
  readAnswer,
  changeSpeed,
  goBack,
  submitExam,
  unknown
}

class CommandResult {
  final VoiceAction action;
  final dynamic payload;
  CommandResult(this.action, {this.payload});
}

class VoiceCommandService {
  final TtsService tts;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  VoiceCommandService(this.tts);

  CommandResult parse(String text) {
    text = text.toLowerCase();
    if (text.contains("take exam") || text.contains("start exam") || text.contains("open exam")) {
      return CommandResult(VoiceAction.goToTakeExam);
    }
    if (text.contains("saved papers") || text.contains("go back to papers")) {
      return CommandResult(VoiceAction.goToSavedPapers);
    }
    if (text.contains("go back")) return CommandResult(VoiceAction.goBack);
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
    if (text.contains("change speed") || text.contains("faster") || text.contains("slower")) {
      return CommandResult(VoiceAction.changeSpeed);
    }

    return CommandResult(VoiceAction.unknown);
  }

  void performGlobalNavigation(CommandResult result) {
    switch (result.action) {
      case VoiceAction.goBack:
        navigatorKey.currentState?.pop();
        break;
      case VoiceAction.goToSavedPapers:
        navigatorKey.currentState?.pushNamed('/saved_papers');
        break;
      default:
        break;
    }
  }

  
}
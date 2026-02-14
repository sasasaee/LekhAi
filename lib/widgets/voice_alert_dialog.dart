import 'dart:async';
import 'package:flutter/material.dart';
import '../services/voice_command_service.dart';

class VoiceAlertDialog extends StatefulWidget {
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final VoiceCommandService voiceService;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onSkip;
  final Function(int)? onSelectOption;
  final VoidCallback? onViewPdf;
  final VoidCallback? onSharePdf;
  final VoidCallback? onSaveToDownloads;

  const VoiceAlertDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    required this.voiceService,
    this.onConfirm,
    this.onCancel,
    this.onSkip,
    this.onSelectOption,
    this.onViewPdf,
    this.onSharePdf,
    this.onSaveToDownloads,
  });

  @override
  State<VoiceAlertDialog> createState() => _VoiceAlertDialogState();
}

class _VoiceAlertDialogState extends State<VoiceAlertDialog> {
  // We need to listen to the stream manually since the dialog
  // might not be the top-most route in the traditional sense for the global listener?
  // Actually, VoiceCommandService broadcasts to all listeners.
  // We just need to register a listener here.

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  StreamSubscription<CommandResult>? _subscription;

  @override
  void initState() {
    super.initState();
    // Listen to the stream for events
    _subscription = widget.voiceService.commandStream.listen(_handleCommand);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: widget.title,
      content: widget.content,
      actions: widget.actions,
    );
  }

  void _handleCommand(CommandResult result) {
    if (!mounted) return;

    switch (result.action) {
      case VoiceAction.confirmAction:
      case VoiceAction.saveResult:
      case VoiceAction.submitExam: // Added: "Submit Exam" triggers confirm
      case VoiceAction.enterExamMode: // Added: "Start Exam" triggers confirm
        if (widget.onConfirm != null) widget.onConfirm!();
        break;
      case VoiceAction.cancelAction:
      case VoiceAction.goBack: // "Back" usually cancels a dialog
      case VoiceAction.exitExam: // "Exit exam" closes post-exam dialog
        if (widget.onCancel != null) widget.onCancel!();
        break;
      case VoiceAction.skip:
        if (widget.onSkip != null) widget.onSkip!();
        break;
      case VoiceAction.selectOption:
        if (widget.onSelectOption != null && result.payload is int) {
          widget.onSelectOption!(result.payload);
        }
        break;
      case VoiceAction.useGemini:
        // Specific logic for Scan Options dialog
        if (widget.onSelectOption != null) widget.onSelectOption!(1);
        break;
      case VoiceAction.useLocalOcr:
        // Specific logic for Scan Options dialog
        if (widget.onSelectOption != null) widget.onSelectOption!(2);
        break;
      case VoiceAction.viewPdf:
        if (widget.onViewPdf != null) widget.onViewPdf!();
        break;
      case VoiceAction.shareFile:
        if (widget.onSharePdf != null) widget.onSharePdf!();
        break;
      case VoiceAction.saveFile:
        // Handle save to downloads specifically if callback exists, else fall through to existing saveResult logic?
        // Actually, saveFile is mapped from "save to downloads".
        if (widget.onSaveToDownloads != null) {
          widget.onSaveToDownloads!();
        } else if (widget.onConfirm != null) {
          widget.onConfirm!();
        }
        break;
      default:
        break;
    }
  }
}

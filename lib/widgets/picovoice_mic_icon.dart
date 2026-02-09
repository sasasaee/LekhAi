import 'package:flutter/material.dart';
import '../services/picovoice_service.dart';

class PicovoiceMicIcon extends StatelessWidget {
  final PicovoiceService service;
  final double size;

  const PicovoiceMicIcon({
    super.key,
    required this.service,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PicovoiceState>(
      valueListenable: service.stateNotifier,
      builder: (ctx, state, child) {
        Color iconColor;
        IconData iconData = Icons.mic_rounded;
        bool isAnimating = false;

        switch (state) {
          case PicovoiceState.idle:
            iconColor = Colors.white.withValues(alpha: 0.3);
            break;
          case PicovoiceState.commandListening:
            iconColor = Colors.orangeAccent;
            isAnimating = true;
            break;
          case PicovoiceState.processing:
            iconColor = Colors.blueAccent;
            isAnimating = true;
            break;
          case PicovoiceState.ttsSpeaking:
            iconColor = Colors.blue.withValues(alpha: 0.5);
            iconData = Icons.volume_up_rounded;
            break;
          case PicovoiceState.error:
            iconColor = Colors.redAccent;
            iconData = Icons.mic_off_rounded;
            break;
          case PicovoiceState.disabled:
            iconColor = Colors.grey.withValues(alpha: 0.2);
            iconData = Icons.mic_off_rounded;
            break;
          default:
            iconColor = Colors.white24;
        }

        Widget icon = Icon(
          iconData,
          color: iconColor,
          size: size,
        );

        if (isAnimating) {
          return TweenAnimationBuilder<double>(
            key: ValueKey(state), // Restart on state change
            tween: Tween(begin: 1.0, end: 1.2),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: icon,
              );
            },
          );
        }

        return ValueListenableBuilder<String?>(
          valueListenable: service.errorNotifier,
          builder: (ctx, errorMessage, _) {
            final content = errorMessage != null && state == PicovoiceState.error
                ? Tooltip(
                    message: errorMessage,
                    triggerMode: TooltipTriggerMode.tap,
                    child: icon,
                  )
                : icon;
            return content;
          },
        );
      },
    );
  }
}

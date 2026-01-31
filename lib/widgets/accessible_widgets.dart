import 'package:flutter/material.dart';
import '../services/accessibility_service.dart';

/// A wrapper that handles Double Tap to Activate logic.
class DoubleTapWrapper extends StatefulWidget {
  final VoidCallback? onActivate;
  final String announcement;
  final Widget Function(BuildContext context, VoidCallback onTap) builder;
  final AccessibilityEvent activationEvent;
  final AccessibilityEvent focusEvent;

  const DoubleTapWrapper({
    super.key,
    required this.onActivate,
    required this.announcement,
    required this.builder,
    this.activationEvent = AccessibilityEvent.action,
    this.focusEvent = AccessibilityEvent.focus,
  });

  @override
  State<DoubleTapWrapper> createState() => _DoubleTapWrapperState();
}

class _DoubleTapWrapperState extends State<DoubleTapWrapper> {
  final AccessibilityService _service = AccessibilityService();
  DateTime? _lastTapTime;
  static const Duration _doubleTapThreshold = Duration(
    milliseconds: 400,
  ); // Tweakable

  void _handleTap() {
    if (widget.onActivate == null) return;

    // Check if system screen reader (TalkBack/VoiceOver) is active.
    // If so, TalkBack handles the double-tap-to-activate interaction internally.
    // The 'onTap' we receive here IS the activation.
    final bool isScreenReaderActive = MediaQuery.of(
      context,
    ).accessibleNavigation;

    if (isScreenReaderActive) {
      _service.trigger(widget.activationEvent);
      widget.onActivate!();
      return;
    }

    // Check preference: If "Single Tap Announce" is disabled, activate immediately on single tap
    if (!_service.oneTapAnnounce) {
      _service.trigger(widget.activationEvent);
      widget.onActivate!();
      return;
    }

    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < _doubleTapThreshold) {
      // DOUBLE TAP detected
      _service.trigger(widget.activationEvent);
      widget.onActivate!();
      _lastTapTime = null; // Reset
    } else {
      // SINGLE TAP detected
      _lastTapTime = now;
      // Announce
      final msg = "${widget.announcement}. Double tap to activate.";
      _service.announce(msg, widget.focusEvent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.announcement, // Expose label to TalkBack/VoiceOver
      button: true, // Identify as button
      container: true, // Group children
      enabled: widget.onActivate != null,
      onTap: widget.onActivate != null
          ? _handleTap
          : null, // Essential for TalkBack activation
      excludeSemantics:
          true, // Hide child semantics (e.g. "Button") to avoid double-speak
      child: widget.builder(context, _handleTap),
    );
  }
}

class AccessibleIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final AccessibilityEvent event;
  final Color? color;
  final double? iconSize;
  final ButtonStyle? style;

  AccessibleIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.event = AccessibilityEvent.action,
    this.color,
    this.iconSize,
    this.style,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      excludeSemantics: true, // We provide our own semantics
      child: GestureDetector(
        onLongPress: () {
          if (tooltip != null) {
            _service.announce(tooltip!, AccessibilityEvent.focus);
          }
        },
        child: IconButton(
          onPressed: onPressed == null
              ? null
              : () async {
                  await _service.trigger(event);
                  onPressed!();
                },
          icon: icon,
          tooltip:
              null, // Disable default tooltip to avoid double announcements
          color: color,
          iconSize: iconSize,
          style: style,
        ),
      ),
    );
  }
}

class AccessibleElevatedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final AccessibilityEvent event;
  final ButtonStyle? style;
  final Widget? icon; // Optional icon for ElevatedButton.icon

  AccessibleElevatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.event = AccessibilityEvent.action,
    this.style,
    this.icon,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    final action = onPressed == null
        ? null
        : () async {
            await _service.trigger(event);
            onPressed!();
          };

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: action,
        icon: icon!,
        label: child,
        style: style,
      );
    }

    return ElevatedButton(onPressed: action, style: style, child: child);
  }
}

class AccessibleListTile extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final AccessibilityEvent tapEvent;
  final AccessibilityEvent longPressEvent;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? contentPadding; // Added
  final Color? tileColor; // Restored

  AccessibleListTile({
    super.key,
    this.onTap,
    this.onLongPress,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.tapEvent = AccessibilityEvent.navigation, // ListTiles often navigate
    this.longPressEvent = AccessibilityEvent.warning,
    this.shape,
    this.tileColor,
    this.contentPadding,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap == null
          ? null
          : () async {
              await _service.trigger(tapEvent);
              onTap!();
            },
      onLongPress: onLongPress == null
          ? null
          : () async {
              await _service.trigger(longPressEvent);
              onLongPress!();
            },
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      shape: shape,
      tileColor: tileColor,
      contentPadding: contentPadding,
    );
  }
}

class AccessibleInkWell extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final AccessibilityEvent tapEvent;

  AccessibleInkWell({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.child,
    this.tapEvent = AccessibilityEvent.action,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () async {
              await _service.trigger(tapEvent);
              onTap!();
            },
      onLongPress: onLongPress == null
          ? null
          : () async {
              await _service.trigger(AccessibilityEvent.warning);
              onLongPress!();
            },
      child: child,
    );
  }
}

class AccessibleFloatingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final AccessibilityEvent event;
  final Color? backgroundColor;

  AccessibleFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.event = AccessibilityEvent.action,
    this.backgroundColor,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed == null
          ? null
          : () async {
              await _service.trigger(event);
              onPressed!();
            },
      tooltip: tooltip,
      backgroundColor: backgroundColor,
      child: child,
    );
  }
}

class AccessibleTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final AccessibilityEvent event;
  final ButtonStyle? style;

  AccessibleTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.event = AccessibilityEvent.action,
    this.style,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed == null
          ? null
          : () async {
              await _service.trigger(event);
              onPressed!();
            },
      style: style,
      child: child,
    );
  }
}

class AccessibleOutlinedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final AccessibilityEvent event;
  final ButtonStyle? style;
  final Widget? icon;

  AccessibleOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.event = AccessibilityEvent.action,
    this.style,
    this.icon,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    final action = onPressed == null
        ? null
        : () async {
            await _service.trigger(event);
            onPressed!();
          };

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: action,
        icon: icon!,
        label: child,
        style: style,
      );
    }

    return OutlinedButton(onPressed: action, style: style, child: child);
  }
}

class AccessibleSwitchListTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final VisualDensity? visualDensity;
  final Color? activeColor;

  AccessibleSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    this.visualDensity,
    this.activeColor,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged == null
          ? null
          : (val) async {
              await _service.trigger(
                AccessibilityEvent.action,
              ); // Toggle action
              onChanged!(val);
            },
      title: title,
      subtitle: subtitle,
      contentPadding: contentPadding,
      visualDensity: visualDensity,
      activeColor: activeColor,
    );
  }
}

class AccessibleSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final Color? inactiveColor;
  final String? label;

  AccessibleSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
    this.inactiveColor,
    this.label,
  });

  final AccessibilityService _service = AccessibilityService();

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      label: label,
      onChanged: onChanged == null
          ? null
          : (val) {
              if (val != value) {
                _service.trigger(
                  AccessibilityEvent.action,
                ); // Vibrate on change
              }
              onChanged!(val);
            },
    );
  }
}

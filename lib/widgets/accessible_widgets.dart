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
  static const Duration _doubleTapThreshold = Duration(milliseconds: 400); // Tweakable

  void _handleTap() {
    if (widget.onActivate == null) return;

    // Check if system screen reader (TalkBack/VoiceOver) is active.
    // If so, TalkBack handles the double-tap-to-activate interaction internally.
    // The 'onTap' we receive here IS the activation.
    final bool isScreenReaderActive = MediaQuery.of(context).accessibleNavigation;

    if (isScreenReaderActive) {
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
      onTap: widget.onActivate != null ? _handleTap : null, // Essential for TalkBack activation
      excludeSemantics: true, // Hide child semantics (e.g. "Button") to avoid double-speak
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

  const AccessibleIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.event = AccessibilityEvent.action,
    this.color,
    this.iconSize,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return DoubleTapWrapper(
      onActivate: onPressed,
      announcement: tooltip ?? "Button",
      activationEvent: event,
      builder: (context, onTap) {
        return Semantics(
          label: tooltip,
          button: true,
          excludeSemantics: true,
          child: IconButton(
            onPressed: onPressed == null ? null : onTap,
            icon: icon,
            tooltip: null, // Disable built-in tooltip
            color: color,
            iconSize: iconSize,
            style: style,
          ),
        );
      },
    );
  }
}

class AccessibleElevatedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final AccessibilityEvent event;
  final ButtonStyle? style;
  final Widget? icon;
  final String? semanticLabel; // Added parameter

  const AccessibleElevatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.event = AccessibilityEvent.action,
    this.style,
    this.icon,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    String announcement = semanticLabel ?? "Button";
    if (semanticLabel == null && child is Text) {
      announcement = (child as Text).data ?? "Button";
    }

    return DoubleTapWrapper(
      onActivate: onPressed,
      announcement: announcement,
      activationEvent: event,
      builder: (context, onTap) {
        if (icon != null) {
          return ElevatedButton.icon(
            onPressed: onPressed == null ? null : onTap,
            icon: icon!,
            label: child,
            style: style,
          );
        }
        return ElevatedButton(
          onPressed: onPressed == null ? null : onTap,
          style: style,
          child: child,
        );
      },
    );
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
  final EdgeInsetsGeometry? contentPadding;
  final Color? tileColor;
  final String? semanticLabel;

  const AccessibleListTile({
    super.key,
    this.onTap,
    this.onLongPress,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.tapEvent = AccessibilityEvent.navigation,
    this.longPressEvent = AccessibilityEvent.warning,
    this.shape,
    this.tileColor,
    this.contentPadding,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    String announcement = semanticLabel ?? "Item";
    if (semanticLabel == null && title is Text) {
        announcement = (title as Text).data ?? "Item";
    }

    return DoubleTapWrapper(
      onActivate: onTap,
      announcement: announcement,
      activationEvent: tapEvent,
      builder: (context, newTapHandler) {
        return ListTile(
          onTap: onTap == null ? null : newTapHandler,
          onLongPress: onLongPress == null ? null : () {
            AccessibilityService().trigger(longPressEvent);
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
      },
    );
  }
}

class AccessibleInkWell extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final AccessibilityEvent tapEvent;
  final String? semanticLabel;

  const AccessibleInkWell({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.child,
    this.tapEvent = AccessibilityEvent.action,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    String announcement = semanticLabel ?? "Element";
    if (semanticLabel == null && child is Text) {
      announcement = (child as Text).data ?? "Element";
    }

    return DoubleTapWrapper(
      onActivate: onTap,
      announcement: announcement,
      activationEvent: tapEvent,
      builder: (context, newTapHandler) {
        return InkWell(
          onTap: onTap == null ? null : newTapHandler,
          onLongPress: onLongPress == null ? null : () {
            AccessibilityService().trigger(AccessibilityEvent.warning);
            onLongPress!();
          },
          child: child,
        );
      },
    );
  }
}

class AccessibleFloatingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final AccessibilityEvent event;
  final Color? backgroundColor;

  const AccessibleFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.event = AccessibilityEvent.action,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DoubleTapWrapper(
      onActivate: onPressed,
      announcement: tooltip ?? "Action Button",
      activationEvent: event,
      builder: (context, onTap) {
        return FloatingActionButton(
          onPressed: onPressed == null ? null : onTap,
          tooltip: null, // Disable default
          backgroundColor: backgroundColor,
          child: child,
        );
      },
    );
  }
}

class AccessibleTextButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final AccessibilityEvent event;
  final ButtonStyle? style;
  final String? semanticLabel;

  const AccessibleTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.event = AccessibilityEvent.action,
    this.style,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    String announcement = semanticLabel ?? "Button";
    if (semanticLabel == null && child is Text) {
      announcement = (child as Text).data ?? "Button";
    }

    return DoubleTapWrapper(
      onActivate: onPressed,
      announcement: announcement,
      activationEvent: event,
      builder: (context, onTap) {
        return TextButton(
          onPressed: onPressed == null ? null : onTap,
          style: style,
          child: child,
        );
      },
    );
  }
}

class AccessibleOutlinedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final AccessibilityEvent event;
  final ButtonStyle? style;
  final Widget? icon;
  final String? semanticLabel;

  const AccessibleOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.event = AccessibilityEvent.action,
    this.style,
    this.icon,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    String announcement = semanticLabel ?? "Button";
    if (semanticLabel == null && child is Text) {
      announcement = (child as Text).data ?? "Button";
    }

    return DoubleTapWrapper(
      onActivate: onPressed,
      announcement: announcement,
      activationEvent: event,
      builder: (context, onTap) {
        if (icon != null) {
          return OutlinedButton.icon(
            onPressed: onPressed == null ? null : onTap,
            icon: icon!,
            label: child,
            style: style,
          );
        }
        return OutlinedButton(
          onPressed: onPressed == null ? null : onTap,
          style: style,
          child: child,
        );
      },
    );
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
  final String? semanticLabel;

  const AccessibleSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    this.visualDensity,
    this.activeColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    String announcement = semanticLabel ?? "Switch";
    if (semanticLabel == null && title is Text) {
        announcement = (title as Text).data ?? "Switch";
    }
    announcement += value ? " On" : " Off"; // State feedback

    return DoubleTapWrapper(
      onActivate: onChanged == null ? null : () => onChanged!(!value),
      announcement: announcement,
      activationEvent: AccessibilityEvent.action,
      builder: (context, onTap) {
        // SwitchListTile handles onTap internally to toggle.
        // We intercept setting onChanged to our onTap? 
        // No, onChanged expects (bool).
        // SwitchListTile onTap calls onChanged(!value).
        // So we can wrap the tile in a wrapper, but SwitchListTile isn't a button exactly.
        // Let's use InkWell wrapper logic or just pass a modified onChanged.
        
        return SwitchListTile(
          value: value,
          onChanged: onChanged == null ? null : (val) {
             // val is the NEW value.
             // We need to trigger double tap logic.
             // But the DoubleTapWrapper expects a VoidCallback.
             // We can bridge it.
             onTap();
          },
          title: title,
          subtitle: subtitle,
          contentPadding: contentPadding,
          visualDensity: visualDensity,
          // ignore: deprecated_member_use
          activeColor: activeColor,
        );
      },
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

  const AccessibleSlider({
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

  // Slider is different. It's a drag interaction.
  // Double tap to activate doesn't apply well to Slider.
  // We keep it as is (immediate), or maybe double tap to announce value?
  // Current implementation just vibrates on change.
  // We will leave it as is for now as User asked "for the buttons".

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
                AccessibilityService().trigger(AccessibilityEvent.action); // Vibrate on change
              }
              onChanged!(val);
            },
    );
  }
}

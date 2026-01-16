import 'package:flutter/material.dart';
import '../services/accessibility_service.dart';

/// A set of widgets that automatically trigger haptic feedback on interaction.
/// Usage: Replace standard Flutter widgets with these accessible variants.

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
          tooltip: null, // Disable default tooltip to avoid double announcements
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

    return ElevatedButton(
      onPressed: action,
      style: style,
      child: child,
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

    return OutlinedButton(
      onPressed: action,
      style: style,
      child: child,
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
              await _service.trigger(AccessibilityEvent.action); // Toggle action
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
                _service.trigger(AccessibilityEvent.action); // Vibrate on change
              }
              onChanged!(val);
            },
    );
  }
}

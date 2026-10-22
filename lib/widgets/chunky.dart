import 'package:flutter/material.dart';

import '../theme.dart';

/// The signature Duolingo button: a solid face sitting on a darker "lip"
/// that squashes down when pressed.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = Palette.green,
    this.lipColor = Palette.greenLip,
    this.textColor = Colors.white,
    this.expand = true,
  });

  /// White button with a gray outline, for secondary actions.
  const ChunkyButton.outlined({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.textColor = Palette.blue,
    this.expand = true,
  }) : color = Palette.white,
       lipColor = Palette.line;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color lipColor;
  final Color textColor;
  final bool expand;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  static const _lip = 4.0;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final face = enabled ? widget.color : Palette.line;
    final lip = enabled ? widget.lipColor : Palette.line;
    final fg = enabled ? widget.textColor : Palette.gray;
    final outlined = widget.color == Palette.white;

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, color: fg, size: 22),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: fg,
              letterSpacing: 0.8,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          height: 50,
          margin: EdgeInsets.only(
            top: _pressed ? _lip : 0,
            bottom: _pressed ? 0 : _lip,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: face,
            borderRadius: BorderRadius.circular(16),
            border: outlined ? Border.all(color: Palette.line, width: 2) : null,
            boxShadow: _pressed
                ? const []
                : [BoxShadow(color: lip, offset: const Offset(0, _lip))],
          ),
          child: content,
        ),
      ),
    );
  }
}

/// White rounded card with a gray outline and bottom lip.
class ChunkyCard extends StatelessWidget {
  const ChunkyCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderColor = Palette.line,
    this.color = Palette.white,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color borderColor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [BoxShadow(color: borderColor, offset: const Offset(0, 4))],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// Thick rounded progress bar with a highlight stripe, à la Duolingo.
class ChunkyProgressBar extends StatelessWidget {
  const ChunkyProgressBar({
    super.key,
    required this.value,
    this.color = Palette.green,
    this.height = 16,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: Palette.line,
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          widthFactor: v == 0 ? 0 : v.clamp(0.06, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(height),
            ),
            alignment: Alignment.topCenter,
            padding: EdgeInsets.fromLTRB(
              height * 0.5,
              height * 0.22,
              height * 0.5,
              0,
            ),
            child: Container(
              height: height * 0.22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A big selectable tile (used for strands, outcomes, categories, goals).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color = Palette.blue,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final border = selected ? color : Palette.line;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Palette.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 2),
          boxShadow: [BoxShadow(color: border, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: selected ? color : Palette.gray, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: selected ? _readableOn(color) : Palette.ink,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A darker shade of [accent] that stays legible on a light tint of itself.
Color _readableOn(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  return hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).toColor();
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_coach/apple_coach.dart';
import 'package:flutter/material.dart';

import '../src/rust/api/coach.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import 'chunky.dart';

/// Apple Intelligence-style colours.
const _glowColors = [
  Color(0xFF0894FF),
  Color(0xFFC959DD),
  Color(0xFFFF2E54),
  Color(0xFFFF9004),
  Color(0xFF0894FF),
];

const _thinkingPhrases = [
  'Reading your reflection…',
  'Looking for feelings…',
  'Spotting what you learned…',
  'Checking learning outcomes…',
  'Thinking about next steps…',
];

enum _Phase { idle, thinking, done }

/// "Coach me" button that turns into an animated, glowing feedback card.
///
/// Uses Apple Intelligence on supported iPhones and Macs, and the Rust rule
/// engine everywhere else (or if Apple Intelligence fails).
class CoachPanel extends StatefulWidget {
  const CoachPanel({
    super.key,
    required this.draft,
    required this.wordCount,
    required this.tagged,
    required this.onTag,
  });

  /// The reflection as it currently stands in the editor.
  final ReflectionDraft Function() draft;
  final int wordCount;
  final Set<LearningOutcome> tagged;
  final ValueChanged<LearningOutcome> onTag;

  @override
  State<CoachPanel> createState() => _CoachPanelState();
}

class _CoachPanelState extends State<CoachPanel> {
  _Phase _phase = _Phase.idle;
  CoachReport? _report;
  AppleCoachStatus _apple = AppleCoachStatus.unsupported;
  final _random = math.Random();

  bool get _useApple => _apple == AppleCoachStatus.available;

  @override
  void initState() {
    super.initState();
    AppleCoach.status().then((s) {
      if (mounted) setState(() => _apple = s);
    });
  }

  Future<void> _run() async {
    setState(() => _phase = _Phase.thinking);
    final draft = widget.draft();
    CoachReport? report;

    if (_useApple) {
      try {
        final prompt = coachPrompt(draft: draft);
        final raw = await AppleCoach.generate(
          instructions: prompt.instructions,
          prompt: prompt.prompt,
        );
        report = await coachWithAi(draft: draft, feedback: _toFeedback(raw));
      } catch (_) {
        report = null; // Fall back to the rules below.
      }
    }

    // The rules answer instantly; a short pause lets the animation breathe.
    report ??= (await Future.wait([
      coachWithRules(draft: draft),
      Future<void>.delayed(
        Duration(milliseconds: 1000 + _random.nextInt(1000)),
      ),
    ]))[0] as CoachReport;

    if (!mounted) return;
    setState(() {
      _report = report;
      _phase = _Phase.done;
    });
  }

  AiFeedback _toFeedback(Map<String, Object?> raw) => AiFeedback(
    headline: raw['headline'] as String? ?? '',
    tips: [
      for (final t in (raw['tips'] as List<Object?>? ?? const []))
        if (t is Map)
          AiTip(
            kind: t['kind'] as String? ?? 'suggestion',
            title: t['title'] as String? ?? '',
            body: t['body'] as String? ?? '',
          ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final minWords = coachMinWords();
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: switch (_phase) {
        _Phase.idle => _CoachButton(
          appleIntelligence: _useApple,
          enabled: widget.wordCount >= minWords,
          hint: widget.wordCount >= minWords
              ? null
              : 'Write at least $minWords words to get feedback',
          onPressed: _run,
        ),
        _Phase.thinking => _ThinkingCard(appleIntelligence: _useApple),
        _Phase.done => _ResultCard(
          report: _report!,
          tagged: widget.tagged,
          onTag: widget.onTag,
          onRecheck: _run,
          appleHint: switch (_apple) {
            AppleCoachStatus.notEnabled =>
              'Turn on Apple Intelligence in Settings for smarter feedback.',
            AppleCoachStatus.notReady =>
              'Apple Intelligence is still downloading. Smarter feedback soon!',
            _ => null,
          },
        ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Glow
// ---------------------------------------------------------------------------

/// A card with a flowing rainbow edge. While [active], the colours rotate
/// and bleed outward as a soft glow, like Apple Intelligence's Siri edge.
class IntelligenceGlow extends StatefulWidget {
  const IntelligenceGlow({
    super.key,
    required this.child,
    this.active = false,
    this.radius = 22,
  });

  final Widget child;
  final bool active;
  final double radius;

  @override
  State<IntelligenceGlow> createState() => _IntelligenceGlowState();
}

class _IntelligenceGlowState extends State<IntelligenceGlow>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, child) {
        // Slow drift when idle, full spin while thinking.
        final turns = widget.active ? _spin.value : _spin.value * 0.25;
        final gradient = SweepGradient(
          colors: _glowColors,
          transform: GradientRotation(turns * 2 * math.pi),
        );
        // Gentle "breathing" of the glow.
        final pulse = 0.75 + 0.25 * math.sin(_spin.value * 4 * math.pi);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: widget.active ? pulse : 0.25,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(widget.active ? 3 : 2),
              decoration: BoxDecoration(gradient: gradient, borderRadius: radius),
              child: Container(
                decoration: BoxDecoration(
                  color: Palette.white,
                  borderRadius: BorderRadius.circular(widget.radius - 2),
                ),
                child: child,
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Text with a rainbow highlight sweeping across it.
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          final x = -1.0 + 3.0 * _c.value;
          return LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: const [
              Palette.gray,
              Color(0xFF0894FF),
              Color(0xFFC959DD),
              Color(0xFFFF2E54),
              Palette.gray,
            ],
          ).createShader(bounds);
        },
        child: child,
      ),
      child: Text(widget.text, style: widget.style),
    );
  }
}

/// "✨ Apple Intelligence" in rainbow, or the BetterBAC coach badge.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.appleIntelligence});

  final bool appleIntelligence;

  @override
  Widget build(BuildContext context) {
    if (!appleIntelligence) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_rounded, size: 18, color: Palette.green),
          SizedBox(width: 4),
          Text(
            'BetterBAC Coach',
            style: TextStyle(
              color: Palette.greenLip,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      );
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (b) =>
          const LinearGradient(colors: _glowColors).createShader(b),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 18),
          SizedBox(width: 4),
          Text(
            'Apple Intelligence',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

class _CoachButton extends StatelessWidget {
  const _CoachButton({
    required this.appleIntelligence,
    required this.enabled,
    required this.onPressed,
    this.hint,
  });

  final bool appleIntelligence;
  final bool enabled;
  final VoidCallback onPressed;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: IntelligenceGlow(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (b) =>
                      const LinearGradient(colors: _glowColors).createShader(b),
                  child: const Icon(Icons.auto_awesome, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Coach my reflection',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        hint ??
                            (appleIntelligence
                                ? 'Private feedback with Apple Intelligence'
                                : 'Private feedback, right on your device'),
                        style: const TextStyle(
                          color: Palette.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Palette.gray),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinkingCard extends StatefulWidget {
  const _ThinkingCard({required this.appleIntelligence});

  final bool appleIntelligence;

  @override
  State<_ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<_ThinkingCard> {
  int _phrase = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => setState(() => _phrase = (_phrase + 1) % _thinkingPhrases.length),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IntelligenceGlow(
      active: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SourceBadge(appleIntelligence: widget.appleIntelligence),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: ShimmerText(
                _thinkingPhrases[_phrase],
                key: ValueKey(_phrase),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Placeholder lines that hint at the answer to come.
            for (final w in const [1.0, 0.85, 0.6])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Palette.snow,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.report,
    required this.tagged,
    required this.onTag,
    required this.onRecheck,
    this.appleHint,
  });

  final CoachReport report;
  final Set<LearningOutcome> tagged;
  final ValueChanged<LearningOutcome> onTag;
  final VoidCallback onRecheck;
  final String? appleHint;

  @override
  Widget build(BuildContext context) {
    final apple = report.source == CoachSource.appleIntelligence;
    return IntelligenceGlow(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _SourceBadge(appleIntelligence: apple)),
                TextButton.icon(
                  onPressed: onRecheck,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('RE-CHECK'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ScoreRing(score: report.score),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    report.headline,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (i, tip) in report.tips.indexed)
              _Staggered(
                index: i,
                child: _TipRow(tip: tip, tagged: tagged, onTag: onTag),
              ),
            if (appleHint != null && !apple)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  appleHint!,
                  style: const TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score});

  final int score;

  Color get _color => switch (score) {
    >= 80 => Palette.green,
    >= 60 => Palette.blue,
    >= 35 => Palette.orange,
    _ => Palette.red,
  };

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: v,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              backgroundColor: Palette.line,
              color: _color,
            ),
            Center(
              child: Text(
                '${(v * 100).round()}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and slides a tip in, a little later for each successive [index].
class _Staggered extends StatelessWidget {
  const _Staggered({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = 200 + index * 140;
    final total = delay + 350;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.tip, required this.tagged, required this.onTag});

  final CoachTip tip;
  final Set<LearningOutcome> tagged;
  final ValueChanged<LearningOutcome> onTag;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (tip.kind) {
      TipKind.praise => (Icons.check_circle_rounded, Palette.green),
      TipKind.suggestion => (Icons.lightbulb_rounded, Palette.orange),
      TipKind.outcome => (Icons.sell_rounded, Palette.blue),
    };
    final tag = tip.suggestTag;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(tip.body),
                if (tag != null) ...[
                  const SizedBox(height: 8),
                  tagged.contains(tag)
                      ? const Text(
                          'Tagged ✓',
                          style: TextStyle(
                            color: Palette.green,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : ChunkyButton(
                          label: 'Tag LO${tag.number()}',
                          icon: Icons.sell_rounded,
                          color: Palette.blue,
                          lipColor: Palette.blueLip,
                          expand: false,
                          onPressed: () => onTag(tag),
                        ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

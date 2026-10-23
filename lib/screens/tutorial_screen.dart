import 'package:flutter/material.dart';

import '../src/rust/api/tutorial.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/coach_panel.dart';
import '../widgets/workload.dart';
import 'shell.dart';

/// Opens the full tour from anywhere (e.g. Profile → Replay the tour).
Future<void> replayTutorial(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => TutorialScreen(steps: tutorialSteps(afterVersion: 0)),
  ),
);

/// A Duolingo-lesson-style walkthrough of the app.
///
/// Step content comes from Rust (`api/tutorial.rs`); this file only draws
/// it. Add an illustration in [_illustration] for each new step id.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({
    super.key,
    required this.steps,
    this.whatsNew = false,
    this.continueToApp = false,
  });

  final List<TutorialStep> steps;

  /// Shown after an update: only the new steps, with a "What's new" header.
  final bool whatsNew;

  /// On finish, replace this screen with the app instead of popping back.
  final bool continueToApp;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pages = PageController();
  int _index = 0;

  bool get _last => _index == widget.steps.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    try {
      await markTutorialSeen();
    } catch (_) {
      // Not worth blocking the user over; they'll just see the tour again.
    }
    if (widget.continueToApp) {
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
    } else {
      navigator.pop();
    }
  }

  void _go(int delta) => _pages.animateToPage(
    _index + delta,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                // Lesson header: close, progress.
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Skip tour',
                        onPressed: _finish,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Palette.gray,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChunkyProgressBar(
                          value: (_index + 1) / widget.steps.length,
                          color: _accent(step.accent),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.whatsNew)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      "WHAT'S NEW",
                      style: TextStyle(
                        color: Palette.blue,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.steps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) =>
                        _StepPage(step: widget.steps[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      if (_index > 0) ...[
                        ChunkyButton.outlined(
                          label: 'Back',
                          textColor: Palette.muted,
                          expand: false,
                          onPressed: () => _go(-1),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ChunkyButton(
                          label: _last
                              ? (widget.whatsNew ? 'Got it' : "Let's go!")
                              : 'Continue',
                          color: _accent(step.accent),
                          lipColor: _lip(step.accent),
                          onPressed: _last ? _finish : () => _go(1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});

  final TutorialStep step;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: [
          // At least 240 tall so titles line up between steps, but taller
          // illustrations may grow (the page scrolls).
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 240),
            child: Center(child: _illustration(step)),
          ),
          const SizedBox(height: 28),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              color: Palette.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Illustrations: small, static previews built from the app's real widgets.
// ---------------------------------------------------------------------------

Color _accent(TutorialAccent a) => switch (a) {
  TutorialAccent.green => Palette.green,
  TutorialAccent.blue => Palette.blue,
  TutorialAccent.orange => Palette.orange,
  TutorialAccent.purple => Palette.purple,
  TutorialAccent.red => Palette.red,
  TutorialAccent.yellow => Palette.yellow,
};

Color _lip(TutorialAccent a) => switch (a) {
  TutorialAccent.green => Palette.greenLip,
  TutorialAccent.blue => Palette.blueLip,
  TutorialAccent.orange => Palette.orangeLip,
  TutorialAccent.purple => Palette.purpleLip,
  TutorialAccent.red => Palette.redLip,
  TutorialAccent.yellow => Palette.yellowLip,
};

IconData _icon(String name) => switch (name) {
  'school' => Icons.school_rounded,
  'local_fire_department' => Icons.local_fire_department_rounded,
  'verified' => Icons.verified_rounded,
  'flag' => Icons.flag_rounded,
  'edit_note' => Icons.edit_note_rounded,
  'auto_awesome' => Icons.auto_awesome,
  'send' => Icons.send_rounded,
  'calendar_month' => Icons.calendar_month_rounded,
  'warning' => Icons.warning_rounded,
  'emoji_events' => Icons.emoji_events_rounded,
  'lock' => Icons.lock_rounded,
  'event_repeat' => Icons.event_repeat_rounded,
  'notifications_active' => Icons.notifications_active_rounded,
  _ => Icons.star_rounded,
};

/// Big circular icon badge; the fallback illustration.
Widget _badge(TutorialStep step, {double size = 150}) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: _accent(step.accent),
    shape: BoxShape.circle,
    boxShadow: [
      BoxShadow(color: _lip(step.accent), offset: const Offset(0, 8)),
    ],
  ),
  child: Icon(_icon(step.icon), color: Colors.white, size: size * 0.5),
);

Widget _illustration(TutorialStep step) => switch (step.id) {
  'daily_goal' => const _DailyGoalDemo(),
  'outcomes' => const _OutcomesDemo(),
  'experiences' => const _StrandsDemo(),
  'reflections' => const _ReflectionDemo(),
  'coach' => const _CoachDemo(),
  'managebac' => const _ManageBacDemo(),
  'calendar' => const _CalendarDemo(),
  'calendar_import' => const _CalendarImportDemo(),
  'pressing_task' => const _PressingTaskDemo(),
  'crunch' => const _CrunchDemo(),
  'reminders' => const _RemindersDemo(),
  'achievements' => const _AchievementsDemo(),
  _ => _badge(step),
};

class _DailyGoalDemo extends StatelessWidget {
  const _DailyGoalDemo();

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return ChunkyCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(Icons.local_fire_department_rounded, Palette.orange, '5'),
              _Stat(Icons.bolt_rounded, Palette.yellow, '340'),
              _Stat(Icons.shield_rounded, Palette.blue, 'Lv 3'),
            ],
          ),
          const SizedBox(height: 16),
          const ChunkyProgressBar(value: 0.7),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (i, d) in days.indexed)
                Column(
                  children: [
                    Text(
                      d,
                      style: const TextStyle(
                        color: Palette.gray,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: i < 5 ? Palette.orange : Palette.line,
                      size: 26,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.color, this.value);

  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 30),
      const SizedBox(width: 4),
      Text(
        value,
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20),
      ),
    ],
  );
}

class _OutcomesDemo extends StatelessWidget {
  const _OutcomesDemo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (var n = 1; n <= 7; n++)
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: n <= 4 ? Palette.green : Palette.snow,
                  border: Border.all(
                    color: n <= 4 ? Palette.greenLip : Palette.line,
                    width: 3,
                  ),
                ),
                child: n <= 4
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : Text(
                        '$n',
                        style: const TextStyle(
                          color: Palette.gray,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const _StrandsDemo(compact: true),
      ],
    );
  }
}

class _StrandsDemo extends StatelessWidget {
  const _StrandsDemo({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 56.0 : 84.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in Strand.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: strandColor(s),
                    borderRadius: BorderRadius.circular(size * 0.28),
                    boxShadow: [
                      BoxShadow(color: strandLip(s), offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Icon(strandIcon(s), color: Colors.white, size: size * 0.5),
                ),
                if (!compact) ...[
                  const SizedBox(height: 10),
                  Text(
                    s.label(),
                    style: TextStyle(
                      color: strandLip(s),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ReflectionDemo extends StatelessWidget {
  const _ReflectionDemo();

  @override
  Widget build(BuildContext context) {
    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Palette.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Palette.greenLip, fontWeight: FontWeight.w800),
      ),
    );
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Learning to improvise',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [chip('LO2'), chip('LO5')]),
          const SizedBox(height: 10),
          const Text(
            'I was nervous before my first solo, but I learned that mistakes '
            'can become part of the music…',
            style: TextStyle(color: Palette.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: Palette.blue, size: 20),
              SizedBox(width: 6),
              Text(
                'Need inspiration?',
                style: TextStyle(color: Palette.blueLip, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoachDemo extends StatelessWidget {
  const _CoachDemo();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: IntelligenceGlow(
        active: true,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFFC959DD)),
                  SizedBox(width: 6),
                  Text('Coach', style: TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
              SizedBox(height: 14),
              ShimmerText(
                'Spotting what you learned…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageBacDemo extends StatelessWidget {
  const _ManageBacDemo();

  @override
  Widget build(BuildContext context) {
    Widget bubble(IconData icon, Color color, String label) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 38),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            bubble(Icons.content_copy_rounded, Palette.green, 'Copy'),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 26),
              child: Icon(Icons.arrow_forward_rounded, color: Palette.gray, size: 32),
            ),
            bubble(Icons.open_in_new_rounded, Palette.blue, 'Open'),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 26),
              child: Icon(Icons.arrow_forward_rounded, color: Palette.gray, size: 32),
            ),
            bubble(Icons.content_paste_rounded, Palette.purple, 'Paste'),
          ],
        ),
        const SizedBox(height: 24),
        ChunkyButton(
          label: 'Copy & open ManageBAC',
          icon: Icons.send_rounded,
          expand: false,
          onPressed: () {},
        ),
      ],
    );
  }
}

class _CalendarDemo extends StatelessWidget {
  const _CalendarDemo();

  @override
  Widget build(BuildContext context) {
    Widget row(String title, String sub, EventCategory c, bool done) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChunkyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 34,
              decoration: BoxDecoration(
                color: categoryColor(c),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? Palette.gray : Palette.ink,
                    ),
                  ),
                  Text(sub, style: const TextStyle(color: Palette.muted, fontSize: 12)),
                ],
              ),
            ),
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: done ? Palette.green : Palette.gray,
              size: 28,
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row('TOK exhibition', 'TOK · Mon', EventCategory.tok, true),
        row('EE first draft', 'Extended Essay · Wed', EventCategory.extendedEssay, false),
        row('Math paper 2', 'Exam · Fri', EventCategory.exam, false),
      ],
    );
  }
}

class _CalendarImportDemo extends StatelessWidget {
  const _CalendarImportDemo();

  @override
  Widget build(BuildContext context) {
    Widget row(String title, String sub, EventCategory c) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChunkyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 34,
              decoration: BoxDecoration(
                color: categoryColor(c),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(sub, style: const TextStyle(color: Palette.muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Palette.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.line, width: 2),
              ),
              child: const Icon(Icons.calendar_today_rounded, color: Palette.red, size: 32),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.arrow_forward_rounded, color: Palette.gray, size: 30),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/icon/app_icon.png', width: 64, height: 64),
            ),
          ],
        ),
        const SizedBox(height: 18),
        row('Math AA paper 2', 'Exam · Tue · School', EventCategory.exam),
        row('Chem lab report due', 'IA · Thu · School', EventCategory.internalAssessment),
      ],
    );
  }
}

class _PressingTaskDemo extends StatelessWidget {
  const _PressingTaskDemo();

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.flag_circle_rounded, color: Palette.red, size: 30),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MOST PRESSING',
                      style: TextStyle(
                        color: Palette.red,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'Math AA paper 2 mock',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    Text('Exam · in 3 days', style: TextStyle(color: Palette.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChunkyButton.outlined(
            label: 'Add to Reminders',
            icon: Icons.checklist_rounded,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _CrunchDemo extends StatelessWidget {
  const _CrunchDemo();

  @override
  Widget build(BuildContext context) {
    final monday = DateUtils.dateOnly(DateTime.now())
        .subtract(Duration(days: DateTime.now().weekday - 1));
    final loads = [
      (2, LoadLevel.light),
      (4, LoadLevel.moderate),
      (10, LoadLevel.crunch),
      (6, LoadLevel.heavy),
      (1, LoadLevel.light),
      (3, LoadLevel.moderate),
    ];
    final weeks = [
      for (final (i, (load, level)) in loads.indexed)
        WeekLoad(
          weekStart: monday.add(Duration(days: 7 * i)).toUtc(),
          load: load,
          level: level,
          eventCount: load ~/ 2,
          majorTitles: const [],
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CrunchCard(
          warning: CrunchWarning(
            weekStart: weeks[2].weekStart,
            weeksAway: 2,
            level: LoadLevel.crunch,
            title: 'Crunch week in 2 weeks',
            message: 'Exam, EE draft and IA land together. Start early!',
          ),
        ),
        const SizedBox(height: 10),
        WorkloadStrip(weeks: weeks, onSelect: (_) {}),
      ],
    );
  }
}

class _RemindersDemo extends StatelessWidget {
  const _RemindersDemo();

  @override
  Widget build(BuildContext context) {
    // A notification banner above a lock-screen Live Activity.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Palette.snow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.line, width: 2),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/icon/app_icon.png', width: 36, height: 36),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔥 Your 5-day streak is on the line',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Earn a little XP before midnight to keep it.',
                      style: TextStyle(color: Palette.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2B2B),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Palette.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '5-day streak at risk',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Ends in 4:12:33',
                      style: TextStyle(
                        color: Palette.orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    ChunkyProgressBar(value: 0.3, height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AchievementsDemo extends StatelessWidget {
  const _AchievementsDemo();

  @override
  Widget build(BuildContext context) {
    const icons = [
      (Icons.edit_note_rounded, true),
      (Icons.local_fire_department_rounded, true),
      (Icons.category_rounded, true),
      (Icons.verified_rounded, false),
      (Icons.groups_rounded, false),
      (Icons.menu_book_rounded, false),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      children: [
        for (final (icon, unlocked) in icons)
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: unlocked ? Palette.yellow : Palette.snow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: unlocked ? Palette.yellowLip : Palette.line,
                width: 3,
              ),
            ),
            child: Icon(icon, color: unlocked ? Colors.white : Palette.gray, size: 38),
          ),
      ],
    );
  }
}

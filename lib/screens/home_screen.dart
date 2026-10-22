import 'package:flutter/material.dart';

import '../app_state.dart';
import '../src/rust/api/app.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/event_tile.dart';
import '../widgets/workload.dart';
import 'reflection_editor.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate});

  /// Switches the shell to another tab (indices as in `Shell`).
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ReloadOnChange<Dashboard>(
        load: getDashboard,
        builder: (context, d) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _StatsBar(dashboard: d),
            const SizedBox(height: 20),
            Text(
              d.displayName.isEmpty ? 'Welcome back!' : 'Hi, ${d.displayName}!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            if (d.crunch case final crunch?) ...[
              CrunchCard(warning: crunch, onTap: () => onNavigate(3)),
              const SizedBox(height: 16),
            ],
            _DailyGoalCard(dashboard: d),
            const SizedBox(height: 16),
            ChunkyButton(
              label: 'Write a reflection',
              icon: Icons.edit_rounded,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReflectionEditor()),
              ),
            ),
            if (d.draftCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: () => onNavigate(2),
                  child: Text(
                    '${d.draftCount} draft${d.draftCount == 1 ? '' : 's'} waiting to be sent to ManageBAC',
                    style: const TextStyle(color: Palette.blue),
                  ),
                ),
              ),
            const SectionTitle('Learning outcomes'),
            _OutcomesCard(coverage: d.outcomeCoverage),
            const SectionTitle('Strand balance'),
            _StrandBalance(counts: d.strandBalance),
            SectionTitle(
              'Up next',
              trailing: TextButton(
                onPressed: () => onNavigate(3),
                child: const Text('SEE ALL'),
              ),
            ),
            if (d.upcoming.isEmpty)
              const ChunkyCard(
                child: Text(
                  'Nothing coming up. Add deadlines in the Calendar tab so nothing sneaks up on you.',
                  style: TextStyle(color: Palette.muted),
                ),
              )
            else
              for (final e in d.upcoming) EventTile(event: e, showDate: true),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    Widget stat(IconData icon, Color color, String value, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        stat(
          Icons.local_fire_department_rounded,
          d.streak.current > 0 ? Palette.orange : Palette.gray,
          '${d.streak.current}',
          'Day streak (best ${d.streak.best})',
        ),
        stat(Icons.bolt_rounded, Palette.yellow, '${d.totalXp}', 'Total XP'),
        stat(
          Icons.shield_rounded,
          Palette.blue,
          'Lv ${d.level.level}',
          '${d.level.xpIntoLevel} / ${d.level.xpForNextLevel} XP to next level',
        ),
      ],
    );
  }
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    final done = d.todayXp >= d.dailyGoalXp;
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  done ? 'Daily goal reached!' : 'Daily goal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${d.todayXp} / ${d.dailyGoalXp} XP',
                style: const TextStyle(
                  color: Palette.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ChunkyProgressBar(
            value: d.dailyGoalXp == 0 ? 0 : d.todayXp / d.dailyGoalXp,
            color: done ? Palette.yellow : Palette.green,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final day in d.week) _WeekDay(day: day)],
          ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({required this.day});

  final DayActivity day;

  @override
  Widget build(BuildContext context) {
    final active = day.xp > 0;
    return Column(
      children: [
        Text(
          day.weekdayLabel,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: day.isToday ? Palette.orange : Palette.gray,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Palette.orange : Palette.snow,
            border: Border.all(
              color: active ? Palette.orangeLip : Palette.line,
              width: 2,
            ),
          ),
          child: active
              ? const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.white,
                  size: 18,
                )
              : null,
        ),
      ],
    );
  }
}

class _OutcomesCard extends StatelessWidget {
  const _OutcomesCard({required this.coverage});

  final List<OutcomeCoverage> coverage;

  @override
  Widget build(BuildContext context) {
    final covered = coverage.where((c) => c.reflections > 0).length;
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$covered of 7 evidenced',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Tag outcomes in your reflections. You need all 7 to complete CAS.',
            style: TextStyle(color: Palette.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final c in coverage) _OutcomeBadge(coverage: c)],
          ),
        ],
      ),
    );
  }
}

class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge({required this.coverage});

  final OutcomeCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final o = coverage.outcome;
    final done = coverage.reflections > 0;
    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      message:
          'LO${o.number()}: ${o.description()}\n${coverage.reflections} reflection${coverage.reflections == 1 ? '' : 's'}',
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? Palette.green : Palette.snow,
          border: Border.all(
            color: done ? Palette.greenLip : Palette.line,
            width: 3,
          ),
        ),
        child: done
            ? const Icon(Icons.check_rounded, color: Colors.white)
            : Text(
                '${o.number()}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Palette.gray,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}

class _StrandBalance extends StatelessWidget {
  const _StrandBalance({required this.counts});

  final List<StrandCount> counts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in counts) ...[
          Expanded(
            child: ChunkyCard(
              borderColor: strandColor(c.strand),
              color: strandColor(c.strand).withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  Icon(
                    strandIcon(c.strand),
                    color: strandColor(c.strand),
                    size: 30,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${c.experiences}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: strandLip(c.strand),
                    ),
                  ),
                  Text(
                    c.strand.label(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (c != counts.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

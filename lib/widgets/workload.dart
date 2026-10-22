import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../src/rust/api/types.dart';
import '../theme.dart';
import 'chunky.dart';

Color loadColor(LoadLevel level) => switch (level) {
  LoadLevel.light => Palette.green,
  LoadLevel.moderate => Palette.yellow,
  LoadLevel.heavy => Palette.orange,
  LoadLevel.crunch => Palette.red,
};

Color loadLip(LoadLevel level) => switch (level) {
  LoadLevel.light => Palette.greenLip,
  LoadLevel.moderate => Palette.yellowLip,
  LoadLevel.heavy => Palette.orangeLip,
  LoadLevel.crunch => Palette.redLip,
};

/// Heads-up about an upcoming busy or crunch week.
class CrunchCard extends StatelessWidget {
  const CrunchCard({super.key, required this.warning, this.onTap});

  final CrunchWarning warning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = loadColor(warning.level);
    return ChunkyCard(
      onTap: onTap,
      borderColor: color,
      color: color.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning.level == LoadLevel.crunch
                ? Icons.warning_rounded
                : Icons.event_busy_rounded,
            color: color,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  warning.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: loadLip(warning.level)),
                ),
                const SizedBox(height: 2),
                Text(warning.message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One bar per upcoming week, coloured and sized by workload.
class WorkloadStrip extends StatelessWidget {
  const WorkloadStrip({super.key, required this.weeks, required this.onSelect});

  final List<WeekLoad> weeks;
  final ValueChanged<DateTime> onSelect;

  static const _barMax = 64.0;

  @override
  Widget build(BuildContext context) {
    final maxLoad = weeks.fold<int>(9, (m, w) => w.load > m ? w.load : m);
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weeks ahead',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, w) in weeks.indexed)
                Expanded(
                  child: Tooltip(
                    message:
                        '${w.level.label()}: ${w.eventCount} '
                        'deadline${w.eventCount == 1 ? '' : 's'}'
                        '${w.majorTitles.isEmpty ? '' : '\n${w.majorTitles.join(', ')}'}',
                    child: GestureDetector(
                      onTap: () => onSelect(w.weekStart.toLocal()),
                      child: Column(
                        children: [
                          Container(
                            height: 4 + _barMax * w.load / maxLoad,
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: w.load == 0
                                  ? Palette.line
                                  : loadColor(w.level),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            i == 0
                                ? 'Now'
                                : DateFormat.MMMd().format(w.weekStart.toLocal()),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

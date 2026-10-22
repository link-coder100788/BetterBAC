import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../src/rust/api/calendar.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/event_tile.dart';
import '../widgets/workload.dart';
import 'event_form.dart';

class _MonthData {
  _MonthData(this.overview, this.events, this.workload);
  final MonthOverview overview;
  final List<CalendarEvent> events;
  final WorkloadOutlook workload;
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateUtils.dateOnly(DateTime.now());

  Future<_MonthData> _load() async {
    final next = DateTime(_month.year, _month.month + 1);
    return _MonthData(
      await monthOverview(year: _month.year, month: _month.month),
      await eventsBetween(start: _month.toUtc(), end: next.toUtc()),
      await workloadOutlook(weeks: 6),
    );
  }

  void _shiftMonth(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _selected = _month;
  });

  void _goToDay(DateTime day) => setState(() {
    _month = DateTime(day.year, day.month);
    _selected = DateUtils.dateOnly(day);
  });

  void _goToday() => setState(() {
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateUtils.dateOnly(now);
  });

  List<CalendarEvent> _eventsOn(DateTime day, List<CalendarEvent> events) {
    final start = day;
    final end = DateTime(day.year, day.month, day.day + 1);
    return events.where((e) {
      final s = e.startsAt.toLocal();
      final f = (e.endsAt ?? e.startsAt).toLocal();
      return s.isBefore(end) && !f.isBefore(start);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          TextButton(onPressed: _goToday, child: const Text('TODAY')),
        ],
      ),
      body: ReloadOnChange<_MonthData>(
        key: ValueKey(_month),
        load: _load,
        builder: (context, data) {
          final dayEvents = _eventsOn(_selected, data.events);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (data.workload.warning case final warning?) ...[
                CrunchCard(
                  warning: warning,
                  onTap: () => _goToDay(warning.weekStart.toLocal()),
                ),
                const SizedBox(height: 12),
              ],
              WorkloadStrip(weeks: data.workload.weeks, onSelect: _goToDay),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded, size: 32),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM().format(_month),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _MonthGrid(
                overview: data.overview,
                selected: _selected,
                onSelect: (d) => setState(() => _selected = d),
              ),
              SectionTitle(DateFormat.MMMMEEEEd().format(_selected)),
              if (dayEvents.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Nothing planned.',
                    style: TextStyle(color: Palette.muted),
                  ),
                )
              else
                for (final e in dayEvents) EventTile(event: e),
              const SizedBox(height: 8),
              ChunkyButton(
                label: 'Add event',
                icon: Icons.add_rounded,
                color: Palette.blue,
                lipColor: Palette.blueLip,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EventForm(initialDay: _selected),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.overview,
    required this.selected,
    required this.onSelect,
  });

  final MonthOverview overview;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final cells = <Widget>[
      for (final l in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(
          child: Text(
            l,
            style: const TextStyle(
              color: Palette.gray,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      for (var i = 0; i < overview.leadingBlanks; i++) const SizedBox(),
      for (final d in overview.days)
        _DayCell(
          summary: d,
          date: DateTime(overview.year, overview.month, d.day),
          isToday: DateTime(overview.year, overview.month, d.day) == today,
          isSelected: DateTime(overview.year, overview.month, d.day) == selected,
          onTap: onSelect,
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.summary,
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DaySummary summary;
  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (isSelected) {
      bg = Palette.blue;
      fg = Colors.white;
    } else if (isToday) {
      bg = Palette.blue.withValues(alpha: 0.12);
      fg = Palette.blueLip;
    } else {
      bg = Colors.transparent;
      fg = Palette.ink;
    }
    return GestureDetector(
      onTap: () => onTap(date),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${summary.day}',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final c in summary.categories.take(3))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : categoryColor(c),
                        shape: BoxShape.circle,
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

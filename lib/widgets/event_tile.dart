import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../screens/event_form.dart';
import '../src/rust/api/calendar.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import 'chunky.dart';

/// One calendar event with a tick-off circle. Tapping opens the editor.
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.showDate = false});

  final CalendarEvent event;
  final bool showDate;

  String _when() {
    final start = event.startsAt.toLocal();
    final date = DateFormat.MMMEd().format(start);
    if (event.allDay) return showDate ? date : 'All day';
    final time = DateFormat.jm().format(start);
    return showDate ? '$date · $time' : time;
  }

  Future<void> _toggle(BuildContext context) async {
    final xp = await guard(
      context,
      () => setEventCompleted(id: event.id, completed: !event.completed),
    );
    if (xp == null) return;
    notifyDataChanged();
    if (context.mounted) showXp(context, xp, message: 'Task complete!');
  }

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(event.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ChunkyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: event.editable
            ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EventForm(event: event)),
              )
            : null,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      decoration: event.completed
                          ? TextDecoration.lineThrough
                          : null,
                      color: event.completed ? Palette.gray : Palette.ink,
                    ),
                  ),
                  Text(
                    [
                      event.category.label(),
                      _when(),
                      ?event.calendarName,
                    ].join(' · '),
                    style: const TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (event.editable)
              IconButton(
                tooltip: event.completed ? 'Mark not done' : 'Mark done',
                onPressed: () => _toggle(context),
                icon: Icon(
                  event.completed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: event.completed ? Palette.green : Palette.gray,
                  size: 32,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

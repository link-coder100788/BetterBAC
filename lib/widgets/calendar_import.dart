import 'package:device_calendar_import/device_calendar_import.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../device_calendar.dart';
import '../src/rust/api/device_calendar.dart';
import '../theme.dart';
import 'chunky.dart';

/// Shown on the Calendar tab until the device calendar is connected.
class CalendarImportCard extends StatelessWidget {
  const CalendarImportCard({super.key});

  @override
  Widget build(BuildContext context) {
    final name = DeviceCalendar.providerName;
    return ChunkyCard(
      borderColor: Palette.blue,
      color: Palette.blue.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat_rounded, color: Palette.blue, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bring in your $name',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'See your exams and school deadlines here, and let them count '
            'towards crunch-week warnings. BetterBAC only reads your calendar.',
            style: TextStyle(color: Palette.muted),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: 'Connect',
            icon: Icons.link_rounded,
            color: Palette.blue,
            lipColor: Palette.blueLip,
            onPressed: () => connectDeviceCalendar(context),
          ),
        ],
      ),
    );
  }
}

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String _importedMessage(DeviceImportSummary? s) {
  if (s == null) return 'Calendar connected.';
  final n = s.added;
  return 'Calendar connected: imported $n event${n == 1 ? '' : 's'}.';
}

/// First-time flow: permission → choose calendars → import.
Future<void> connectDeviceCalendar(BuildContext context) async {
  final calendars = await guard(context, DeviceCalendar.connect);
  if (!context.mounted) return;
  if (calendars == null) {
    _snack(
      context,
      'Allow calendar access for BetterBAC in your device settings to import events.',
    );
    return;
  }
  final picked = await _pickCalendars(
    context,
    calendars,
    {for (final c in calendars) if (c.suggested) c.id},
    managing: false,
  );
  if (picked == null || !context.mounted) return;
  final summary = await guard(context, () => DeviceCalendar.enable(picked.ids));
  if (context.mounted) _snack(context, _importedMessage(summary));
}

/// Change calendars, sync now, or stop importing.
Future<void> manageDeviceCalendar(BuildContext context, DeviceCalendarPrefs prefs) async {
  final calendars = await guard(context, DeviceCalendar.calendars);
  if (calendars == null || !context.mounted) return;
  final picked = await _pickCalendars(
    context,
    calendars,
    prefs.calendarIds.toSet(),
    managing: true,
  );
  if (picked == null || !context.mounted) return;
  if (picked.stop) {
    await guard(context, DeviceCalendar.disable);
    if (context.mounted) _snack(context, 'Stopped importing. Imported events removed.');
    return;
  }
  final summary = await guard(context, () => DeviceCalendar.enable(picked.ids));
  if (summary != null && context.mounted) {
    _snack(
      context,
      summary.changed()
          ? 'Synced: ${summary.added} new, ${summary.updated} updated, ${summary.removed} removed.'
          : 'Already up to date.',
    );
  }
}

class _Picked {
  const _Picked(this.ids, {this.stop = false});
  final Set<String> ids;
  final bool stop;
}

Future<_Picked?> _pickCalendars(
  BuildContext context,
  List<DeviceCalendarInfo> calendars,
  Set<String> initial, {
  required bool managing,
}) {
  final selected = {...initial};
  return showModalBottomSheet<_Picked>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(
              'Import from ${DeviceCalendar.providerName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick the calendars to bring in. Imported events are read-only '
              'and update automatically.',
              style: TextStyle(color: Palette.muted),
            ),
            const SizedBox(height: 12),
            if (calendars.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No calendars found on this device.'),
              ),
            for (final c in calendars)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: selected.contains(c.id),
                activeColor: Palette.green,
                onChanged: (on) => setSheetState(
                  () => on == true ? selected.add(c.id) : selected.remove(c.id),
                ),
                secondary: CircleAvatar(radius: 8, backgroundColor: c.color),
                title: Text(
                  c.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: c.account.isEmpty ? null : Text(c.account),
              ),
            const SizedBox(height: 16),
            ChunkyButton(
              label: managing
                  ? 'Save & sync'
                  : 'Import ${selected.length} calendar${selected.length == 1 ? '' : 's'}',
              icon: Icons.download_rounded,
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, _Picked(selected)),
            ),
            if (managing) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, const _Picked({}, stop: true)),
                style: TextButton.styleFrom(foregroundColor: Palette.red),
                child: const Text('STOP IMPORTING'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

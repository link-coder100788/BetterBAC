import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../src/rust/api/calendar.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/confirm.dart';

/// Create (when [event] is null) or edit a manual calendar event.
class EventForm extends StatefulWidget {
  const EventForm({super.key, this.event, this.initialDay});

  final CalendarEvent? event;
  final DateTime? initialDay;

  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  late final _title = TextEditingController(text: widget.event?.title);
  late final _notes = TextEditingController(text: widget.event?.notes);
  late EventCategory _category = widget.event?.category ?? EventCategory.cas;
  late bool _allDay = widget.event?.allDay ?? true;
  late DateTime _day = DateUtils.dateOnly(
    widget.event?.startsAt.toLocal() ?? widget.initialDay ?? DateTime.now(),
  );
  late TimeOfDay _startTime = TimeOfDay.fromDateTime(
    widget.event?.startsAt.toLocal() ?? DateTime(2000, 1, 1, 9),
  );
  late TimeOfDay _endTime = TimeOfDay.fromDateTime(
    widget.event?.endsAt?.toLocal() ?? DateTime(2000, 1, 1, 10),
  );
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() => start ? _startTime = picked : _endTime = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final draft = EventDraft(
      title: _title.text,
      notes: _notes.text,
      category: _category,
      startsAt: (_allDay ? _day : _at(_startTime)).toUtc(),
      endsAt: _allDay ? null : _at(_endTime).toUtc(),
      allDay: _allDay,
    );
    final navigator = Navigator.of(context);
    final existing = widget.event;
    final saved = await guard(
      context,
      () => existing == null
          ? createEvent(draft: draft)
          : updateEvent(id: existing.id, draft: draft),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved == null) return;
    notifyDataChanged();
    navigator.pop();
  }

  Future<void> _delete() async {
    final existing = widget.event!;
    final ok = await confirm(
      context,
      title: 'Delete "${existing.title}"?',
      message: "This can't be undone.",
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    if (!await attempt(context, () => deleteEvent(id: existing.id))) return;
    notifyDataChanged();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.jm();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event == null ? 'New event' : 'Edit event'),
        actions: [
          if (widget.event != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.event == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. EE first draft due'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SectionTitle('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in EventCategory.values)
                ChoiceTile(
                  label: c.label(),
                  color: categoryColor(c),
                  selected: c == _category,
                  onTap: () => setState(() => _category = c),
                ),
            ],
          ),
          const SectionTitle('When'),
          ChunkyButton.outlined(
            label: DateFormat.yMMMMEEEEd().format(_day),
            icon: Icons.event_rounded,
            onPressed: _pickDay,
          ),
          const SizedBox(height: 12),
          ChoiceTile(
            label: 'All day',
            icon: Icons.wb_sunny_rounded,
            color: Palette.orange,
            selected: _allDay,
            onTap: () => setState(() => _allDay = !_allDay),
          ),
          if (!_allDay) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChunkyButton.outlined(
                    label: time.format(_at(_startTime)),
                    icon: Icons.schedule_rounded,
                    onPressed: () => _pickTime(start: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('to'),
                ),
                Expanded(
                  child: ChunkyButton.outlined(
                    label: time.format(_at(_endTime)),
                    icon: Icons.schedule_rounded,
                    onPressed: () => _pickTime(start: false),
                  ),
                ),
              ],
            ),
          ],
          const SectionTitle('Notes'),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
          const SizedBox(height: 28),
          ChunkyButton(
            label: _saving ? 'Saving…' : 'Save',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

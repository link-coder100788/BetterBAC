import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../src/rust/api/cas.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';

/// Create (when [experience] is null) or edit a CAS experience.
class ExperienceForm extends StatefulWidget {
  const ExperienceForm({super.key, this.experience});

  final Experience? experience;

  @override
  State<ExperienceForm> createState() => _ExperienceFormState();
}

class _ExperienceFormState extends State<ExperienceForm> {
  late final _title = TextEditingController(text: widget.experience?.title);
  late final _description = TextEditingController(
    text: widget.experience?.description,
  );
  late final Set<Strand> _strands = {...?widget.experience?.strands};
  late bool _isProject = widget.experience?.isProject ?? false;
  late DateTime? _start = widget.experience?.startDate?.toLocal();
  late DateTime? _end = widget.experience?.endDate?.toLocal();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _start : _end) ?? _start ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final draft = ExperienceDraft(
      title: _title.text,
      description: _description.text,
      strands: Strand.values.where(_strands.contains).toList(),
      isProject: _isProject,
      startDate: _start?.toUtc(),
      endDate: _end?.toUtc(),
    );
    final navigator = Navigator.of(context);
    final existing = widget.experience;
    final xp = await guard(context, () async {
      if (existing == null) {
        return (await createExperience(draft: draft)).xpGained;
      }
      await updateExperience(id: existing.id, draft: draft);
      return 0;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (xp == null) return;
    notifyDataChanged();
    showXp(context, xp, message: 'Experience logged!');
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.experience == null ? 'New experience' : 'Edit experience'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.experience == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Volunteering at the food bank',
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SectionTitle('Strands'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in Strand.values)
                ChoiceTile(
                  label: s.label(),
                  icon: strandIcon(s),
                  color: strandColor(s),
                  selected: _strands.contains(s),
                  onTap: () => setState(
                    () => _strands.contains(s) ? _strands.remove(s) : _strands.add(s),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ChoiceTile(
            label: 'This is my CAS project',
            subtitle: 'A collaborative, month-long-or-more experience',
            icon: Icons.groups_rounded,
            color: Palette.green,
            selected: _isProject,
            onTap: () => setState(() => _isProject = !_isProject),
          ),
          const SectionTitle('Dates'),
          Row(
            children: [
              Expanded(
                child: ChunkyButton.outlined(
                  label: _start == null ? 'Start date' : fmt.format(_start!),
                  icon: Icons.event_rounded,
                  onPressed: () => _pickDate(start: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChunkyButton.outlined(
                  label: _end == null ? 'End date' : fmt.format(_end!),
                  icon: Icons.event_available_rounded,
                  onPressed: () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          const SectionTitle('Description'),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What is it, and what do you hope to get out of it?',
            ),
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

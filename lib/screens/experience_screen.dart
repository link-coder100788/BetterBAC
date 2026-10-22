import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../src/rust/api/cas.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/confirm.dart';
import 'cas_screen.dart';
import 'experience_form.dart';
import 'reflection_editor.dart';
import 'reflections_screen.dart';

class _ExperienceData {
  _ExperienceData(this.experience, this.reflections);
  final Experience experience;
  final List<Reflection> reflections;
}

class ExperienceScreen extends StatelessWidget {
  const ExperienceScreen({super.key, required this.id});

  final String id;

  Future<_ExperienceData> _load() async => _ExperienceData(
    await getExperience(id: id),
    await listReflections(experienceId: id),
  );

  Future<void> _delete(BuildContext context, Experience e) async {
    final ok = await confirm(
      context,
      title: 'Delete "${e.title}"?',
      message: 'Its reflections will be kept but unlinked.',
      action: 'Delete',
    );
    if (!ok || !context.mounted) return;
    final navigator = Navigator.of(context);
    if (!await attempt(context, () => deleteExperience(id: id))) return;
    navigator.pop();
    notifyDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ReloadOnChange<_ExperienceData>(
      load: _load,
      builder: (context, data) {
        final e = data.experience;
        final fmt = DateFormat.yMMMd();
        final dates = [
          if (e.startDate != null) fmt.format(e.startDate!.toLocal()),
          if (e.endDate != null) fmt.format(e.endDate!.toLocal()),
        ].join(' – ');
        return Scaffold(
          appBar: AppBar(
            title: Text(e.title),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExperienceForm(experience: e),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _delete(context, e),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              StrandPills(strands: e.strands, isProject: e.isProject),
              if (dates.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.event_rounded, size: 18, color: Palette.muted),
                    const SizedBox(width: 6),
                    Text(dates, style: const TextStyle(color: Palette.muted)),
                  ],
                ),
              ],
              if (e.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(e.description, style: const TextStyle(fontSize: 16)),
              ],
              const SizedBox(height: 24),
              ChunkyButton(
                label: 'Reflect on this',
                icon: Icons.edit_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReflectionEditor(experienceId: e.id),
                  ),
                ),
              ),
              SectionTitle('Reflections (${data.reflections.length})'),
              if (data.reflections.isEmpty)
                const Text(
                  'No reflections yet. Reflecting regularly is how you show growth.',
                  style: TextStyle(color: Palette.muted),
                )
              else
                for (final r in data.reflections) ReflectionCard(reflection: r),
            ],
          ),
        );
      },
    );
  }
}

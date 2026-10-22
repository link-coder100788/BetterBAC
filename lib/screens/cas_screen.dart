import 'package:flutter/material.dart';

import '../app_state.dart';
import '../src/rust/api/cas.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import 'experience_form.dart';
import 'experience_screen.dart';

class CasScreen extends StatelessWidget {
  const CasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CAS Experiences')),
      body: ReloadOnChange<List<Experience>>(
        load: listExperiences,
        builder: (context, experiences) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ChunkyButton(
              label: 'New experience',
              icon: Icons.add_rounded,
              color: Palette.blue,
              lipColor: Palette.blueLip,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExperienceForm()),
              ),
            ),
            const SizedBox(height: 20),
            if (experiences.isEmpty)
              const _EmptyState()
            else
              for (final e in experiences) ExperienceCard(experience: e),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.flag_circle_rounded, size: 96, color: Palette.line),
          const SizedBox(height: 12),
          Text(
            'No experiences yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Log the things you do for Creativity, Activity and Service. '
            'Then reflect on them to evidence your learning outcomes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted),
          ),
        ],
      ),
    );
  }
}

class StrandPills extends StatelessWidget {
  const StrandPills({super.key, required this.strands, this.isProject = false});

  final List<Strand> strands;
  final bool isProject;

  @override
  Widget build(BuildContext context) {
    Widget pill(String text, Color color, IconData icon) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in strands)
          pill(s.label(), strandLip(s), strandIcon(s)),
        if (isProject)
          pill('CAS Project', Palette.greenLip, Icons.groups_rounded),
      ],
    );
  }
}

class ExperienceCard extends StatelessWidget {
  const ExperienceCard({super.key, required this.experience});

  final Experience experience;

  @override
  Widget build(BuildContext context) {
    final e = experience;
    final color = e.strands.isEmpty ? Palette.gray : strandColor(e.strands.first);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ChunkyCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExperienceScreen(id: e.id)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                e.strands.isEmpty ? Icons.flag_rounded : strandIcon(e.strands.first),
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  StrandPills(strands: e.strands, isProject: e.isProject),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  '${e.reflectionCount}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Palette.blue,
                  ),
                ),
                const Text(
                  'reflections',
                  style: TextStyle(fontSize: 11, color: Palette.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

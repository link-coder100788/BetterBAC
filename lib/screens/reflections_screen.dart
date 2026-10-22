import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../src/rust/api/cas.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import 'reflection_editor.dart';

class ReflectionsScreen extends StatelessWidget {
  const ReflectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reflections')),
      body: ReloadOnChange<List<Reflection>>(
        load: () => listReflections(),
        builder: (context, reflections) {
          final drafts = reflections.where((r) => r.exportedAt == null).toList();
          final sent = reflections.where((r) => r.exportedAt != null).toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ChunkyButton(
                label: 'New reflection',
                icon: Icons.edit_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReflectionEditor()),
                ),
              ),
              if (reflections.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Text(
                    'Reflections you write here can be sent to ManageBAC with one tap.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.muted),
                  ),
                ),
              if (drafts.isNotEmpty) ...[
                SectionTitle('Drafts (${drafts.length})'),
                for (final r in drafts) ReflectionCard(reflection: r),
              ],
              if (sent.isNotEmpty) ...[
                SectionTitle('Sent to ManageBAC (${sent.length})'),
                for (final r in sent) ReflectionCard(reflection: r),
              ],
            ],
          );
        },
      ),
    );
  }
}

class ReflectionCard extends StatelessWidget {
  const ReflectionCard({super.key, required this.reflection});

  final Reflection reflection;

  @override
  Widget build(BuildContext context) {
    final r = reflection;
    final sent = r.exportedAt != null;
    final subtitle = [
      ?r.experienceTitle,
      '${r.wordCount} words',
      DateFormat.MMMd().format(r.updatedAt.toLocal()),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ChunkyCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReflectionEditor(reflectionId: r.id)),
        ),
        child: Row(
          children: [
            Icon(
              sent ? Icons.check_circle_rounded : Icons.edit_note_rounded,
              color: sent ? Palette.green : Palette.orange,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                  if (r.outcomes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final o in r.outcomes)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Palette.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'LO${o.number()}',
                              style: const TextStyle(
                                color: Palette.greenLip,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Palette.gray),
          ],
        ),
      ),
    );
  }
}

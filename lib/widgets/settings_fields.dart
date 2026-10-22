import 'package:flutter/material.dart';

import '../theme.dart';
import 'chunky.dart';

const dailyGoals = [
  (xp: 10, label: 'Casual'),
  (xp: 20, label: 'Regular'),
  (xp: 30, label: 'Serious'),
  (xp: 50, label: 'Intense'),
];

class DailyGoalPicker extends StatelessWidget {
  const DailyGoalPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final g in dailyGoals)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: ChoiceTile(
                label: g.label,
                subtitle: '${g.xp} XP per day',
                color: Palette.blue,
                selected: value == g.xp,
                onTap: () => onChanged(g.xp),
              ),
            ),
          ),
      ],
    );
  }
}

class CasLinkField extends StatelessWidget {
  const CasLinkField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.link_rounded),
            hintText: 'https://yourschool.managebac.com/student/…',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Open ManageBAC in your browser, go to the page where you add CAS '
          'reflections, and copy the link from the address bar.',
          style: TextStyle(color: Palette.muted, fontSize: 13),
        ),
      ],
    );
  }
}

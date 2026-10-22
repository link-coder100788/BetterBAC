import 'package:flutter/material.dart';

import '../app_state.dart';
import '../src/rust/api/app.dart';
import '../src/rust/api/dev.dart';
import '../src/rust/api/settings.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/settings_fields.dart';
import 'dev_menu_screen.dart';
import 'tutorial_screen.dart';

class _ProfileData {
  _ProfileData(this.dashboard, this.achievements, this.settings);
  final Dashboard dashboard;
  final List<Achievement> achievements;
  final Settings settings;
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static Future<_ProfileData> _load() async => _ProfileData(
    await getDashboard(),
    await getAchievements(),
    await getSettings(),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ReloadOnChange<_ProfileData>(
        load: _load,
        builder: (context, data) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Header(dashboard: data.dashboard),
            const SectionTitle('Achievements'),
            _AchievementGrid(achievements: data.achievements),
            const SectionTitle('Settings'),
            _SettingsForm(settings: data.settings),
            const SectionTitle('Help'),
            ChunkyButton.outlined(
              label: 'Replay the app tour',
              icon: Icons.school_rounded,
              onPressed: () => replayTutorial(context),
            ),
            if (devMenuEnabled())
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DevMenuScreen()),
                  ),
                  icon: const Icon(Icons.build_rounded, size: 18),
                  label: const Text('Developer menu'),
                  style: TextButton.styleFrom(foregroundColor: Palette.gray),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    final name = d.displayName.isEmpty ? '?' : d.displayName;
    Widget tile(IconData icon, Color color, String value, String label) =>
        Expanded(
          child: ChunkyCard(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: color, size: 28),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        );

    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: Palette.green,
          child: Text(
            name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Level ${d.level.level}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Palette.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChunkyProgressBar(
                value: d.level.xpIntoLevel / d.level.xpForNextLevel,
                color: Palette.blue,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${d.level.xpIntoLevel}/${d.level.xpForNextLevel}',
              style: const TextStyle(color: Palette.muted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            tile(
              Icons.local_fire_department_rounded,
              Palette.orange,
              '${d.streak.current}',
              'Day streak',
            ),
            const SizedBox(width: 10),
            tile(
              Icons.emoji_events_rounded,
              Palette.yellow,
              '${d.streak.best}',
              'Best streak',
            ),
            const SizedBox(width: 10),
            tile(Icons.bolt_rounded, Palette.yellow, '${d.totalXp}', 'Total XP'),
          ],
        ),
      ],
    );
  }
}

/// Maps the icon hints from Rust onto Material icons.
IconData _achievementIcon(String name) => switch (name) {
  'edit_note' => Icons.edit_note_rounded,
  'psychology' => Icons.psychology_rounded,
  'menu_book' => Icons.menu_book_rounded,
  'local_fire_department' => Icons.local_fire_department_rounded,
  'whatshot' => Icons.whatshot_rounded,
  'flag' => Icons.flag_rounded,
  'category' => Icons.category_rounded,
  'verified' => Icons.verified_rounded,
  'groups' => Icons.groups_rounded,
  'event_available' => Icons.event_available_rounded,
  _ => Icons.star_rounded,
};

class _AchievementGrid extends StatelessWidget {
  const _AchievementGrid({required this.achievements});

  final List<Achievement> achievements;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final a in achievements)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChunkyCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: a.unlocked ? Palette.yellow : Palette.snow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: a.unlocked ? Palette.yellowLip : Palette.line,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _achievementIcon(a.icon),
                      color: a.unlocked ? Colors.white : Palette.gray,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          a.description,
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ChunkyProgressBar(
                                value: a.progress / a.goal,
                                color: Palette.yellow,
                                height: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${a.progress}/${a.goal}',
                              style: const TextStyle(
                                color: Palette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.settings});

  final Settings settings;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final _name = TextEditingController(text: widget.settings.displayName);
  late final _url = TextEditingController(
    text: widget.settings.managebacCasUrl,
  );
  late int _goal = widget.settings.dailyGoalXp;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await guard(
      context,
      () => updateSettings(
        settings: Settings(
          displayName: _name.text,
          managebacCasUrl: _url.text,
          dailyGoalXp: _goal,
        ),
      ),
    );
    if (saved == null) return;
    _url.text = saved.managebacCasUrl ?? '';
    notifyDataChanged();
    messenger.showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Name', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),
        const Text(
          'ManageBAC CAS link',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        CasLinkField(controller: _url),
        const SizedBox(height: 20),
        const Text('Daily goal', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        DailyGoalPicker(
          value: _goal,
          onChanged: (g) => setState(() => _goal = g),
        ),
        const SizedBox(height: 20),
        ChunkyButton(label: 'Save settings', onPressed: _save),
      ],
    );
  }
}

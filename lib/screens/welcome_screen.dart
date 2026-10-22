import 'package:flutter/material.dart';

import '../app_state.dart';
import '../src/rust/api/settings.dart';
import '../src/rust/api/tutorial.dart';
import '../src/rust/api/types.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/settings_fields.dart';
import 'tutorial_screen.dart';

/// First-run setup: name, daily goal and (optionally) the ManageBAC link.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  int _goal = 20;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final navigator = Navigator.of(context);
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
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => TutorialScreen(
          steps: tutorialSteps(afterVersion: 0),
          continueToApp: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                const Icon(
                  Icons.school_rounded,
                  size: 88,
                  color: Palette.green,
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome to BetterBAC',
                  textAlign: TextAlign.center,
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'CAS, deadlines and reflections, all in one place.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.muted, fontSize: 16),
                ),
                const SectionTitle("What's your name?"),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'First name'),
                ),
                const SectionTitle('Pick a daily goal'),
                DailyGoalPicker(
                  value: _goal,
                  onChanged: (g) => setState(() => _goal = g),
                ),
                const SectionTitle('ManageBAC CAS link (optional)'),
                CasLinkField(controller: _url),
                const SizedBox(height: 32),
                ChunkyButton(
                  label: 'Get started',
                  onPressed: _name.text.trim().isEmpty ? null : _start,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

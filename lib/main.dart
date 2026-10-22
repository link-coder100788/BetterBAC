import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/shell.dart';
import 'screens/tutorial_screen.dart';
import 'screens/welcome_screen.dart';
import 'src/rust/api/app.dart';
import 'src/rust/api/settings.dart';
import 'src/rust/api/tutorial.dart';
import 'src/rust/frb_generated.dart';
import 'theme.dart';
import 'web/web_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  if (kIsWeb) {
    await startWebCore();
  } else {
    final dir = await getApplicationSupportDirectory();
    await initCore(dbPath: '${dir.path}/betterbac.sqlite3');
  }
  final settings = await getSettings();
  final tutorial = await tutorialStatus();
  runApp(
    BetterBacApp(
      needsWelcome: settings.displayName.isEmpty,
      tutorial: tutorial,
    ),
  );
}

class BetterBacApp extends StatelessWidget {
  const BetterBacApp({super.key, required this.needsWelcome, this.tutorial});

  final bool needsWelcome;

  /// When set and the tour is due, it shows before the app (full tour, or
  /// just the new steps after an update).
  final TutorialStatus? tutorial;

  Widget get _home {
    if (needsWelcome) return const WelcomeScreen();
    final t = tutorial;
    if (t != null && t.needsTour()) {
      return TutorialScreen(
        steps: tutorialSteps(afterVersion: t.isUpdate() ? t.seenVersion : 0),
        whatsNew: t.isUpdate(),
        continueToApp: true,
      );
    }
    return const Shell();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BetterBAC',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _home,
    );
  }
}

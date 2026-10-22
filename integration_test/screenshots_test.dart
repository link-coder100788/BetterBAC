// Renders each main screen with sample data and saves PNGs, for eyeballing
// the UI without a device. Run: flutter test integration_test/screenshots_test.dart -d macos
import 'dart:io';
import 'dart:ui' as ui;

import 'package:betterbac/screens/reflection_editor.dart';
import 'package:betterbac/screens/shell.dart';
import 'package:betterbac/screens/welcome_screen.dart';
import 'package:betterbac/src/rust/api/app.dart';
import 'package:betterbac/src/rust/api/calendar.dart';
import 'package:betterbac/src/rust/api/cas.dart';
import 'package:betterbac/src/rust/api/settings.dart';
import 'package:betterbac/src/rust/api/types.dart';
import 'package:betterbac/src/rust/frb_generated.dart';
import 'package:betterbac/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final _boundary = GlobalKey();
late Directory _out;

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  // Let fonts finish loading.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
  await tester.pumpAndSettle();
  final ro = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await ro.toImage(pixelRatio: 2);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!;
  });
  final file = File('${_out.path}/$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('SCREENSHOT ${file.path}');
}

Widget _frame(Widget home) => RepaintBoundary(
  key: _boundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: home,
  ),
);

Future<void> _seed() async {
  await updateSettings(
    settings: const Settings(displayName: 'Noah', managebacCasUrl: null, dailyGoalXp: 20),
  );
  final band = await createExperience(
    draft: const ExperienceDraft(
      title: 'School jazz band',
      description: 'Weekly rehearsals and the spring concert.',
      strands: [Strand.creativity],
      isProject: false,
    ),
  );
  await createExperience(
    draft: const ExperienceDraft(
      title: 'Food bank volunteering',
      description: '',
      strands: [Strand.service, Strand.activity],
      isProject: true,
    ),
  );
  final r = await saveReflection(
    draft: ReflectionDraft(
      experienceId: band.experience.id,
      title: 'Learning to improvise',
      body: List.filled(60, 'reflection').join(' '),
      outcomes: const [LearningOutcome.challenge, LearningOutcome.awareness],
    ),
  );
  await exportReflection(id: r.reflection.id);
  await saveReflection(
    draft: const ReflectionDraft(
      title: 'Concert nerves',
      body: 'Draft in progress',
      outcomes: [LearningOutcome.commitment],
    ),
  );
  final now = DateTime.now();
  for (final (i, title, cat) in [
    (1, 'EE first draft due', EventCategory.extendedEssay),
    (3, 'TOK exhibition', EventCategory.tok),
    (6, 'Math IA check-in', EventCategory.internalAssessment),
  ]) {
    await createEvent(
      draft: EventDraft(
        title: title,
        notes: '',
        category: cat,
        startsAt: DateTime(now.year, now.month, now.day + i, 15).toUtc(),
        allDay: false,
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
    _out = await Directory.systemTemp.createTemp('betterbac_shots');
    await initCore(dbPath: '${_out.path}/shots.sqlite3');
    await _seed();
  });

  testWidgets('screenshots', (tester) async {
    await binding.setSurfaceSize(const Size(400, 860));

    await tester.pumpWidget(_frame(const WelcomeScreen()));
    await _snap(tester, '0_welcome');

    await tester.pumpWidget(_frame(const Shell()));
    await _snap(tester, '1_home');

    for (final (i, icon) in [
      (2, Icons.flag_rounded),
      (3, Icons.edit_note_rounded),
      (4, Icons.calendar_month_rounded),
      (5, Icons.person_rounded),
    ]) {
      await tester.tap(find.byIcon(icon).last);
      await _snap(tester, '${i}_tab');
    }

    await tester.pumpWidget(_frame(const ReflectionEditor()));
    await _snap(tester, '6_editor');
  });
}

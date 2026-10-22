import 'dart:io';

import 'package:apple_coach/apple_coach.dart';

import 'package:betterbac/main.dart';
import 'package:betterbac/screens/dev_menu_screen.dart';
import 'package:betterbac/screens/tutorial_screen.dart';
import 'package:betterbac/src/rust/api/app.dart';
import 'package:betterbac/src/rust/api/calendar.dart';
import 'package:betterbac/src/rust/api/cas.dart';
import 'package:betterbac/src/rust/api/coach.dart';
import 'package:betterbac/src/rust/api/dev.dart';
import 'package:betterbac/src/rust/api/settings.dart';
import 'package:betterbac/src/rust/api/tutorial.dart';
import 'package:betterbac/src/rust/api/types.dart';
import 'package:betterbac/src/rust/frb_generated.dart';
import 'package:betterbac/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
    final dir = await Directory.systemTemp.createTemp('betterbac_test');
    await initCore(dbPath: '${dir.path}/test.sqlite3');
  });

  testWidgets('Welcome screen shows on first run', (tester) async {
    await tester.pumpWidget(const BetterBacApp(needsWelcome: true));
    expect(find.text('Welcome to BetterBAC'), findsOneWidget);
  });

  test('CAS flow through the Rust core', () async {
    await updateSettings(
      settings: const Settings(
        displayName: 'Noah',
        managebacCasUrl: 'school.managebac.com/student/ib/activity/cas',
        dailyGoalXp: 20,
      ),
    );

    final exp = await createExperience(
      draft: const ExperienceDraft(
        title: 'Food bank',
        description: '',
        strands: [Strand.service],
        isProject: false,
      ),
    );
    expect(exp.xpGained, 15);

    final saved = await saveReflection(
      draft: ReflectionDraft(
        experienceId: exp.experience.id,
        title: 'First shift',
        body: List.filled(40, 'word').join(' '),
        outcomes: const [LearningOutcome.collaboration],
      ),
    );
    expect(saved.xpGained, 5);

    final export = await exportReflection(id: saved.reflection.id);
    expect(export.url, 'https://school.managebac.com/student/ib/activity/cas');
    expect(export.xpGained, 22);

    final now = DateTime.now();
    final event = await createEvent(
      draft: EventDraft(
        title: 'EE draft due',
        notes: '',
        category: EventCategory.extendedEssay,
        startsAt: now.add(const Duration(days: 1)).toUtc(),
        allDay: false,
      ),
    );
    expect(await setEventCompleted(id: event.id, completed: true), 5);

    final d = await getDashboard();
    expect(d.totalXp, 15 + 5 + 22 + 5);
    expect(d.streak.current, 1);
    expect(
      d.outcomeCoverage
          .firstWhere((c) => c.outcome == LearningOutcome.collaboration)
          .reflections,
      1,
    );
    expect(d.crunch, isNull);

    // Three big deadlines in the same week, two weeks out -> crunch warning.
    final monday = now.subtract(Duration(days: now.weekday - 1));
    for (final (i, cat) in [
      EventCategory.exam,
      EventCategory.extendedEssay,
      EventCategory.internalAssessment,
    ].indexed) {
      await createEvent(
        draft: EventDraft(
          title: 'Big deadline $i',
          notes: '',
          category: cat,
          startsAt: DateTime(monday.year, monday.month, monday.day + 14 + i, 12).toUtc(),
          allDay: false,
        ),
      );
    }
    final outlook = await workloadOutlook(weeks: 6);
    expect(outlook.weeks[2].level, LoadLevel.crunch);
    expect(outlook.warning?.weeksAway, 2);
    expect((await getDashboard()).crunch?.title, 'Crunch week in 2 weeks');
  });

  test('Reflection coach: rules and Apple Intelligence', () async {
    const draft = ReflectionDraft(
      title: 'Food bank',
      body:
          'I was nervous before my first shift at the food bank. Working with '
          'a team of volunteers was hard at first, but I learned that asking '
          'questions is a strength. Next time I will organise the sorting table.',
      outcomes: [LearningOutcome.collaboration],
    );
    final rules = await coachWithRules(draft: draft);
    expect(rules.source, CoachSource.rules);
    expect(rules.tips, isNotEmpty);

    final status = await AppleCoach.status();
    // ignore: avoid_print
    print('APPLE_STATUS $status');
    if (status != AppleCoachStatus.available) return;

    final prompt = coachPrompt(draft: draft);
    final raw = await AppleCoach.generate(
      instructions: prompt.instructions,
      prompt: prompt.prompt,
    );
    // ignore: avoid_print
    print('APPLE_RAW $raw');
    final tips = (raw['tips'] as List).cast<Map>();
    final report = await coachWithAi(
      draft: draft,
      feedback: AiFeedback(
        headline: raw['headline'] as String,
        tips: [
          for (final t in tips)
            AiTip(kind: t['kind'] as String, title: t['title'] as String, body: t['body'] as String),
        ],
      ),
    );
    expect(report.source, CoachSource.appleIntelligence);
    expect(report.score, rules.score);
  });

  testWidgets('Tutorial: every step renders at phone size', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    // Render each step on its own: one frame is enough to surface layout
    // overflows, and avoids timing-dependent page/route animations.
    for (final step in tutorialSteps(afterVersion: 0)) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(step.id),
          theme: buildTheme(),
          home: TutorialScreen(steps: [step]),
        ),
      );
      await tester.pump();
      expect(find.text(step.title), findsOneWidget, reason: step.id);
      expect(tester.takeException(), isNull, reason: step.id);
    }
  });

  test('Tutorial: finishing records the version', () async {
    await markTutorialSeen();
    final status = await tutorialStatus();
    expect(status.needsTour(), isFalse);
    expect(status.seenVersion, status.currentVersion);
  });

  testWidgets('Developer menu: seed, inspect, query, clear', (tester) async {
    expect(devMenuEnabled(), isTrue);

    await devSeedSampleData();
    final d = await getDashboard();
    expect(d.streak.current, greaterThanOrEqualTo(7));
    expect(d.crunch, isNotNull);

    final db = await devDbOverview();
    expect(db.schemaVersion, 2);
    final reflections = db.tables.firstWhere((t) => t.name == 'reflections');
    expect(reflections.rows.toInt(), greaterThanOrEqualTo(4));

    final page = await devTable(table: 'experiences', offset: 0, limit: 10);
    expect(page.columns, contains('title'));
    expect(page.rows, isNotEmpty);
    expect(
      (await devQuery(sql: 'SELECT COUNT(*) FROM events')).rows.single.cells.single,
      isNot('0'),
    );
    await expectLater(devQuery(sql: 'DELETE FROM events'), throwsA(anything));

    // The menu renders at phone size without overflow.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(), home: const DevMenuScreen()),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('Developer menu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await devClearAll();
    final empty = await getDashboard();
    expect(empty.totalXp, 0);
    expect(empty.displayName, '');
    expect(await listExperiences(), isEmpty);
  });
}

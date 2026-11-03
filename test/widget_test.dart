import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goal/app.dart';

void main() {
  testWidgets('preview shows quests and navigation at phone size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LifeRpgApp());
    await tester.pumpAndSettle();
    expect(find.text('Your next chapter\nstarts today.'), findsOneWidget);
    expect(find.text('Take the scenic route'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Habits').last);
    await tester.pumpAndSettle();
    expect(find.text('Build your everyday magic.'), findsOneWidget);
    expect(find.text('Start with a glass of water'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Review').last);
    await tester.pumpAndSettle();
    expect(find.text('Pause. Reflect. Grow.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview cannot mutate progress', (tester) async {
    await tester.pumpWidget(const LifeRpgApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Complete quest').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Complete quest').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('read-only preview'), findsOneWidget);
    expect(find.text('Take the scenic route'), findsOneWidget);
  });

  testWidgets('desktop navigation has no layout overflow', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LifeRpgApp());
    await tester.pumpAndSettle();
    expect(find.text('life rpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Character').first);
    await tester.pumpAndSettle();
    expect(find.text('Five paths of growth'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quest dialog offers ChatGPT prompt in preview', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LifeRpgApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Get quests with AI'));
    await tester.pumpAndSettle();
    expect(find.text('Get your next quests'), findsOneWidget);
    expect(find.text('Copy prompt for ChatGPT'), findsOneWidget);
    // The paid AI planner needs an account, so the preview hides it.
    expect(find.text('Generate quests'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

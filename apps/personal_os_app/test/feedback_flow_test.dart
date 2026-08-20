import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/navigation/app_destination.dart';

void main() {
  testWidgets('task complete button records execution and task events',
      (tester) async {
    final composition = await _readyComposition(tester);
    final taskId = composition.controller.result!.taskIds.first;
    composition.controller.navigate(AppDestination.tasks);
    await tester.pump();

    await tester.tap(find.byKey(Key('complete-task-$taskId')));
    await tester.pumpAndSettle();

    expect(composition.controller.taskState(taskId), 'completed');
    expect(find.text('succeeded: task_completed'), findsOneWidget);
    expect(
      composition.eventStore
          .readEvents()
          .map((stored) => stored.event.eventType),
      containsAll(<String>['execution.recorded', 'task.completed']),
    );
  });

  testWidgets('task skip button records task skipped event', (tester) async {
    final composition = await _readyComposition(tester);
    final taskId = composition.controller.result!.taskIds.first;
    composition.controller.navigate(AppDestination.tasks);
    await tester.pump();

    await tester.tap(find.byKey(Key('skip-task-$taskId')));
    await tester.pumpAndSettle();

    expect(composition.controller.taskState(taskId), 'skipped');
    expect(find.text('succeeded: task_skipped'), findsOneWidget);
    expect(
      composition.eventStore
          .readEvents()
          .map((stored) => stored.event.eventType),
      contains('task.skipped'),
    );
  });

  testWidgets('review create and accept buttons record the full review path',
      (tester) async {
    final composition = await _readyComposition(tester);
    await composition.controller.completeTask(
      composition.controller.result!.taskIds.first,
    );
    composition.controller.navigate(AppDestination.review);
    await tester.pump();

    await tester.tap(find.byKey(const Key('create-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-review')));
    await tester.pumpAndSettle();

    expect(composition.controller.reviewState, 'accepted');
    expect(find.text('succeeded: review_accepted'), findsOneWidget);
    expect(
      composition.eventStore
          .readEvents()
          .map((stored) => stored.event.eventType),
      containsAll(<String>[
        'review.created',
        'review.user_reviewed',
        'review.accepted',
      ]),
    );
  });

  testWidgets('review create and reject buttons record rejection',
      (tester) async {
    final composition = await _readyComposition(tester);
    await composition.controller.completeTask(
      composition.controller.result!.taskIds.first,
    );
    composition.controller.navigate(AppDestination.review);
    await tester.pump();

    await tester.tap(find.byKey(const Key('create-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject-review')));
    await tester.pumpAndSettle();

    expect(composition.controller.reviewState, 'rejected');
    expect(find.text('succeeded: review_rejected'), findsOneWidget);
    expect(
      composition.eventStore
          .readEvents()
          .map((stored) => stored.event.eventType),
      containsAll(<String>[
        'review.created',
        'review.user_reviewed',
        'review.rejected',
      ]),
    );
  });

  testWidgets('review action remains disabled without task feedback',
      (tester) async {
    final composition = AppComposition.inMemoryDemo();
    await tester.pumpWidget(PersonalOsApp(composition: composition));
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();
    composition.controller.navigate(AppDestination.review);
    await tester.pump();

    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('create-review')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('先完成或跳过'), findsOneWidget);
    expect(composition.eventStore.readEvents(), isEmpty);
  });
}

Future<AppComposition> _readyComposition(WidgetTester tester) async {
  final composition = AppComposition.inMemoryDemo();
  await tester.pumpWidget(PersonalOsApp(composition: composition));
  await tester.tap(find.byKey(const Key('unlock-vault')));
  await tester.pump();
  composition.controller.setConsent(true);
  await composition.controller.analyzeBlobReference(
    blobReference: 'blob://vault/test-portrait',
    observationContext: 'front',
  );
  composition.controller.continueFromClaims();
  composition.controller.startPlan();
  await tester.pump();
  return composition;
}

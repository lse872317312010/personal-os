import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

void main() {
  testWidgets('offline Chinese MVP completes the guided appearance loop',
      (tester) async {
    final composition = AppComposition.inMemoryDemo();
    await tester.pumpWidget(PersonalOsApp(composition: composition));

    expect(find.textContaining('不上传云端'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();

    await tester.tap(find.text('开始首次分析'));
    await tester.pumpAndSettle();
    expect(find.text('内置合成示例'), findsOneWidget);
    expect(find.textContaining('不会读取相册'), findsOneWidget);

    // Lazy sliver controls must be built before interaction.
    await tester.scrollUntilVisible(
      find.byKey(const Key('analysis-consent')),
      300,
    );
    await tester.tap(find.byKey(const Key('analysis-consent')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('analyze-reference')),
      300,
    );
    await tester.tap(find.byKey(const Key('analyze-reference')));
    await tester.pumpAndSettle();

    expect(find.text('你的示例建议'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accept-suggestions')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start-plan')));
    await tester.pump();

    final taskId = composition.controller.result!.taskIds.first;
    await tester.tap(find.byKey(Key('complete-task-$taskId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('行动已记录'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-review')));
    await tester.pumpAndSettle();

    expect(find.textContaining('闭环完成'), findsOneWidget);
    expect(composition.controller.completedStep, 5);
  });

  testWidgets('analysis explains missing consent in Chinese', (tester) async {
    await tester.pumpWidget(
      PersonalOsApp(composition: AppComposition.inMemoryDemo()),
    );
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始首次分析'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('analyze-reference')),
      300,
    );
    await tester.tap(find.byKey(const Key('analyze-reference')));
    await tester.pump();

    expect(find.text('请先勾选本次分析授权。'), findsOneWidget);
  });

  testWidgets('task and review cannot bypass plan and feedback', (tester) async {
    final composition = AppComposition.inMemoryDemo();
    await tester.pumpWidget(PersonalOsApp(composition: composition));
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();

    await tester.tap(find.text('复盘'));
    await tester.pump();
    expect(find.byKey(const Key('create-review')), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(const Key('create-review'))).onPressed,
      isNull,
    );
    expect(find.textContaining('先完成或跳过'), findsOneWidget);
  });
}

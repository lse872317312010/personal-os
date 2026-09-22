import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

void main() {
  testWidgets('vault gate protects the shell and can be relocked',
      (tester) async {
    await tester.pumpWidget(
      PersonalOsApp(composition: AppComposition.inMemoryDemo()),
    );

    expect(find.text('我的 Personal OS'), findsOneWidget);
    expect(find.text('今天，从一个小改变开始'), findsNothing);

    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();
    expect(find.text('今天，从一个小改变开始'), findsOneWidget);
    expect(find.text('最近观察'), findsOneWidget);
    expect(find.textContaining('blob://'), findsNothing);

    await tester.tap(find.byKey(const Key('lock-vault')));
    await tester.pump();
    expect(find.text('我的 Personal OS'), findsOneWidget);
  });

  testWidgets('backgrounding revokes Vault and Agent access', (tester) async {
    final composition = AppComposition.inMemoryDemo();
    await tester.pumpWidget(
      PersonalOsApp(composition: composition),
    );
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();
    expect(find.text('今天，从一个小改变开始'), findsOneWidget);
    expect(
      composition.agentAccessController.start(vaultUnlocked: true),
      isTrue,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(find.text('我的 Personal OS'), findsOneWidget);
    expect(find.text('今天，从一个小改变开始'), findsNothing);
    expect(composition.agentAccessController.active, isFalse);
  });
}

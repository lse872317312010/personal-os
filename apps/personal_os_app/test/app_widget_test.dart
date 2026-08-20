import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';

void main() {
  testWidgets('vault gate protects the shell and can be relocked', (tester) async {
    await tester.pumpWidget(
      PersonalOsApp(composition: AppComposition.inMemoryDemo()),
    );

    expect(find.text('Personal Vault'), findsOneWidget);
    expect(find.text('今天从一次观察开始'), findsNothing);

    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pump();
    expect(find.text('今天从一次观察开始'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lock-vault')));
    await tester.pump();
    expect(find.text('Personal Vault'), findsOneWidget);
  });
}

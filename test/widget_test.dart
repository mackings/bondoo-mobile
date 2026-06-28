import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bondoo_mobile/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the sign-in experience for a signed-out user', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: BondooApp()));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('BONDOO'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}

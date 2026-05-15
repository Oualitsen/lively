import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('app launches and shows counter tab', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    // Counter tab is selected by default — the count starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}

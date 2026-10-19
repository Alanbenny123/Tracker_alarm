import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/widgets/location_disclosure.dart';

void main() {
  testWidgets(
    'location disclosure explains background use and can be declined',
    (tester) async {
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    accepted = await showLocationDisclosure(context),
                child: const Text('Enable location'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Enable location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('closed or not in use'), findsOneWidget);
      expect(find.textContaining('monitoring notification'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
    },
  );
}

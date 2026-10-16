import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/main.dart';

void main() {
  testWidgets('app buttons fit map overlays and dialog actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: createAppTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: Stack(
              children: [
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open map'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final context = tester.element(find.text('Open map'));
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('End trip?'),
            actions: [
              FilledButton(onPressed: () {}, child: const Text('End trip')),
            ],
          ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('End trip'), findsOneWidget);
  });
}

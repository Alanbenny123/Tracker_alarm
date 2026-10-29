import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/features/map/offline_maps_screen.dart';
import 'package:tracker_alarm/providers/offline_packs_provider.dart';
import 'package:tracker_alarm/services/offline_pack_store.dart';

class _CatalogController extends OfflinePacksController {
  _CatalogController() {
    catalog = [
      OfflinePackListing(
        id: 'goa',
        name: 'Goa',
        url: Uri.parse('https://example.com/goa.zip'),
      ),
      OfflinePackListing(
        id: 'kerala',
        name: 'Kerala',
        url: Uri.parse('https://example.com/kerala.zip'),
      ),
    ];
  }

  @override
  Future<void> refreshCatalog() async {}
}

void main() {
  testWidgets('region search filters and clears the available map list', (
    tester,
  ) async {
    final controller = _CatalogController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [offlinePacksProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: OfflineMapsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Goa'), findsOneWidget);
    expect(find.text('Kerala'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'kera');
    await tester.pump();
    expect(find.text('Goa'), findsNothing);
    expect(find.text('Kerala'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Punjab');
    await tester.pump();
    expect(
      find.text('No available regions match your search.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Clear region search'));
    await tester.pump();
    expect(find.text('Goa'), findsOneWidget);
    expect(find.text('Kerala'), findsOneWidget);
  });
}

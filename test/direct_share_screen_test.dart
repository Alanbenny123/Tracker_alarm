import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/main.dart';
import 'package:tracker_alarm/features/map/map_view.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/shared_location_service.dart';

import 'helpers/alarm_fakes.dart';
import 'helpers/raw_memory_storage.dart';

class _Native extends FakeNative {
  @override
  Stream<void> get statusChanges => const Stream.empty();
}

class _Location extends FakeLocation {
  @override
  Stream<Position> visibleUpdates() => const Stream.empty();
}

void main() {
  testWidgets(
    'direct shares replace an already open setup and search destination',
    (tester) async {
      String? pending = 'First place\nhttps://www.google.com/maps?q=9.9,76.7';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SharedLocationService.channel, (
        _,
      ) async {
        final text = pending;
        pending = null;
        return text;
      });
      const places = MethodChannel('tracker_alarm/places');
      final searches = <String>[];
      messenger.setMockMethodCallHandler(places, (call) async {
        final query = call.arguments['query'] as String;
        searches.add(query);
        return [
          {
            'name': query,
            'address': query,
            'latitude': 9.93,
            'longitude': 76.26,
          },
        ];
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SharedLocationService.channel, null);
        messenger.setMockMethodCallHandler(places, null);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWith((ref) => RawMemoryStorage()),
            geofenceProvider.overrideWithValue(_Native()),
            locationServiceProvider.overrideWithValue(_Location()),
          ],
          child: const TrackerAlarmApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('First place'), findsOneWidget);

      Future<void> share(String text) async {
        pending = text;
        final handled = Completer<void>();
        // This invokes the same Dart handler as Android MainActivity.acceptShare.
        messenger.handlePlatformMessage(
          SharedLocationService.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('sharedText'),
          ),
          (_) => handled.complete(),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        await handled.future;
      }

      await share('Second place\nhttps://www.google.com/maps?q=9.91,76.71');
      expect(find.text('Second place'), findsOneWidget);
      expect(find.text('First place'), findsNothing);
      final map = tester.widget<MapView>(find.byType(MapView));
      expect(map.destination?.latitude, 9.91);
      expect(map.destination?.longitude, 76.71);

      await share('https://www.google.com/maps/place/First+shop/data=!1sfirst');
      expect(searches.last, 'First shop');
      await share(
        'https://www.google.com/maps/place/Hello+pets,+Mamangalam/data=!1ssecond',
      );
      expect(searches.last, 'Hello pets, Mamangalam');
      expect(
        find.widgetWithText(TextField, 'Hello pets, Mamangalam'),
        findsOneWidget,
      );
      expect(find.text('First shop'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

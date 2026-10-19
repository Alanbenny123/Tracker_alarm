import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/main.dart';
import 'package:tracker_alarm/models/place.dart';
import 'package:tracker_alarm/features/map/map_view.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/shared_location_service.dart';

import 'helpers/alarm_fakes.dart';
import 'helpers/raw_memory_storage.dart';
import 'support/fake_maplibre.dart';

class _Native extends FakeNative {
  @override
  Stream<void> get statusChanges => const Stream.empty();
}

class _Location extends FakeLocation {
  @override
  Stream<Position> visibleUpdates() => const Stream.empty();
}

class _RetryShareService extends SharedLocationService {
  final received = <String>[];
  @override
  Future<Place?> parse(String text) async {
    received.add(text);
    if (received.length == 1) {
      throw const SharedLocationException(
        'Could not connect. Retry the shared link.',
      );
    }
    return stationA.copyWith(name: 'Resolved shared place');
  }
}

class _NamedShareService extends SharedLocationService {
  @override
  Future<Place?> parse(String text) async {
    resolvedQuery = "St. George's Syro-Malabar Church, Kalady";
    return null;
  }
}

void main() {
  for (final ambiguous in [false, true]) {
    testWidgets(
      ambiguous
          ? 'a shared place with multiple matching pins asks the user to choose'
          : 'a shared place without coordinates searches and selects its matching pin',
      (tester) async {
        const text = 'https://maps.app.goo.gl/wn1hjHyCztTvCcSZ6';
        final shared = stationA.copyWith(
          name: "St. George's Syro-Malabar Church",
          address: 'Kalady, Kerala',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var takes = 0;
        messenger.setMockMethodCallHandler(
          SharedLocationService.channel,
          (_) async => ++takes == 1 ? text : null,
        );
        const places = MethodChannel('tracker_alarm/places');
        final searches = <String>[];
        messenger.setMockMethodCallHandler(places, (call) async {
          searches.add(call.arguments['query'] as String);
          return [
            const Place(
              name: 'Unrelated church',
              address: 'Halifax, Canada',
              latitude: 44.65,
              longitude: -63.63,
            ).toJson(),
            stationB
                .copyWith(name: 'Kalady', address: 'Kalady, Kerala')
                .toJson(),
            shared.toJson(),
            if (ambiguous)
              stationB
                  .copyWith(
                    name: "St. George's Syro-Malabar Church",
                    address: 'Another address, Kalady, Kerala',
                  )
                  .toJson(),
          ];
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(
            SharedLocationService.channel,
            null,
          );
          messenger.setMockMethodCallHandler(places, null);
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storageProvider.overrideWith((ref) => RawMemoryStorage()),
              geofenceProvider.overrideWithValue(_Native()),
              locationServiceProvider.overrideWithValue(_Location()),
            ],
            child: TrackerAlarmApp(sharedLocationService: _NamedShareService()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(searches, ["St. George's Syro-Malabar Church, Kalady"]);
        expect(find.text('Unrelated church'), findsNothing);
        if (ambiguous) {
          expect(
            tester.widget<MapView>(find.byType(MapView)).destination,
            isNull,
          );
          expect(find.text('Confirm destination'), findsNothing);
          await tester.tap(find.text(shared.name).first);
          await tester.pumpAndSettle();
        }
        final map = tester.widget<MapView>(find.byType(MapView));
        expect(map.destination?.latitude, shared.latitude);
        expect(map.destination?.longitude, shared.longitude);
        final camera = FakeMapLibrePlatform.shared.states.last.camera!;
        expect(camera.center.lat, shared.latitude);
        expect(camera.center.lon, shared.longitude);
        expect(find.text('Confirm destination'), findsOneWidget);
        expect(
          find.textContaining('This link has no exact coordinates'),
          findsNothing,
        );
        await tester.tap(find.text('Confirm destination'));
        await tester.pumpAndSettle();
        expect(find.text('Destination alarm'), findsOneWidget);
        expect(find.text(shared.name), findsOneWidget);
        expect(
          tester.widget<MapView>(find.byType(MapView)).destination?.latitude,
          shared.latitude,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'a network failure offers Retry and never starts a generic worldwide search',
    (tester) async {
      const text =
          'Hello pets\nhttps://maps.app.goo.gl/fwc4aVUmk4fWWyfy5?g_st=aw';
      final service = _RetryShareService();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var takes = 0;
      messenger.setMockMethodCallHandler(
        SharedLocationService.channel,
        (_) async => ++takes == 1 ? text : null,
      );
      const places = MethodChannel('tracker_alarm/places');
      var searches = 0;
      messenger.setMockMethodCallHandler(places, (_) async {
        searches++;
        return [];
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
          child: TrackerAlarmApp(sharedLocationService: service),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Choose destination'), findsNothing);
      expect(searches, 0);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(service.received, [text, text]);
      expect(takes, 1);
      expect(find.text('Resolved shared place'), findsOneWidget);
      expect(searches, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../models/travel_mode.dart';
import '../services/offline_pack_store.dart';

final offlinePacksProvider = ChangeNotifierProvider<OfflinePacksController>(
  (ref) => OfflinePacksController()..load(),
);

class OfflinePacksController extends ChangeNotifier {
  OfflinePacksController({this.catalogUrl = defaultOfflinePackCatalogUrl});

  final String catalogUrl;
  OfflinePackStore? _store;
  Future<void>? _loading;
  bool _loaded = false;
  List<OfflinePack> packs = [];
  List<OfflinePackListing> catalog = [];
  bool loadingCatalog = false;
  String? catalogError;
  bool downloading = false;
  int receivedBytes = 0;
  int? totalBytes;
  String? error;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      _store ??= await OfflinePackStore.open();
      packs = await _store!.installed();
      _loaded = true;
      error = null;
    } catch (e) {
      error = 'Could not read offline maps: $e';
    }
    notifyListeners();
  }

  OfflinePack? covering(double latitude, double longitude) {
    for (final pack in packs) {
      if (pack.contains(latitude, longitude)) return pack;
    }
    return null;
  }

  Future<void> refreshCatalog() async {
    if (loadingCatalog) return;
    await load();
    if (_store == null) return;
    loadingCatalog = true;
    catalogError = null;
    notifyListeners();
    try {
      catalog = await _store!.catalog(Uri.parse(catalogUrl));
    } catch (_) {
      catalogError =
          'Could not load region list. Check your connection and retry.';
    } finally {
      loadingCatalog = false;
      notifyListeners();
    }
  }

  Future<void> download(Uri url) async {
    if (downloading) return;
    await load();
    if (_store == null) throw StateError(error ?? 'Offline maps unavailable');
    downloading = true;
    receivedBytes = 0;
    totalBytes = null;
    error = null;
    notifyListeners();
    try {
      await _store!.download(
        url,
        onProgress: (received, total) {
          receivedBytes = received;
          totalBytes = total;
          notifyListeners();
        },
      );
      packs = await _store!.installed();
    } catch (e) {
      error = 'Could not download offline map: $e';
      rethrow;
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  Future<void> delete(OfflinePack pack) async {
    await load();
    if (_store == null) throw StateError(error ?? 'Offline maps unavailable');
    await _store!.delete(pack);
    packs = await _store!.installed();
    notifyListeners();
  }

  Future<List<Place>> search(String query, {LatLng? near}) async {
    await load();
    return _store?.search(packs, query, near: near) ?? [];
  }

  Future<List<Place>> nearby(TravelMode mode, LatLng center) async {
    await load();
    return _store?.nearby(packs, mode, center) ?? [];
  }
}

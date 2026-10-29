# Offline India region packs

The app supports separate downloadable OpenStreetMap packs for India's 28 states and 8 union territories. A user can install several regions, such as Kerala and Tamil Nadu, independently from **Settings → Offline maps**. Each pack contains a searchable place list and locally rendered map tiles. Google Maps and Places remain the online option. GPS alarms use the stored destination coordinates after setup and do not require map data or a Places request.

The pack files are built locally under `offline-packs/builds/` and excluded from Git. They are **not available for one-tap download until the ZIPs are uploaded to a public HTTPS host and their real URLs are added to `offline-packs/catalog.json`**. Do not add catalog entries before the files are live. The app reads the catalog from the repository's `main` branch; users may also paste a direct HTTPS link.

## Build all regions

`tools/build_india_offline_packs.py` lists all 36 regions and uses the per-region PBF extracts and polygons from [OSM.fr](https://download.openstreetmap.fr/extracts/asia/india/). Install Python packages `osmium`, `Pillow`, and `Shapely`, then run:

```sh
python3 tools/build_india_offline_packs.py download --jobs 3
python3 tools/build_india_offline_packs.py build --jobs 2 --tile-budget 20000
python3 tools/build_india_offline_packs.py manifest
```

Use `--region kerala` (or another ID from the script) for a single region. Downloads are checked against the source's MD5 file. Completed ZIPs are validated before being listed in `offline-packs/builds/manifest.json`; the manifest includes sizes and SHA-256 checksums. The builder renders schematic roads, rail lines, waterways, and major labels from raw OSM data. It never fetches public OSM tile-server tiles. Each pack retains precise place coordinates even when the tile budget lowers the map's native zoom. The map can zoom further by enlarging the last rendered zoom, with less detail.

The ZIP root contains `pack.json`, `places.json`, and `tiles/{zoom}/{x}/{y}.png`. `pack.json` declares the region ID, name, bounds, exact polygon coverage, zoom range, native tile zoom, and place count. `places.json` includes named bus stops, metro and railway stations, shops, landmarks, and other mapped places with coordinates. Place completeness depends on local OpenStreetMap coverage and can differ from Google search.

## Publish one-tap downloads

1. Upload each ZIP as a separate static HTTPS asset, for example to a public GitHub Release. Keep the files out of the Git repository itself.
2. Verify every asset URL downloads the correct ZIP. Use the manifest's SHA-256 digest to check uploads.
3. Generate a catalog draft using the real asset directory URL, verify its links, and copy it to `offline-packs/catalog.json` on `main`:

```sh
python3 tools/build_india_offline_packs.py catalog \
  --base-url https://github.com/OWNER/REPO/releases/download/RELEASE_TAG
```

The draft is saved as `offline-packs/builds/catalog-to-publish.json`. An individual entry looks like:

```json
{"schema":1,"packs":[{"id":"kerala","name":"Kerala","url":"https://example.com/kerala-20261027.zip"}]}
```

The example URL is a placeholder, not a working download. The catalog may contain all 36 regions. A user can install any combination; they do not need a single full-India ZIP. Update the packs and catalog as map data changes. Downloading a prepared pack does not call Google Maps APIs.

## Validation and licensing

The app checks archive paths, size, tile format, metadata, and the place count before installation. A previously installed pack is retained if a replacement fails validation. Verify a real ZIP with:

```sh
flutter test test/offline_pack_artifact_test.dart \
  --dart-define=OFFLINE_PACK_PATH=/absolute/path/to/region.zip
```

The map and place data are derived from OpenStreetMap. Keep the **© OpenStreetMap contributors** attribution and comply with the ODbL when distributing packs. Do not create these packs from Google Maps or Google Places results. [OSM's public tile policy](https://operations.osmfoundation.org/policies/tiles/) prohibits bulk downloading their tiles for offline use. Test offline search, map display, and locked-screen GPS alarms on a physical phone before a Play release.

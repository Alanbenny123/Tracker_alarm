# Offline region packs

The app can install more than one prepared region pack from **Settings → Offline maps**. Each pack is a static HTTPS ZIP download, so no application server is required. The destination picker can search downloaded places and show downloaded map tiles without mobile data or Wi‑Fi. Google Maps and Places remain the online option.

The app loads a public static catalog from `offline-packs/catalog.json` on the repository's `main` branch. When a prepared pack is published, add an entry such as `{"id":"kerala","name":"Kerala","url":"https://.../kerala.zip"}` to that file and push it. The app then shows a **Download** button for Kerala without an app update. The catalog is deliberately empty until real pack files exist. A direct HTTPS pack link can also be pasted in the app.

## Pack format (version 1)

The ZIP root contains these paths:

```text
pack.json
places.json
tiles/{zoom}/{x}/{y}.png
```

`pack.json` example:

```json
{
  "schema": 1,
  "id": "kerala",
  "name": "Kerala",
  "bounds": {"south": 8.2, "west": 74.8, "north": 12.9, "east": 77.6},
  "minZoom": 6,
  "maxZoom": 15,
  "placeCount": 2
}
```

`places.json` is an array of named places. A place has `id`, `name`, `address`, `latitude`, `longitude`, and `type`. Type is one of `bus`, `metro`, `railway`, or `other`:

```json
[
  {"id":"n123", "name":"Example Metro", "address":"Kochi", "latitude":9.99, "longitude":76.30, "type":"metro"},
  {"id":"n456", "name":"Example Shop", "address":"Kochi", "latitude":9.99, "longitude":76.31, "type":"other"}
]
```

Tiles use the standard XYZ numbering scheme. Include all tiles needed at the advertised zoom levels; empty or missing tiles will appear blank. Each pack must contain both the map and the place list. Archives are validated before installation, and an existing pack is replaced only after the new copy is validated.

Build packs from OpenStreetMap raw data or another data source whose licence permits offline redistribution. Credit **© OpenStreetMap contributors** and comply with the ODbL for OSM-derived place data. Do not create packs from Google Maps or Google Places results. Do not bulk download from `tile.openstreetmap.org`, whose policy prohibits offline prefetching.

Prepared ZIP files can be hosted as static files, for example as release assets or object storage. Publish a separate URL for each region; users can install Kerala, Tamil Nadu, or any other supported region independently. Keep the ZIPs updated as places change.

The repository currently contains the app-side installer, offline search, and local map reader, plus synthetic pack tests. **No real state pack or hosted download URL is included yet.** A genuine region pack requires a licensed source extract, rendering of its tiles, and static hosting. Source tests do not establish how the map looks or how GPS alarms behave on a locked physical phone; those need device testing before a Play release.

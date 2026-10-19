# Transit search without hosting

The app uses two public Overpass instances in sequence: `overpass-api.de`, then `overpass.private.coffee` if the first connection times out, fails, returns HTTP 5xx, or returns an incomplete result. No new hosting account, API key, or server rental is required. This provides resilience for limited use, not a guaranteed backend for a widely distributed app. Public instances may be overloaded; their aggregate application usage limits still apply. See the [OpenStreetMap public-instance guidance](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances).

## Implemented behavior

- Only named stops/stations are requested, with the existing 2.5 km Bus/Metro and 5 km Railway radii and a 200-object response cap.
- At most one automatic fallback to the second server. HTTP 5xx or an incomplete result waits two seconds before fallback; a connection timeout or network error switches directly. The total lookup deadline is 50 seconds. Leaving or changing the search closes the client and prevents a later request.
- HTTP 429/406 applies a process-wide cooldown of at least 30 seconds. A longer `Retry-After`, in seconds or HTTP-date format, is respected. Clicking Retry or changing transport does not bypass that cooldown.
- Up to 64 area/category entries remain in memory across picker visits. Fresh results are reused for ten minutes. On refresh failure or cooldown, nonempty results for the same key can be shown with their age, until 24 hours after the original successful lookup. Using fallback results never extends that timestamp. No permanent stop database or offline basemap is created.
- Results exceeding 2 MB, malformed JSON/envelopes, or an Overpass `remark` indicating incomplete data are rejected instead of being cached as an empty success.
- MapLibre displays OpenFreeMap vector tiles with a dark raster backup. Place geocoding and Google Maps link resolution keep their existing providers. Destination alarm monitoring still works offline after setup.

## Practical limit

New areas still need internet and at least one working public provider. Cached stops can be missing or outdated. If search remains unavailable, use Other and choose a map point. Caching and server fallback reduce failures but do not create an uptime guarantee or remove public-service usage limits. A dependable contracted provider, local regional dataset, or owned backend remains a separate distribution decision; none was provisioned in this batch.

# Transit search without hosting

The app continues using the public Overpass endpoint. No new hosting account, API key, or server rental is required for the implemented changes. This provides resilience for limited use, not a guaranteed backend for a widely distributed app. Public instances may be overloaded; their aggregate application usage limits still apply. See the [OpenStreetMap public-instance guidance](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances).

## Implemented behavior

- Only named stops/stations are requested, with the existing 2.5 km Bus/Metro and 5 km Railway radii and a 200-object response cap.
- At most one automatic retry for HTTP 502/503/504, after two seconds; total lookup deadline is 50 seconds. Leaving or changing the search closes the client and prevents a later retry.
- HTTP 429/406 applies a process-wide cooldown of at least 30 seconds. A longer `Retry-After`, in seconds or HTTP-date format, is respected. Clicking Retry or changing transport does not bypass that cooldown.
- Up to 64 area/category entries remain in memory across picker visits. Fresh results are reused for ten minutes. On refresh failure or cooldown, nonempty results for the same key can be shown with their age, until 24 hours after the original successful lookup. Using fallback results never extends that timestamp. No permanent stop database or offline basemap is created.
- Results exceeding 2 MB, malformed JSON/envelopes, or an Overpass `remark` indicating incomplete data are rejected instead of being cached as an empty success.
- Place geocoding, map tiles and Google Maps link resolution keep their existing providers. Destination alarm monitoring still works offline after setup.

## Practical limit

New areas still need internet and a working public provider. Cached stops can be missing or outdated. If search remains unavailable, use Other and choose a map point. Caching reduces requests but does not create an uptime guarantee or remove public-service usage limits. A dependable contracted provider, local regional dataset, or owned backend remains a separate distribution decision; none was provisioned in this batch.

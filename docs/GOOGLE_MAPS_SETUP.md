# Google Maps setup

This app uses the native Google Maps SDK for Android and Places SDK for Android (New). It does not call the Places web service directly and needs no app server. Map and search need internet; GPS monitoring of a started trip works without internet.

1. Create a Google Cloud project, link a billing account, and enable **Maps SDK for Android** and **Places API (New)**.
2. Create an API key. Restrict its application to **Android apps** with package name `com.trackeralarm.app` and the SHA-1 fingerprint of the signing certificate. Add your local debug fingerprint for `flutter run`. Before Play release, add the **Play app signing key SHA-1**, which differs from the upload key.
3. Restrict the key to **Maps SDK for Android** and **Places API (New)**.
4. Put `GOOGLE_MAPS_API_KEY=YOUR_KEY` in `android/local.properties`. Do not commit this file or paste the key into source files. The key is embedded in the Android application at build time, so its Android and API restrictions are essential.
5. In **Google Maps Platform → Quotas**, set separate Text Search and Nearby Search limits that match your budget. Set billing alerts too; alerts do not stop spending. The app only searches on explicit user actions and reuses recent in-memory stop results, but client-side throttling cannot enforce a project-wide monthly ceiling.

The app uses only name, ID, location, and formatted address fields in Places search requests. These make Text and Nearby Search **Pro** requests. It does not call autocomplete, photos, reviews, routing, Street View, or 3D map services. Google determines billing by the highest requested field tier. Review the current price list and your billing account's eligibility before public release.

For a public Play release, publish the prepared [Terms of Use](TERMS_OF_USE.md) and [Privacy Policy](PRIVACY_POLICY.md) at stable public URLs. The in-app links currently point to those files on this repository's public `main` branch. Include Google's required terms and privacy links, and complete Play's background-location declaration. Google Places latitude/longitude values have a 30-day caching limit. Saved repeating alarms using a Google Places result still need a compliant refresh or expiry design; this work was deferred and is a release blocker. Do not treat the current local saved-place storage as unlimited permission to retain Google Places coordinates.

Sources: [Maps API key guidance](https://developers.google.com/maps/api-security-best-practices), [Places SDK policies](https://developers.google.com/maps/documentation/places/android-sdk/policies), [Places SDK billing](https://developers.google.com/maps/documentation/places/android-sdk/usage-and-billing), [Google Maps service terms](https://cloud.google.com/maps-platform/terms/maps-service-terms).

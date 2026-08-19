# App Store screenshots

Read Apple's current [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) before export. Keep screenshots and their ordered manifest in the app repository, using synthetic/non-sensitive data.

For each locale and display type: delete current ASC set, upload one ordered
batch, then read it back and verify count, identity, locale, display type and
order. Do not retry Fastlane screenshot upload during Connect eventual
consistency; retries can create duplicate images.

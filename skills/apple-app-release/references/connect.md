# Fastlane and App Store Connect

Registration needs both Developer Portal App ID and App Store Connect record;
query both by exact bundle ID. Confirm owner, name, primary locale and SKU
before creating the Connect record. `produce(skip_itc: false)` needs Apple-ID
session auth; use API-key auth for normal Fastlane/Connect operations.

Before review, read back selected VALID build, price/category, age rating,
privacy label, legal content-rights declaration, URLs and review contact. Use
current `reviewSubmissions` → `reviewSubmissionItems` → read-back → submit;
do not rely on retired version-submission endpoints.

Before an initial submission, Fastlane upgrade, or contradictory API response,
check [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi), [API release notes](https://developer.apple.com/documentation/appstoreconnectapi/release-notes), and [Connect Help](https://developer.apple.com/help/app-store-connect/). Record observed behaviour before adding a workaround.

# Privacy consistency contract

These are separate artifacts and must agree:

1. Source and shipped `PrivacyInfo.xcprivacy` (the binary manifest).
2. App Store Connect privacy nutrition label.
3. Public privacy page.

Audit actual call sites and SDKs, including analytics, ads, crash reporting,
network hosts, Keychain/storage, user accounts, and required-reason APIs. Do
not infer behaviour from a class name or copy a sibling app's declaration.

Before release, verify the public HTTPS URL returns 200, names the publisher's
contact method, accurately states collection/sharing/retention/deletion, and
matches the selected release profile's owner. A privacy page is not updated by
Fastlane automatically; version and publish it with the product site.

If the product has no own website, use GitHub Pages as the fallback: add the
page and Pages workflow/configuration to the app repository, enable Pages for
that repository, and verify the generated HTTPS URL before putting it into ASC
metadata. Do not use a README, a raw GitHub file URL, or a planned domain as a
privacy-policy URL.

# Capture, curation, and publish contract

Start from Apple's current [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), not a copied pixel table. Make an ordered manifest for every locale × device class with filename, scene, source capture, output size, and website slide order.

Use a deterministic demo fixture or an intentionally created public-safe
session. Review every final pixel for privacy. A mockup may frame a screenshot;
it must never replace its in-app contents. Use official Apple Design Resources
or a licensed high-resolution device frame and preserve the screen inset.

Connect upload is a transaction: list/delete the old locale/display set,
upload one ordered batch, then read it back to verify exact count, order and
locale. Do not rerun Fastlane screenshot retries during eventual consistency:
they can duplicate sets.

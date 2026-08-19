---
name: app-privacy-page
description: Create or audit a factory privacy-policy page for an Apple app. Use for app privacy pages, PrivacyInfo.xcprivacy consistency, App Store privacy labels, support URLs, and website deployment.
---

# App privacy page

Create a plain, deployable page from verified product behaviour—not a generic
legal claim. Keep it in the app repository/site source and link it from every
App Store locale.

## Workflow

1. Inspect app source, dependencies, `PrivacyInfo.xcprivacy`, networking,
   storage and account flows.
2. Read `references/consistency.md`; reconcile source facts, the binary
   manifest, ASC privacy label and page copy.
3. Write only claims supported by that audit. If data handling is uncertain,
   stop and ask the owner rather than claim “no data collected”.
4. Deploy and `curl` the exact HTTPS privacy URL before Fastlane metadata
   upload. Prefer the project's own product page; if it has none, publish the
   factory page to that repository's GitHub Pages and use its HTTPS URL.
   Re-audit for each material product or SDK change.

The factory has no publisher name, contact, domain, analytics statement, or
data claim. Those are user-provided project facts.

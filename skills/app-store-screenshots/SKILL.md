---
name: app-store-screenshots
description: Produce and publish privacy-safe, real iPhone/iPad App Store screenshot sets. Use for simulator/device capture, mockups, localization, screenshot ordering, website reuse, and transactional App Store Connect media upload.
---

# App Store screenshots

Screenshots are product evidence first, marketing composition second. Capture
the real app in a controlled demo state; use high-quality licensed/official
device frames only as presentation around the real pixels.

## Workflow

1. Read `references/capture.md`; define supported device/locale matrix and an
   ordered manifest before capturing.
2. Capture real simulator/device screens using synthetic but credible content.
   Never show personal workspaces, real hosts, tokens, contacts, local paths,
   or private session history.
3. For each locale, keep the same feature story and order across iPhone/iPad;
   revise copy/layout rather than literal overflowing translations.
4. Export current Apple-approved dimensions with no alpha. Use the manifest in
   both the website slideshow and Connect upload.
5. Hand off to `apple-app-release` for profile selection and the transactional
   ASC upload/read-back verification.

For the web preview/slideshow and canonical asset layout, read
`references/web-preview-and-assets.md`.

Do not draw device bezels by hand, invent fake in-app content when a controlled
real session can be captured, or mix superseded assets with the export set.

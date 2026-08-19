# Web preview and canonical asset layout

One approved screenshot set must feed both App Store Connect and the product
page. The web preview is a responsive review/export tool, not a second source
of images.

```text
assets/store/
  screenshots/
    en/
      iphone/  01-...png through 06-...png
      ipad/    01-...png through 06-...png
    zh-Hans/
      iphone/  01-...png through 06-...png
      ipad/    01-...png through 06-...png
  manifest.json             # canonical locale/device/order/scene matrix
  generator/                # local review/export UI, not deployed
  site/                     # product page + privacy page source
fastlane/store_screenshots/ # symlinks or copied formal exports only
```

The manifest owns slide order and maps each locale/device pair. Keep matching
counts and scene order across languages and iPhone/iPad unless the product
meaning genuinely differs. Remove rejected/old captures from candidate dirs;
never let a slideshow glob discover stale files.

## Product-page presentation

Use the approved formal exports inside a high-quality, correctly measured
iPhone/iPad frame. A tab control switches device class; the selected device
auto-advances through its manifest slides, with dot controls below the mockup
(never overlaying the screen). Support manual swipe/click and pause automatic
advance while the user interacts. Respect reduced motion.

On narrow viewports, allow vertical scrolling and show the complete device
mockup rather than clipping it. Keep page typography and decorative background
separate from store screenshot pixels. Do not display private-data disclaimers
or fake product claims inside the slide artwork.

Before publishing, test every locale/device selection, ensure all image URLs
are current formal exports, and verify the privacy-page link. The generator,
raw simulator captures, and metadata tooling must not be deployed.

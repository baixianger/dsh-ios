# DSH Pocket App Store screenshots

This folder contains the deterministic source for the iPhone App Store screenshot set. It deliberately lives outside `App/`, so product development can continue without a marketing-asset conflict.

## Current export

- `../fastlane/store_screenshots/en-US/`: two iPhone screenshots and two iPad screenshots selected for upload.
- `../fastlane/store_screenshots/zh-Hans/`: two Simplified Chinese iPhone screenshots selected for upload.
- iPhone files are 1320 × 2868 RGB PNGs; iPad A16 files are 1640 × 2360 high-quality JPEGs. Neither format has an alpha channel.

The screen interiors are native SwiftUI screenshots captured from the iPhone 17 Pro Max Simulator with `--store-screenshot-demo`. That launch argument uses only anonymized demonstration data and never contacts a DSH host. The outer warm-neutral card and official Apple device bezel are marketing composition only.

## Re-export

The page accepts `locale=en|zh`, `slide=1..2`, and `export=1`. It has no package dependencies. Run this from the repository root after copy or visual changes:

```sh
chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
page='file:///Users/baixianger/personal/dsh-ios/marketing/index.html'

"$chrome" --headless --disable-gpu --hide-scrollbars --window-size=1320,2868 \
  --screenshot="fastlane/store_screenshots/en-US/01-hero-iphone-1320x2868.png" \
  "$page?locale=en&slide=1&export=1"
```

Replace the raw files under `raw-screenshots/` only with newly captured native SwiftUI screenshots. Re-export both locales after doing so.

## Store name recommendation

Proposed App Store name: **DSH Pocket**.

Use “DeepSeek Harness in your pocket” as a marketing claim only after confirming trademark permission; if this is not an official DeepSeek app, do not use `DeepSeek` in the App Store title or subtitle.

# Pocket Dolphin · DSH — App Store assets

This directory is the single handoff package for the Pocket Dolphin · DSH App Store listing.
It contains only review-safe content; do not add screenshots of a personal DSH
host, device, workspace, session, file path, API credential, or token.

## Contents

| Path | Purpose |
| --- | --- |
| `marketing/en-US/` | Approved English App Store exports: exactly six each for iPhone and iPad. |
| `marketing/zh-Hans/` | Simplified-Chinese iPhone and iPad marketing exports. |
| `icon/app-icon-1024.png` | Store-ready 1024 × 1024 application icon. |
| `third-party/maya/` | MIT-licensed iPhone 16 Pro frame used only in iPhone marketing exports. |
| `third-party/app-store-screenshots/` | MIT-licensed iPad Pro 13-inch (M4/M5) landscape frame used only in iPad marketing exports. |
| `site/` | Product page and privacy-policy source for `https://impai.me/apps/dsh-remote/`. |

## Current screenshot dataset

Each locale and device class has exactly six approved exports. They use only
fictional or disposable content, with no personal workspaces, files,
credentials, or user data.

- `main` — the “Into the Unknown” starting surface
- `sidebar` — workspace and session overview
- `session` — a dedicated, disposable research conversation
- `setup1`, `setup2`, `setup3` — the three host-configuration steps

## Approved marketing direction

- Product name: **Pocket Dolphin · DSH**
- Bundle identifier: `me.impai.dsh`
- Locale: English (`en-US`)
- Art direction: neutral `#F3F3F4` store canvas, restrained two-level copy,
  a large framed device capture, and the original light-gray diagonal division.
- The iPad frame's 2752 × 2064 screen opening matches the iPad source captures
  exactly, so the app image is neither stretched nor cropped.
- The Nearto home-page language is reserved for `site/`, not App Store images.
- Proposed page URLs: `https://impai.me/apps/dsh-remote/` and
  `https://impai.me/apps/dsh-remote/privacy.html`

## Privacy gate

Before upload, reconcile the final privacy policy, App Store Connect privacy
answers, and any in-binary `PrivacyInfo.xcprivacy` against a source audit.
Credentials are stored locally in the device Keychain; screenshots must never
show their values.

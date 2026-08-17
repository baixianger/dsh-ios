# DeepSeek Harness iOS app icon

The icon combines the DeepSeek whale mark with the modular fluorescent material used by the latest Pharos icon. The palette is shifted from Pharos green to DeepSeek ocean blue, with the whale kept as the single central recognition cue.

## Files

- `variants/a4-frosted-slab.svg`: selected editable 1024×1024 production master.
- `deepseek-harness-icon.svg`: original editable master for candidate A, retained for comparison.
- `deepseek-mark.svg`: unmodified DeepSeek silhouette from Simple Icons, recolored with the catalogued DeepSeek blue `#4D6BFE`.
- `../../App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`: rendered iOS asset.
- `variants/comparison.png`: 2200×2400 selection board.
- `variants/*-60.png`: actual-size home-screen legibility checks.

## Candidates

- **A · Abyss Glow** — balanced deep-ocean field and luminous pearl whale; retained as the original exploration.
- **B · Electric Inverse** — dark whale with a cyan fluorescent edge; the strongest visual link to the latest Pharos modular icon.
- **C · Aurora Pearl** — brighter cyan-violet field with a large pearl whale; friendlier and more expressive.
- **D · Brand Core** — focused DeepSeek-blue field and restrained depth; the most product-like and brand-forward option.
- **A2 · Neon Black** — the selected A direction reduced to a true neon-sign treatment: a glowing rounded frame, a hollow glowing whale outline, and near-black negative space.
- **A3 · Modular Frost** — returns to A's filled fluorescent whale and overlays the scene with seamless, softly scattered glass tiles inspired by the supplied Orma reference.
- **A4 · Frosted Slab — selected** — replaces the tile mask with a Figma-style glass stack: refracted/blurred underlay, translucent surface wash, fine noise, clean filled whale, pure-black field, and a thick Pharos-derived inward fluorescent rim. The production master is square and full-bleed; iOS supplies the exact platform mask. This is the version installed in `AppIcon.appiconset`.
- **A5 · Neon Ripple** — keeps A4's black field and Modular Gradient Pack rim, then adds neon energy clipped inside the whale plus anisotropic pattern refraction for a wave-glass surface without an exterior halo.
- **A4R · Wave Glass** — preserves the selected A4 exactly underneath a restrained Figma Pattern Refraction-style cover: Waves, medium displacement strength, high smoothing, low frost, and no chromatic dispersion.

Every candidate contains an embedded copy of the same official vector path so exported assets do not depend on external SVG references.

## Rendering

```sh
rsvg-convert \
  --width 1024 \
  --height 1024 \
  --output App/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
  design/app-icon/variants/a4-frosted-slab.svg
```

The source is full-bleed, opaque, and contains no baked rounded-rectangle crop. Its fluorescent artwork follows a vector contour fitted to Apple’s current iOS app-icon grid, so the rim remains concentric when iOS applies the final platform mask. Don’t export the contour as transparency or pre-cut transparent corners into the App Icon PNG.

## Sources and trademark note

- DeepSeek mark: Simple Icons `deepseek`, CC0-1.0, catalogued brand color `#4D6BFE`.
- Shape cross-check: the current inline logo on `deepseek.com`.
- Material reference: Pharos `Modular Gradient Pack` design process, Figma node `3:453` / content node `3:456`.
- iOS enclosure reference: Apple Human Interface Guidelines app-icon grid (`app-icons-settings-app-grid-square`).

DeepSeek's terms reserve its trademarks and logo. This asset is suitable as a design/internal integration draft; obtain the relevant permission before public distribution if the app is not an official DeepSeek product.

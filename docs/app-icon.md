# Dudo app icon

The Dudo mark is a low-poly scarlet macaw head on a deep navy field.

This document covers two things: the icon that ships **today**, and the manual
Icon Composer step that applies Apple's Liquid Glass material. They are
independent — the app builds and archives with a correct icon whether or not the
Icon Composer step is ever performed.

---

## 1. What ships today

`Dudo/Assets.xcassets/AppIcon.appiconset/` is populated and compiles clean. This is
the classic asset-catalog path and it is what unblocks archiving and TestFlight.

| File | Size | Alpha | Used for |
|---|---|---|---|
| `AppIcon-iOS-1024.png` | 1024 | **no** | iPhone and iPad; Xcode derives every runtime size from it |
| `AppIcon-mac-16x16@1x.png` | 16 | yes | macOS |
| `AppIcon-mac-16x16@2x.png` | 32 | yes | macOS |
| `AppIcon-mac-32x32@1x.png` | 32 | yes | macOS |
| `AppIcon-mac-32x32@2x.png` | 64 | yes | macOS |
| `AppIcon-mac-128x128@1x.png` | 128 | yes | macOS |
| `AppIcon-mac-128x128@2x.png` | 256 | yes | macOS |
| `AppIcon-mac-256x256@1x.png` | 256 | yes | macOS |
| `AppIcon-mac-256x256@2x.png` | 512 | yes | macOS |
| `AppIcon-mac-512x512@1x.png` | 512 | yes | macOS |
| `AppIcon-mac-512x512@2x.png` | 1024 | yes | macOS |

The iOS 1024 is deliberately **opaque, square, and without rounded corners**. Apple
rejects marketing icons that carry an alpha channel, and the system applies its own
mask — pre-rounding it would produce a double-rounded corner.

The macOS images are the reverse: they carry alpha because the macOS icon is a
rounded rectangle sitting inside a larger canvas with room for its shadow.

### Geometry

| | Value |
|---|---|
| Canvas | 1024 × 1024 |
| Background | solid `#091440`, sampled from the source artwork, not guessed |
| Content inset | subject bounding box fits 80% of its container |
| iOS subject | 646 × 819 at (189, 102) on the 1024 canvas |
| macOS rounded rect | 824 × 824 centred, corner radius 185.4 |
| macOS subject | 520 × 659, inset against the **824 rect**, not the canvas |

The macOS subject is inset against the rounded rect rather than the canvas on
purpose. Insetting against the canvas makes the artwork exactly as tall as the rect
and clips the crown and the tail feather.

### Verified

- `xcodebuild` succeeds for `generic/platform=iOS Simulator` and for `platform=macOS`,
  Debug and Release.
- `actool` compiles the catalog with **zero warnings and zero notices**.
- macOS product contains `Contents/Resources/AppIcon.icns` with `CFBundleIconFile = AppIcon`.
- iOS product contains `AppIcon60x60@2x.png` and `AppIcon76x76@2x~ipad.png`, and
  `Info.plist` carries `CFBundleIconName = AppIcon`. This key is what App Store
  validation checks for, and it was absent before.
- `Assets.car` contains all 10 macOS renditions at the correct pixel sizes.

The `.icns` file contains 4 members (16, 32, 128, 512) rather than 10. That is
actool's own choice — it emits a legacy `.icns` companion while the complete icon
data lives in `Assets.car`, and it raises no diagnostic about it.

---

## 2. Layered sources for Icon Composer

`Design/AppIcon/` holds the layer separation. These files are **not** referenced by
the Xcode project and are not compiled; they are design inputs.

| File | Purpose |
|---|---|
| `Dudo-Background-Default.png` | solid `#091440` field, 1024, opaque |
| `Dudo-Background-Dark.png` | deepened field `#060C28` for the Dark appearance |
| `Dudo-Foreground-Default.png` | the macaw, background keyed out, clean alpha |
| `Dudo-Foreground-Dark.png` | as above with the brightest cream held back 8% |
| `Dudo-Foreground-Mono.png` | greyscale remap for the Mono / tinted appearance |
| `Dudo-Features-Default.png` | optional: face, beak and eye only, pixel-aligned on top of the foreground |
| `Dudo-Source-Flat-1254.png` | the original flat artwork, kept for provenance |

The mono variant is a per-region tone remap, not a desaturation: cream face → 1.00,
gold eye → 0.86, red plumage → 0.62, dark beak → 0.20, each with a small in-class
modulation so the low-poly faceting survives. A straight desaturation collapses the
plumage and the beak toward the same value and the silhouette stops reading at 32 px.

`Dudo-Features-Default.png` sits **pixel-exactly on top of** the full foreground
rather than replacing part of it, so giving it its own specular cannot open a seam —
the full foreground is always underneath.

---

## 3. Applying Liquid Glass — manual, GUI only

**Icon Composer has no usable command line.** The binary at
`/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/MacOS/Icon Composer`
contains an internal `ToolCommand` surface (`--export-preview`,
`--export-build-intermediary`, `--export-intermediate-representation`,
`--output-directory`), but invoking it launches the GUI and blocks; it depends on an
Apple-internal bundle that is not shipped. This step cannot be scripted or automated.

Installed version: **Icon Composer 1.6**, bundled inside Xcode 26.6.

### Steps

1. Open Icon Composer. It is inside Xcode, not in `/Applications`:
   **Xcode ▸ Open Developer Tool ▸ Icon Composer**, or open
   `/Applications/Xcode.app/Contents/Applications/Icon Composer.app` directly.

2. Create a new document and save it as **`Dudo.icon`** at the repository root.
   A `.icon` is a *package* (UTI `com.apple.iconcomposer.icon`, conforming to
   `com.apple.package`) — a folder that Finder presents as one file.

3. **Background group.** Prefer a solid fill over an imported image: select the
   background group and set its fill to solid **`#091440`**. A fill stays perfectly
   clean at every size, whereas a 1024 PNG of a flat colour can only get worse.
   Use `Dudo-Background-Default.png` only if entering the hex is inconvenient.

4. **Foreground group.** Add a group above the background and import
   `Dudo-Foreground-Default.png` into it.

5. **Features group (optional).** Add a group above the foreground and import
   `Dudo-Features-Default.png`. Skip this if the result reads better without it —
   it exists to let the face and beak take a stronger highlight than the plumage,
   and that is a judgement call best made against the live preview.

   Icon Composer allows a **maximum of four visible groups**; this composition uses
   two or three.

6. **Effects.** The inspector exposes, per group and per layer: specular highlight,
   translucency, shadow, blur material, and glass. Recommended starting point:

   | Group | Specular | Shadow | Translucency | Glass |
   |---|---|---|---|---|
   | Background | off | off | off | off |
   | Foreground | on | on | off | on |
   | Features | on (lower) | off | off | on |

   A specular on a flat background field reads as a smudge rather than a highlight,
   which is why it is off there. These are starting points — judge them against the
   preview, which is the whole reason this step is manual.

7. **Appearances.** Switch the appearance selector between Default, Dark, and Mono.
   Each layer can override its image per appearance:
   - **Dark** — set the background fill to `#060C28` and swap the foreground image
     to `Dudo-Foreground-Dark.png`.
   - **Mono** — swap the foreground image to `Dudo-Foreground-Mono.png`.
   `base` is the appearance the others inherit from; anything not overridden falls
   through to it.

8. **Platforms.** Confirm both the square (iPhone/iPad) and macOS idioms are enabled
   in the document settings. Dudo ships on both. Check the macOS preview separately —
   macOS applies the material differently from iOS.

9. **Save.** Saving writes the `.icon` package in place. There is no separate export
   needed for Xcode; Xcode consumes the `.icon` directly.

### Wiring it into Xcode

Not yet done, and it should be a deliberate decision rather than a side effect:

1. Add `Dudo.icon` to the Xcode project (target **Dudo**).
2. Set `ASSETCATALOG_COMPILER_APPICON_NAME` to the icon's name.
3. Rebuild for **both** destinations and re-verify the checks in §1.

**Keep `AppIcon.appiconset` until that is verified.** Only one app icon source is
active at a time, so switching is reversible by changing that one build setting back.

**Deployment-target caveat.** The project targets iOS 18.0 and macOS 15.0. Liquid
Glass rendering is a 26-era feature, so systems older than that need conventional
icon renditions. Confirm those are still produced for the older targets before
removing the `appiconset` — do not assume it.

---

## 4. Regenerating the layers

The separation was produced by a script that is **not** in this repository, by
design. The method, if it needs repeating:

- Sample the background from the border ring — median, not a guessed hex.
- Key by **flood fill from the border**, not by colour threshold. The beak and the
  shadowed facets sit close to navy in luminance; a threshold punches holes through
  them. A flood fill cannot reach a dark facet that is sealed inside the subject.
  There are 1,224 navy-coloured pixels inside this artwork that a threshold destroys
  and a flood fill preserves.
- Recover the anti-aliased rim by **local unmixing**: alpha = distance-from-navy
  divided by the local edge contrast. A single global threshold is wrong because a
  5%-coverage pixel on a cream edge and on a dark-red edge sit at very different
  distances from navy.
- Decontaminate rim colour (`F = bg + (P − bg) / α`) so no navy fringe survives
  compositing onto a light background.
- Resize **premultiplied**. Lanczos on unpremultiplied RGBA drags rim colour outward
  and produces a halo.

Two traps worth writing down:

- `PIL.Image.fromarray` returns a read-only buffer-backed image, and
  `ImageDraw.floodfill` mutates it to **no effect and raises nothing**. Call
  `.copy()` first. The failure mode is a silently empty matte.
- The source declares sRGB through the PNG `sRGB` chunk, not an embedded ICC
  profile, and Pillow does not carry that chunk through a re-encode. All outputs
  here embed a real sRGB profile instead.

---

## 5. Known limitations

- **The source is flat.** Every layer here is a separation of one flat image, not
  independently authored art. Liquid Glass refracts and lights layers relative to one
  another; genuinely separate art would give the material more to work with. The
  parrot has no internal depth to recover.
- **Small sizes.** At 16 px the mark still reads as a red parrot head with a pale
  face, but the faceting and the beak structure are gone — below the resolution of
  the grid. Apple's guidance is to simplify artwork at small sizes, and that means a
  designer redrawing the mark, not resampling this one.
- **No dedicated Dark artwork.** The Dark foreground is the Default with the
  brightest cream held back 8%. The field is already dark, so this is close to
  correct, but it is an adjustment rather than a designed Dark variant.
- **The Icon Composer result is unverified.** Nobody has seen this composition
  rendered with the material applied. §3 is a grounded starting point, not a
  validated outcome.

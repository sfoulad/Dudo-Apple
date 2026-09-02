# Dudo app icon

The Dudo mark is a low-poly scarlet macaw head on a deep navy field.

This document covers two things: the icon that ships **today**, and the manual
Icon Composer step that applies Apple's Liquid Glass material. They are
independent — the app builds and archives with a correct icon whether or not the
Icon Composer step is ever performed.

Source artwork: `Design/AppIcon/Dudo-Source-Flat-1254.png` (1254 × 1254, RGB, no
alpha), in which the subject is **already inset within the frame by the designer**.

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

All outputs embed a real sRGB ICC profile.

The iOS 1024 is deliberately **opaque, square, and without rounded corners**. Apple
rejects marketing icons that carry an alpha channel, and the system applies its own
mask — pre-rounding it would produce a double-rounded corner.

The macOS images are the reverse: they carry alpha because the macOS icon is a
rounded rectangle sitting inside a larger canvas with room for its shadow.

### Geometry — and one number worth a decision

**The designer's composition is preserved exactly.** The only geometric operation
applied is the 1254 → 1024 downscale. There is no bounding-box re-fit, no
re-centring, and no additional inset. Adding one would double the inset already
present in the source.

| | Value |
|---|---|
| Canvas | 1024 × 1024 |
| Background | flat `#071342` |
| Subject bbox in source | x[355:926] y[281:1004] = 571 × 723 |
| Subject bbox on canvas | x[290:756] y[229:820] = 466 × 590 |
| **Subject largest dimension** | **57.7% of the canvas** |
| Apple grid reference | ~80% content area |
| macOS rounded rect | 824 × 824 centred, corner radius 185.4 |
| Subject inside that rect | 71.6% of the visible rect; margins L 190, R 168, T 129, B 104 |

**The supplied inset is tighter than Apple's grid — 57.7% against roughly 80%.**
This is recorded rather than silently corrected. The subject reads noticeably small
inside the system mask on iOS. It is a one-constant change to scale it up if that is
the preference; it has deliberately not been made.

Two caveats on that 80% figure:

- It is the 824/1024 proportion Apple uses for the macOS icon grid. It could not be
  checked against the current Human Interface Guidelines app-icons page, because that
  requires network access. **Confirm it before acting on the comparison.**
- On macOS the discrepancy largely disappears: because the visible icon is the 824
  rect rather than the full canvas, the same artwork occupies 71.6% of what the user
  actually sees. The subject sits comfortably inside the rect and is not clipped.

The subject is also off-centre in the source by about 1% (bbox centre +13.5, +15.0 px
of 1254). That is preserved too, on the same principle.

### Verified

- `xcodebuild` succeeds for `generic/platform=iOS Simulator` (Debug) and
  `platform=macOS` (Release).
- `actool` compiles the catalog with **zero warnings and zero notices**.
- iOS product: `CFBundleIconName = AppIcon` in `Info.plist`, plus derived
  `AppIcon60x60@2x.png` and `AppIcon76x76@2x~ipad.png`. That plist key is what App
  Store validation checks for, and it was absent before this work.
- macOS product: `Contents/Resources/AppIcon.icns`, `CFBundleIconFile = AppIcon`.
- `Assets.car` carries all 10 macOS renditions: 16, 32, 64, 128, 256, 512, 1024.

The `.icns` contains 4 members rather than 10. That is actool's own choice — it emits
a legacy `.icns` companion while the complete icon data lives in `Assets.car`, and it
raises no diagnostic about it.

Archive, upload, and TestFlight submission have **not** been performed.

---

## 2. Layered sources for Icon Composer

`Design/AppIcon/` holds the layer separation. These files are **not** referenced by
the Xcode project and are not compiled; they are design inputs.

| File | Purpose |
|---|---|
| `Dudo-Background-Default.png` | flat `#071342` field, 1024, opaque |
| `Dudo-Background-Dark.png` | deepened field `#040C29` for the Dark appearance |
| `Dudo-Foreground-Default.png` | the macaw, background keyed out, clean alpha |
| `Dudo-Foreground-Dark.png` | as above with the brightest cream held back 8% |
| `Dudo-Foreground-Mono.png` | greyscale remap for the Mono / tinted appearance |
| `Dudo-Features-Default.png` | optional: face, beak and eye only, pixel-aligned on top of the foreground |
| `Dudo-Source-Flat-1254.png` | the original flat artwork — the input everything else derives from |
| `make_app_icon.py` | the generator that produces every other file above, and the appiconset |

The background layers are **flat fields, not the original background**. The source
carries roughly ±2 per channel of noise, which composites badly under the material
effects; a flat value stays clean at every size.

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
   background group and set its fill to solid **`#071342`**. A fill stays perfectly
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
   - **Dark** — set the background fill to `#040C29` and swap the foreground image
     to `Dudo-Foreground-Dark.png`.
   - **Mono** — swap the foreground image to `Dudo-Foreground-Mono.png`.
   `base` is the appearance the others inherit from; anything not overridden falls
   through to it.

8. **Platforms.** Confirm both the square (iPhone/iPad) and macOS idioms are enabled
   in the document settings. Dudo ships on both. Check the macOS preview separately —
   macOS applies the material differently from iOS.

9. **Save.** Saving writes the `.icon` package in place. Xcode consumes the `.icon`
   directly; no separate export step is needed.

### Wiring it into Xcode

Not yet done, and it should be a deliberate decision rather than a side effect:

1. Add `Dudo.icon` to the Xcode project (target **Dudo**).
2. Set `ASSETCATALOG_COMPILER_APPICON_NAME` to the icon's name.
3. Rebuild for **both** destinations and re-verify the checks in §1.

**Keep `AppIcon.appiconset` until that is verified.** Only one app icon source is
active at a time, so switching is reversible by changing that one build setting back.

**Deployment-target conflict — read this before planning the Icon Composer step.**
The project targets **iOS 18.0 and macOS 15.0**, while Liquid Glass rendering is a
26-era feature. The icon effects this whole exercise is aimed at therefore require an
OS generation the app does not currently target. Systems older than 26 need
conventional renditions regardless. This is a product decision, not a detail to work
around: either the deployment targets move, or the `.icon` is added for newer systems
with the `appiconset` retained as the fallback for older ones. Nothing here assumes
which. The `appiconset` remains the shipping path.

---

## 4. Regenerating the icon

    python3 Design/AppIcon/make_app_icon.py            # regenerate everything
    python3 Design/AppIcon/make_app_icon.py --verify   # and print the evidence below

`Design/AppIcon/make_app_icon.py` is a **design-time tool, not part of the build**.
No build phase, run script, or target dependency invokes it; Xcode builds from the
generated PNGs. It requires only numpy and Pillow, installs nothing, reaches no
network, and touches no signing or App Store state. It writes PNGs only —
`Contents.json` and this document are maintained by hand.

Output is **byte-reproducible**: two consecutive runs produce 17 of 17 identical
files. That needed one deliberate fix. `ImageCms.createProfile` stamps the current
time into the ICC header's creation-date field, so every run would otherwise emit
different bytes from identical pixels and dirty every binary in git for no reason.
The script zeroes that field, which the spec permits; the profile-ID field is all
zeros, so no checksum is invalidated.

### Method

- Sample the background from the border ring — **median, not a guessed hex**. An
  independent median over the 8-pixel ring gives `#071343`; the specified brand
  value `#071342` differs by one unit of blue and is what is used.
- Key by **flood fill from the border**, not by colour threshold. The beak and the
  shadowed facets sit close to navy; a threshold punches holes through them. A flood
  fill cannot reach a dark facet sealed inside the subject, whatever its colour.
- Recover the anti-aliased rim by **local unmixing**: alpha = distance-from-navy
  divided by the local edge contrast. A single global threshold is wrong, because a
  5%-coverage pixel on a cream edge and one on a dark-red edge sit at very different
  distances from navy.
- **Decontaminate** rim colour (`F = bg + (P − bg) / α`) so no navy fringe survives
  compositing onto a light background.
- Resize **premultiplied**. Lanczos on unpremultiplied RGBA drags rim colour outward
  and produces a halo.

### The tolerance trade-off, measured

The risk is that a tolerance wide enough to swallow the background noise also eats
the beak. On this artwork there is a clean window, and both thresholds sit inside it:

| Measurement | Value |
|---|---|
| Greatest distance from `#071342` among **background** pixels | **7.87** |
| Smallest distance among **subject core** pixels | **12.41** |
| Background tolerance used | 8.0 |
| Core tolerance used | 25.0 |

Raising the tolerance from 8 to 25 costs 1,672 px (0.61% of the subject) — that is
the anti-aliased rim being reclassified as *band* for unmixing, which is intended,
not erosion. The beak does not begin to erode until far higher: tolerance 40 still
costs only 0.75%, while tolerance 60 costs 6.36% and takes real structure with it.

The alarming-looking figure of ~11 for "darkest interior pixel" turned out to be
**5 isolated stray pixels**, not a region — established by locating them individually
rather than trusting the aggregate.

### Edge verification

Anti-aliased rim: 1,653 px of 1,572,516.

**Round trip.** Recompositing the matte over the sampled navy and diffing against the
source:

| Region | Max error | Pixels > 8 |
|---|---|---|
| Solid subject | **0.00** — reconstructs exactly | 0 |
| Background | 8.00 — bounded exactly by the flood tolerance | 0 |
| Anti-aliased rim | 16.87 | 256 |

Every error above 8 in the whole image is confined to the rim band.

**No bleed.** The 10,292 fully-transparent pixels immediately outside the subject
deviate from the backdrop by **exactly 0.0000** when composited. A halo would appear
here first.

**Blue-bias test.** A surviving navy fringe shows up as blue bias (B − R) when the
foreground is composited over a neutral backdrop, measured against an
un-decontaminated control:

| | Mean B − R | px > 15 |
|---|---|---|
| Shipped (decontaminated) | **−1.81** | 10 |
| Naive (not decontaminated) | +3.45 | 0 |

Decontamination removes the systematic navy cast — the mean crosses from blue to
faintly warm — at the cost of 10 sub-pixel outliers, which sit at a mean alpha of
0.078 and are gamut-clipping artefacts rather than a visible fringe.

Note that "over white" and "over mid-grey" give identical B − R by construction,
since both backdrops are neutral. It is one test, not two.

**Visual.** The beak, the thin mandible hook, and the crown were inspected as 4×
crops over white alongside the matching source crops. The navy notch between the hook
and the cream mandible is correctly transparent, and the hook survives intact.

### Three traps, all of which cost real time

- `PIL.Image.fromarray` returns a read-only buffer-backed image, and
  `ImageDraw.floodfill` mutates it to **no effect and raises nothing**. Call
  `.copy()` first. The failure mode is a silently empty matte that looks like a
  perfectly successful run.
- The source declares sRGB through the PNG `sRGB` chunk, not an embedded ICC
  profile, and Pillow does not carry that chunk through a re-encode.
- `ImageCms.createProfile` embeds a creation timestamp, which destroys byte
  reproducibility. See §4.

---

## 5. Known limitations

- **The source is flat.** Every layer here is a separation of one flat image, not
  independently authored art. Liquid Glass refracts and lights layers relative to one
  another; genuinely separate art would give the material more to work with. The
  parrot has no internal depth to recover. This is the real ceiling on the result.
- **Content inset is tighter than Apple's grid** — 57.7% against roughly 80%. See §1.
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

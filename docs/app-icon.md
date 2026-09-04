# Dudo app icon

The Dudo mark is a low-poly scarlet macaw head on a deep navy field.

This document covers two things: the icon that ships **today**, and the manual
Icon Composer step that applies Apple's Liquid Glass material. They are
independent — the app builds and archives with a correct icon whether or not the
Icon Composer step is ever performed.

Source artwork: **two crops, one per platform**, both 1254 × 1254, RGB, no alpha.

| File | Subject | Feeds |
|---|---|---|
| `Design/AppIcon/Dudo-Source-iOS-1254.png` | 85.0% of the canvas | the iOS marketing icon |
| `Design/AppIcon/Dudo-Source-Flat-1254.png` | 57.7% of the canvas | the macOS renditions, and every layered file in §2 |

**Why two.** iOS icons are full bleed — the system masks a square that reaches the
edges, so the artwork should fill it. macOS icons carry their padding *in* the
artwork: the visible rounded rect is 824 of 1024 and the remainder is shadow room.
One crop cannot satisfy both, and using one meant one platform was always wrong.
The measurements are in §1.

The macOS source keeps its original filename. Renaming it to match would churn
eight generated binaries and invalidate every reference in §2 for a cosmetic gain,
so the asymmetry is documented instead of removed.

---

## 1. What ships today

`Dudo/Assets.xcassets/AppIcon.appiconset/` is populated and compiles clean. This is
the classic asset-catalog path and it is what unblocks archiving and TestFlight.

| File | Size | Alpha | Used for |
|---|---|---|---|
| `AppIcon-iOS-1024.png` | 1024 | **no** | iPhone and iPad; Xcode derives every runtime size from it. Built from the **iOS** source |
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

### Geometry — measured, per platform

**Each designer composition is preserved exactly.** The only geometric operation
applied is the 1254 → 1024 downscale. There is no bounding-box re-fit, no
re-centring, and no additional inset in either source.

| | iOS source | macOS source |
|---|---|---|
| Canvas | 1024 × 1024 | 1024 × 1024 |
| Background composited over | flat `#071342` | flat `#071342` |
| Subject bbox in source | x[217:1058] y[144:1210] = 841 × 1066 | x[355:926] y[281:1004] = 571 × 723 |
| Subject bbox on canvas | x[177:864] y[118:988] = 687 × 870 | x[290:756] y[229:820] = 466 × 590 |
| **Subject largest dimension** | **85.0% of the canvas** | **57.7% of the canvas** |
| Clearance from canvas edge | L 177, R 160, T 118, **B 36** | L 290, R 268, T 229, B 204 |
| Inside the 824 macOS rect | **no — overruns the bottom by 64 px** | yes; margins L 190, R 168, T 129, B 104 |

**Neither crop is clipped by the iOS mask**, at the n = 5 superellipse or at a
conservative n = 4. That is worth stating explicitly because it is the opposite of
the intuition: the subject's extremities sit near the edge **midpoints**, where that
curve is essentially straight, not in the corners where it bends. The risk that
actually materialised was on macOS.

**The macOS rect is what forces the split.** Given one crop for both platforms:

- the wide crop loses 4244 px of the plume on macOS — the clipped region is exactly
  x[525:656] y[924:988] on a 1024 canvas, i.e. the tail of the tail feather;
- the inset crop is clipped nowhere but reads at 57.7% on iOS, against Apple's ~80%
  grid reference.

**One caveat on that 80% figure, unchanged:** it is the 824/1024 proportion Apple
uses for the macOS icon grid. It could not be checked against the current Human
Interface Guidelines app-icons page, because that requires network access.
**Confirm it before acting on the comparison.**

**The iOS bottom clearance is 36 px of 1024 — 3.5%, the tightest margin anywhere in
this icon.** At the derived runtime sizes that is 4.2 px at 120, 5.3 px at 152, and
**2.0 px at the 58 px settings rendition**. The masked renders were inspected at 120
and 152 and the plume reads as clearing the edge, not touching it. It is recorded
here because it is the number that would break first if the artwork were ever
recomposed, and because 2 px is not much to lose.

Each subject is also slightly off-centre in its own source. That is preserved too,
on the same principle.

### Verified

Measured on 2026-09-05, Xcode 26.6 (17F113), against the split sources.

- `xcodebuild` **BUILD SUCCEEDED** for all four destinations, Release:
  iPhone 17 simulator, iPad Pro 11-inch (M5) simulator, `platform=macOS`, and
  `generic/platform=iOS` with signing disabled.
- `actool` compiles the catalog with **zero warnings and zero errors**.
- iOS product: derived `AppIcon60x60@2x.png` and `AppIcon76x76@2x~ipad.png`, and an
  `Assets.car` carrying the 1024 rendition. See the `CFBundleIconName` note below —
  it is not as simple as it looks.
- macOS product: `Contents/Resources/AppIcon.icns`, `CFBundleIconFile = AppIcon`,
  `CFBundleIconName = AppIcon`.
- `Assets.car` carries all 10 macOS renditions: 16, 32, 64, 128, 256, 512, 1024.
- The built products were rendered and looked at, not merely listed.

### `CFBundleIconName` — where it comes from, and where it does not

**Xcode 26.6's `actool` does not emit a top-level `CFBundleIconName` for iOS.** It
emits the key only nested, inside `CFBundleIcons → CFBundlePrimaryIcon` and again
under `CFBundleIcons~ipad`. This was confirmed on both simulator and device builds.
macOS is unaffected — it gets a top-level key from `actool` already.

App Store validation's ITMS-90713 check is documented against the **top-level** key,
so the top-level key is now set explicitly, in `Config/Info.plist`.

**`INFOPLIST_KEY_CFBundleIconName` was tried first and is a no-op on iOS.** The
setting reaches the build — `xcodebuild -showBuildSettings` prints
`INFOPLIST_KEY_CFBundleIconName = AppIcon` — and the key is still absent from the
built `Info.plist`. Xcode treats the icon keys as `actool`'s to own and discards the
manual value. Every other `INFOPLIST_KEY_*` in this project does apply, so this is
specific to this key. The setting was removed again rather than left in place
looking effective. `Config/Info.plist` is *merged* rather than overwritten, which is
why setting it there works.

**This may well be redundant.** A toolchain that strips the key would otherwise ship
bundles its own validator rejects, which is a decent argument that the nested form is
accepted. **That argument has not been confirmed against an actual upload** — doing so
requires an archive and a submission, which have not been performed. A redundant key
costs nothing, so it stays until an upload proves otherwise.

Verified present as a top-level key in all three built products: iOS simulator,
iOS device, macOS.

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
| `Dudo-Source-Flat-1254.png` | the inset flat artwork — **the input every layer above derives from**, and the macOS renditions |
| `Dudo-Source-iOS-1254.png` | the wide flat artwork — the iOS marketing icon only; **no layer derives from it** |
| `make_app_icon.py` | the generator that produces every other file above, and the appiconset |

**Every layer comes from the inset crop, not the wide one.** The layers feed the
macOS-style composition, and re-deriving them from the wide crop would silently
change what §3 tells you to import. If Liquid Glass is ever pursued for iOS
specifically, that is a decision to take deliberately — see §5.

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

Output is **byte-reproducible**: two consecutive runs produce **19 of 19** identical
files, re-verified after the split. That needed one deliberate fix.
`ImageCms.createProfile` stamps the current time into the ICC header's creation-date
field, so every run would otherwise emit different bytes from identical pixels and
dirty every binary in git for no reason. The script zeroes that field, which the spec
permits; the profile-ID field is all zeros, so no checksum is invalidated.

### Method

- **Key each source against the right background, which is not the same question as
  what it is composited over.** Everything is composited over the brand `#071342`, so
  the two platforms ship an identical field. The *keying* value is what the flood fill
  measures distance from, and the fill fails if a border pixel sits further from it
  than the tolerance of 8.0. Worst border-ring distance, measured:

  | source | vs brand `#071342` | vs its own sampled field |
  |---|---|---|
  | iOS (`#091440`) | **7.68** | 5.10 |
  | macOS (`#071343`) | 7.00 | 6.63 |

  The iOS crop against the brand navy leaves **0.32 of headroom**. It passes, and that
  is far too close to depend on, so it is keyed against its own sampled field. The
  macOS crop keeps the brand navy: it has a full unit of headroom there, and it is the
  value that produced the committed, verified renditions. Switching it too would shift
  blue by one unit, change nothing visible, rewrite all fourteen macOS and layer
  binaries, and push one background pixel to a round-trip error of 9.00 — breaking the
  "every error > 8 is in the rim band" property asserted below. **Change one thing at
  a time.**
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

| Measurement | iOS source | macOS source |
|---|---|---|
| Greatest distance among **background** pixels | **7.87** | **7.87** |
| Smallest distance among **subject core** pixels | **15.03** | **12.41** |
| Background tolerance used | 8.0 | 8.0 |
| Core tolerance used | 25.0 | 25.0 |

Distances are measured against each source's own keying background — see Method
above. Both windows are clean, and the iOS crop's is the wider of the two.

Raising the tolerance from 8 to 25 costs 1,672 px (0.61% of the subject) — that is
the anti-aliased rim being reclassified as *band* for unmixing, which is intended,
not erosion. The beak does not begin to erode until far higher: tolerance 40 still
costs only 0.75%, while tolerance 60 costs 6.36% and takes real structure with it.

The alarming-looking figure of ~11 for "darkest interior pixel" turned out to be
**5 isolated stray pixels**, not a region — established by locating them individually
rather than trusting the aggregate.

### Edge verification

Both sources are verified independently, because they are keyed independently and a
defect could appear in one and not the other. Anti-aliased rim: **2,770 px** (iOS)
and **1,673 px** (macOS), of 1,572,516.

**Round trip.** Recompositing the matte over the keying navy and diffing against the
source:

| Region | iOS: max error / px > 8 | macOS: max error / px > 8 |
|---|---|---|
| Solid subject | **0.00** — reconstructs exactly / 0 | **0.00** — reconstructs exactly / 0 |
| Background | 8.00 — bounded by the flood tolerance / 0 | 8.00 — bounded by the flood tolerance / 0 |
| Anti-aliased rim | 19.97 / 927 | 16.87 / 256 |

Every error above 8 in the whole image is confined to the rim band, **for both
sources**.

**No bleed.** The fully-transparent pixels immediately outside the subject — 14,975
on the iOS source, 10,292 on the macOS source — deviate from the backdrop by
**exactly 0.0000** when composited. A halo would appear here first.

**Blue-bias test.** A surviving navy fringe shows up as blue bias (B − R) when the
foreground is composited over a neutral backdrop, measured against an
un-decontaminated control:

| | iOS: mean B − R / px > 15 | macOS: mean B − R / px > 15 |
|---|---|---|
| Shipped (decontaminated) | **−3.08** / 4 | **−1.81** / 10 |
| Naive (not decontaminated) | +4.32 / 4 | +3.45 / 0 |

Decontamination removes the systematic navy cast on both — the mean crosses from
blue to faintly warm — at the cost of a handful of sub-pixel outliers, which sit at
very low alpha and are gamut-clipping artefacts rather than a visible fringe.

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
- **~~Content inset is tighter than Apple's grid~~ — resolved by the per-platform
  split.** iOS now uses the wide crop at 85.0%. The 57.7% figure still describes the
  macOS source, where it is correct rather than a limitation: it occupies 71.6% of
  the 824 rect the user actually sees.
- **The iOS bottom clearance is 36 px of 1024**, which is 2.0 px at the 58 px
  settings rendition. Not clipped, and inspected at 120 and 152 — but it is the first
  thing that would break if the artwork were recomposed. See §1.
- **The layered sources derive from the macOS crop only.** If Liquid Glass is
  pursued for iOS, the layers would need re-deriving from the wide crop, and §3's
  import instructions would change with them. Not done, and not assumed.
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

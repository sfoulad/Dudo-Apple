#!/usr/bin/env python3
"""
Dudo app icon generator — a DESIGN-TIME TOOL, not part of the build.

Nothing in the Xcode project invokes this script. No build phase, no run script,
no target dependency references it. Xcode builds from the already-generated PNGs
in `Dudo/Assets.xcassets/AppIcon.appiconset/`; this tool exists so those PNGs can
be regenerated from the source artwork instead of being unreproducible binaries.

Run it by hand, from anywhere:

    python3 Design/AppIcon/make_app_icon.py

Input : Design/AppIcon/Dudo-Source-Flat-1254.png — the flat 1254x1254 artwork,
        in which the designer has already inset the subject within the frame.
Output: (a) the classic AppIcon.appiconset that the app actually ships, and
        (b) the layered PNGs in this directory, for manual import into
            Icon Composer. See docs/app-icon.md.

The designer's composition is preserved exactly. The only geometric operation is
a 1254 -> 1024 downscale: no bounding-box re-fit, no re-centring, no additional
inset. The source is already inset, and adding another would double it.

Requires only numpy and Pillow. It installs nothing, reaches no network, and
touches no signing, provisioning, or App Store state.

This tool writes PNG files only. Contents.json and all documentation are authored
by hand, deliberately: generated text files drift out of review.
"""
import argparse
import os
import sys
from collections import namedtuple

import numpy as np
from PIL import Image, ImageCms, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "Dudo-Source-Flat-1254.png")
ICONSET = os.path.join(REPO, "Dudo", "Assets.xcassets", "AppIcon.appiconset")

CANVAS = 1024

# Sampled from the artwork, not guessed. An independent median over the 8px
# border ring gives #071343; the brand value #071342 differs by one unit of blue,
# below any perceptual threshold, and is what is used.
BG = np.array([7.0, 19.0, 66.0])
BG_DARK_SCALE = 0.62

# macOS classic grid: an 824x824 rounded rect on a 1024 canvas, radius 22.5%.
MAC_RECT = 824
MAC_RADIUS = 185.4

# Keying tolerances, both chosen from measured separation rather than by feel.
# Background noise on this source tops out at distance 7.87 from BG across the
# whole border ring; the subject core starts at 12.41 and the dark beak does not
# begin to erode until roughly 60. Both thresholds sit inside that window.
# `--verify` prints the measurements that justify them.
BG_TOL = 8.0
CORE_TOL = 25.0

LUMA = np.array([0.2126, 0.7152, 0.0722])

MAC_SLOTS = [("16x16", "1x", 16), ("16x16", "2x", 32), ("32x32", "1x", 32),
             ("32x32", "2x", 64), ("128x128", "1x", 128), ("128x128", "2x", 256),
             ("256x256", "1x", 256), ("256x256", "2x", 512), ("512x512", "1x", 512),
             ("512x512", "2x", 1024)]

def _srgb_profile():
    """
    A byte-stable sRGB ICC profile.

    The source declares sRGB through the PNG sRGB chunk rather than an embedded
    ICC profile, and Pillow does not carry that chunk through a re-encode. So we
    embed a real profile: untagged PNGs are usually *assumed* sRGB, but assumed
    is not tagged, and an app icon should not rely on the assumption.

    ImageCms stamps the current time into the ICC header's creation-date field
    (bytes 24..35). Left alone, every run of this script would emit different
    bytes from identical pixels and dirty all 17 binaries in git for no reason.
    Zeroing the field means "unknown date", which the spec permits, and makes
    the output byte-reproducible. The profile-ID field at bytes 84..99 is all
    zeros here, so no checksum is invalidated by the edit.
    """
    p = bytearray(ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())
    p[24:36] = b"\x00" * 12
    return bytes(p)


ICC = _srgb_profile()


def _save(arr, path, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode).save(
        path, optimize=True, icc_profile=ICC)


def save_rgba(arr, path):
    _save(arr, path, "RGBA")


def save_rgb(arr, path):
    _save(arr, path, "RGB")


# --------------------------------------------------------------------------
def flood_from_border(candidate):
    """Connected component of `candidate` (bool) reachable from the border."""
    # .copy() is load-bearing: Image.fromarray hands back a read-only
    # buffer-backed image, and ImageDraw.floodfill then mutates it to no effect
    # and raises nothing. Without the copy this returns an empty matte and the
    # run still looks successful.
    m = Image.fromarray(np.where(candidate, 255, 0).astype(np.uint8), "L").copy()
    h, w = candidate.shape
    # Seed from every border pixel that is a candidate. Seeding only the corners
    # is fragile: noise can push a corner outside the tolerance, and the fill
    # then never starts.
    seeds = ([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
             + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])
    started = 0
    for s in seeds:
        if m.getpixel(s) == 255:
            ImageDraw.floodfill(m, s, 128, thresh=0)
            started += 1
    if started == 0:
        raise RuntimeError("no border pixel matched the background tolerance")
    filled = np.asarray(m) == 128
    if not filled.any():
        raise RuntimeError("flood fill produced nothing despite valid seeds")
    return filled


Matte = namedtuple("Matte", "alpha rgb diag")


def build_matte(a, bg=BG, bg_tol=BG_TOL, core_tol=CORE_TOL, window=9):
    """
    Three-way matte: certain background, certain subject, and a thin uncertain
    band between them that gets unmixed.

    Flood fill decides background and subject outright, and that is what
    protects the beak. A dark facet sealed inside the subject is unreachable
    from the border however close its colour sits to navy; a plain colour
    threshold has no such protection and punches holes straight through it.

    Band alpha comes from local edge contrast rather than a global constant,
    because a 5%-coverage pixel on a cream edge and one on a dark-red edge sit
    at very different distances from navy.
    """
    d = np.linalg.norm(a - bg, axis=2)

    pure_bg = flood_from_border(d < bg_tol)
    core = ~flood_from_border(d < core_tol)
    band = ~pure_bg & ~core

    scaled = np.where(core, np.clip(d * 0.5, 0, 255), 0).astype(np.uint8)
    local = np.asarray(
        Image.fromarray(scaled, "L").copy().filter(ImageFilter.MaxFilter(window))
    ).astype(np.float64) * 2.0

    alpha = np.zeros(d.shape)
    alpha[core] = 1.0
    denom = np.maximum(local, 1.0)
    alpha[band] = np.clip(d[band] / denom[band], 0.0, 1.0)
    alpha[band & (local <= 0)] = 0.0

    # Undo the blend with navy on the rim, so the foreground carries no dark
    # fringe when it is composited onto anything lighter.
    rgb = a.copy()
    mix = (alpha > 0.0) & (alpha < 1.0)
    if mix.any():
        af = alpha[mix][:, None]
        rgb[mix] = np.clip(bg + (a[mix] - bg) / af, 0, 255)

    diag = {
        "opaque_px": int((alpha == 1.0).sum()),
        "clear_px": int((alpha == 0.0).sum()),
        "partial_px": int(mix.sum()),
        "navy_pixels_sealed_inside_subject": int((core & (d < bg_tol)).sum()),
        "alpha_on_border": float(max(alpha[0].max(), alpha[-1].max(),
                                     alpha[:, 0].max(), alpha[:, -1].max())),
        "max_background_distance": round(float(d[pure_bg].max()), 2),
        "min_core_distance": round(float(d[core].min()), 2),
    }
    return Matte(alpha, rgb, diag)


def bbox_of(alpha, t=0.5):
    ys, xs = np.where(alpha > t)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


# --------------------------------------------------------------------------
def classify(rgb, alpha):
    """Palette classes. The art is low-poly and flat-shaded, so these boundaries
    follow real facet colours rather than arbitrary cuts."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    v = mx / 255.0
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0.0)
    fg = alpha > 0.5

    red = fg & (r >= g) & (r >= b) & (sat > 0.45) & (g < 0.55 * np.maximum(r, 1))
    gold = fg & (r >= g) & (g > b) & (sat > 0.35) & (g >= 0.55 * np.maximum(r, 1)) & (v > 0.4)
    cream = fg & (sat <= 0.35) & (v > 0.60)
    dark = fg & (v <= 0.60) & (sat <= 0.45)
    other = fg & ~(red | gold | cream | dark)
    return {"red": red, "gold": gold, "cream": cream, "dark": dark,
            "other": other, "fg": fg}


def mono_values(rgb, alpha, cls):
    """
    Greyscale that stays legible as a silhouette.

    Not a desaturation: straight luminance collapses the red plumage and the
    dark beak toward the same value, and the silhouette stops reading at 32px.
    Each region gets a target tone, plus a small in-class modulation so the
    low-poly faceting survives instead of flattening into solid blocks.
    """
    lum = (rgb @ LUMA) / 255.0
    out = np.zeros(lum.shape, dtype=np.float64)
    targets = {"cream": 1.00, "gold": 0.86, "red": 0.62, "dark": 0.20, "other": 0.55}
    spread = {"cream": 0.10, "gold": 0.10, "red": 0.16, "dark": 0.12, "other": 0.14}
    for name, target in targets.items():
        m = cls[name]
        if not m.any():
            continue
        vals = lum[m]
        lo, hi = np.percentile(vals, 2), np.percentile(vals, 98)
        norm = np.clip((vals - lo) / max(hi - lo, 1e-6), 0, 1) - 0.5
        out[m] = np.clip(target + norm * spread[name], 0.03, 1.0)
    return out


# --------------------------------------------------------------------------
def to_canvas(rgb, alpha, canvas=CANVAS, gray=None):
    """
    Scale the whole frame to the canvas, preserving the source composition.

    Premultiplied resize: Lanczos on unpremultiplied RGBA drags the
    decontaminated rim colours outward and produces a halo.
    """
    src = np.dstack([gray * 255.0] * 3) if gray is not None else rgb
    pm = np.dstack([src * alpha[..., None], alpha * 255.0]).astype(np.float32)
    small = np.asarray(
        Image.fromarray(np.clip(pm, 0, 255).astype(np.uint8), "RGBA")
        .resize((canvas, canvas), Image.LANCZOS)
    ).astype(np.float64)
    a_s = small[..., 3:4] / 255.0
    out = np.zeros((canvas, canvas, 4))
    out[..., :3] = np.clip(
        np.where(a_s > 1e-4, small[..., :3] / np.maximum(a_s, 1e-4), 0.0), 0, 255)
    out[..., 3:4] = a_s * 255.0
    return out


def over(fg_rgba, bg_rgb):
    a = fg_rgba[..., 3:4] / 255.0
    return fg_rgba[..., :3] * a + bg_rgb * (1.0 - a)


def rounded_rect_mask(size, rect, radius, supersample=4):
    s = supersample
    m = Image.new("L", (size * s, size * s), 0)
    off = (size - rect) // 2
    ImageDraw.Draw(m).rounded_rectangle(
        [off * s, off * s, (off + rect) * s - 1, (off + rect) * s - 1],
        radius=radius * s, fill=255)
    return m.resize((size, size), Image.LANCZOS)


# --------------------------------------------------------------------------
def report_geometry(m, src_px):
    x0, y0, x1, y1 = bbox_of(m.alpha)
    sc = CANVAS / src_px
    rect_lo, rect_hi = (CANVAS - MAC_RECT) / 2, (CANVAS + MAC_RECT) / 2
    print(f"  subject bbox in source : x[{x0}:{x1}] y[{y0}:{y1}] = {x1-x0}x{y1-y0}")
    print(f"  subject bbox on canvas : x[{x0*sc:.0f}:{x1*sc:.0f}] "
          f"y[{y0*sc:.0f}:{y1*sc:.0f}] = {(x1-x0)*sc:.0f}x{(y1-y0)*sc:.0f}")
    print(f"  largest dimension      : {max(x1-x0, y1-y0)/src_px*100:.1f}% of canvas "
          f"(Apple grid reference ~80%; the source is already inset, see docs/app-icon.md)")
    fits = (x0*sc >= rect_lo and x1*sc <= rect_hi
            and y0*sc >= rect_lo and y1*sc <= rect_hi)
    print(f"  inside the {MAC_RECT} macOS rect? {fits}  "
          f"(margins L={x0*sc-rect_lo:.0f} R={rect_hi-x1*sc:.0f} "
          f"T={y0*sc-rect_lo:.0f} B={rect_hi-y1*sc:.0f})")
    print(f"  vs the visible macOS rect: {max(x1-x0, y1-y0)*sc/MAC_RECT*100:.1f}%")


def verify(a, m):
    """Print the evidence behind the tolerances and the edge quality."""
    d = np.linalg.norm(a - BG, axis=2)
    print("\n  -- keying evidence --")
    print(f"  greatest distance among background pixels : "
          f"{m.diag['max_background_distance']}")
    print(f"  smallest distance among subject core px   : "
          f"{m.diag['min_core_distance']}")
    print(f"  tolerances in use: background {BG_TOL}, core {CORE_TOL} "
          f"-- both inside that window")
    print(f"  navy-coloured pixels sealed inside the subject, preserved by the "
          f"flood fill: {int((~flood_from_border(d < BG_TOL) & (d < BG_TOL)).sum())}")

    rt = m.rgb * m.alpha[..., None] + BG * (1 - m.alpha[..., None])
    err = np.abs(rt - a).max(axis=2)
    solid, clear = m.alpha == 1.0, m.alpha == 0.0
    partial = ~solid & ~clear
    print("\n  -- round trip (recomposite over navy, diff against source) --")
    for label, msk in (("solid subject", solid), ("background", clear),
                       ("anti-aliased rim", partial)):
        if msk.any():
            print(f"  {label:18s}: max {err[msk].max():6.2f}   "
                  f">8: {(err[msk] > 8).sum():5d} px")
    print(f"  every error >8 confined to the rim band: "
          f"{bool(((err > 8) & ~partial).sum() == 0)}")

    # A surviving navy fringe reads as blue bias over a neutral backdrop.
    rim = (m.alpha > 0.02) & (m.alpha < 0.98)
    white = np.array([255.0, 255.0, 255.0])
    for label, rgb in (("decontaminated (shipped)", m.rgb), ("raw (control)", a)):
        comp = rgb * m.alpha[..., None] + white * (1 - m.alpha[..., None])
        bias = comp[rim][:, 2] - comp[rim][:, 0]
        print(f"  blue bias over white, {label:24s}: mean {bias.mean():+6.2f}  "
              f">15: {int((bias > 15).sum())} px")

    grow = np.asarray(Image.fromarray(np.where(solid, 255, 0).astype(np.uint8), "L")
                      .copy().filter(ImageFilter.MaxFilter(9))) > 127
    ring = grow & clear
    comp = m.rgb * m.alpha[..., None] + white * (1 - m.alpha[..., None])
    print(f"  {int(ring.sum())} fully-transparent px just outside the subject "
          f"deviate from the backdrop by max {np.abs(comp[ring] - 255).max():.4f}")


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--verify", action="store_true",
                    help="print the keying and edge-quality evidence")
    ap.add_argument("--diagnostics", metavar="DIR",
                    help="also write halo, alpha and small-size check images to DIR "
                         "(outside the repository, for inspection only)")
    args = ap.parse_args()

    if not os.path.exists(SRC):
        sys.exit(f"source artwork not found: {SRC}")

    a = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)
    src_px = a.shape[0]
    m = build_matte(a)
    cls = classify(m.rgb, m.alpha)
    mono = mono_values(m.rgb, m.alpha, cls)

    print(f"source {SRC} ({src_px}x{src_px})")
    print("background #%02X%02X%02X" % tuple(BG.astype(int)))
    for k, v in m.diag.items():
        print(f"  {k}: {v}")
    report_geometry(m, src_px)

    navy_field = np.broadcast_to(BG, (CANVAS, CANVAS, 3)).copy()
    navy_dark = np.round(BG * BG_DARK_SCALE)
    fg = to_canvas(m.rgb, m.alpha)

    # ---- the shipping asset catalog ---------------------------------------
    # Opaque and square: Apple rejects marketing icons carrying an alpha
    # channel, and the system applies its own mask, so pre-rounding the corners
    # would double-round them.
    ios = over(fg, navy_field)
    save_rgb(ios, os.path.join(ICONSET, "AppIcon-iOS-1024.png"))

    # macOS is the reverse: the icon is a rounded rect inside a larger canvas,
    # with alpha and room for its own shadow.
    mask = np.asarray(rounded_rect_mask(CANVAS, MAC_RECT, MAC_RADIUS)) / 255.0
    shadow = Image.fromarray((mask * 255).astype(np.uint8), "L").copy() \
        .filter(ImageFilter.GaussianBlur(14))
    sh = np.roll(np.asarray(shadow).astype(np.float64) / 255.0, 12, axis=0) * 0.34
    a_ic = (mask * 255.0)[..., None] / 255.0
    a_sh = np.clip(sh * (1 - mask), 0, 1)[..., None]
    out_a = a_ic + a_sh * (1 - a_ic)
    mac_final = np.dstack([
        np.where(out_a > 0, (ios * a_ic) / np.maximum(out_a, 1e-6), 0), out_a * 255.0])
    mac_big = Image.fromarray(np.clip(mac_final, 0, 255).astype(np.uint8), "RGBA")
    for size, scale, px in MAC_SLOTS:
        mac_big.resize((px, px), Image.LANCZOS).save(
            os.path.join(ICONSET, f"AppIcon-mac-{size}@{scale}.png"),
            optimize=True, icc_profile=ICC)

    # ---- layered sources for Icon Composer --------------------------------
    # Flat fields, not the original background: the source carries about +/-2
    # per channel of noise, which composites badly under the material effects.
    save_rgb(navy_field, os.path.join(HERE, "Dudo-Background-Default.png"))
    save_rgb(np.broadcast_to(navy_dark, (CANVAS, CANVAS, 3)),
             os.path.join(HERE, "Dudo-Background-Dark.png"))
    save_rgba(fg, os.path.join(HERE, "Dudo-Foreground-Default.png"))

    dark_rgb = m.rgb.copy()
    hot = (m.rgb @ LUMA) > 200
    dark_rgb[hot] = m.rgb[hot] * 0.92
    save_rgba(to_canvas(dark_rgb, m.alpha), os.path.join(HERE, "Dudo-Foreground-Dark.png"))

    fg_mono = to_canvas(m.rgb, m.alpha, gray=mono)
    save_rgba(fg_mono, os.path.join(HERE, "Dudo-Foreground-Mono.png"))

    # Optional third layer. It sits pixel-exactly ON TOP of the full foreground
    # rather than replacing part of it, so giving it its own specular cannot
    # open a seam -- the full foreground is always underneath. The opening drops
    # the handful of stray plumage pixels that fall into the cream/dark classes.
    feat_raw = cls["cream"] | cls["gold"] | cls["dark"]
    opened = Image.fromarray(np.where(feat_raw, 255, 0).astype(np.uint8), "L").copy() \
        .filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    feat = (np.asarray(opened) > 127).astype(np.float64)
    save_rgba(to_canvas(m.rgb, m.alpha * feat),
              os.path.join(HERE, "Dudo-Features-Default.png"))

    print(f"\n  wrote {1 + len(MAC_SLOTS)} files to {ICONSET}")
    print(f"  wrote 6 layer sources to {HERE}")

    if args.verify:
        verify(a, m)

    if args.diagnostics:
        out = os.path.abspath(args.diagnostics)
        os.makedirs(out, exist_ok=True)
        for name, col in (("magenta", [255., 0., 255.]), ("white", [255.] * 3)):
            save_rgb(over(fg, np.broadcast_to(np.array(col), (CANVAS, CANVAS, 3))),
                     os.path.join(out, f"halo-check-{name}.png"))
        Image.fromarray((m.alpha * 255).astype(np.uint8), "L") \
            .save(os.path.join(out, "alpha.png"))
        for px in (16, 32, 64):
            Image.fromarray(np.clip(fg_mono, 0, 255).astype(np.uint8), "RGBA") \
                .resize((px, px), Image.LANCZOS).resize((256, 256), Image.NEAREST) \
                .save(os.path.join(out, f"mono-{px}.png"))
            Image.open(os.path.join(ICONSET, "AppIcon-iOS-1024.png")) \
                .resize((px, px), Image.LANCZOS).resize((256, 256), Image.NEAREST) \
                .save(os.path.join(out, f"ios-{px}.png"))
        print(f"  wrote diagnostics to {out}")


if __name__ == "__main__":
    sys.exit(main())

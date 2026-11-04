"""Day 3 go/no-go gate.

Checks whether the 20 Apr 2026 RTC contains a usable flood signal over the
Bharalu basin, before committing the report to this event.

Important: the permanent Brahmaputra is dark in every SAR scene. All
signal tests below exclude JRC permanent water, otherwise the gate would
pass trivially. These are diagnostics, not final results.
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import rasterio
from rasterio.warp import transform_bounds
from scipy import ndimage as ndi
from skimage.filters import threshold_otsu

from common import load_config, load_json, rel_path

NODATA = -32768.0
DARK_DB = -16.0
CHANGE_DB = -2.0


def to_db(arr: np.ndarray) -> np.ndarray:
    out = np.full(arr.shape, np.nan, dtype="float32")
    valid = (arr > 0) & (arr != NODATA)
    out[valid] = 10.0 * np.log10(arr[valid])
    return out


def crop_bounds(src_transform, height, width, bbox_wgs84, dst_crs):
    minx, miny, maxx, maxy = transform_bounds(
        "EPSG:4326", dst_crs, *bbox_wgs84, densify_pts=21
    )
    inv = ~src_transform
    col_min, row_max = inv * (minx, miny)
    col_max, row_min = inv * (maxx, maxy)
    c0 = max(0, int(np.floor(min(col_min, col_max))))
    c1 = min(width, int(np.ceil(max(col_min, col_max))))
    r0 = max(0, int(np.floor(min(row_min, row_max))))
    r1 = min(height, int(np.ceil(max(row_min, row_max))))
    return slice(r0, r1), slice(c0, c1)


def read(path):
    with rasterio.open(path) as src:
        return src.read(1), src.transform, src.crs


def clean_mask(mask, min_px):
    opened = ndi.binary_opening(mask, structure=np.ones((3, 3), dtype=bool))
    labels, count = ndi.label(opened)
    sizes = np.bincount(labels.ravel())
    keep = sizes >= min_px
    keep[0] = False
    return keep[labels]


def main() -> int:
    cfg = load_config()
    root = Path(cfg["_root"])
    manifest = load_json(rel_path(cfg, "manifest"))
    raw = rel_path(cfg, "data_raw")

    pre_lin, transform, crs = read(raw / "sentinel1" / "s1_rtc_pre_vv.tif")
    post_lin, _, _ = read(raw / "sentinel1" / "s1_rtc_post_vv.tif")
    b03, _, _ = read(raw / "sentinel2" / "s2_post_B03.tif")
    b11, _, _ = read(raw / "sentinel2" / "s2_post_B11.tif")
    scl, _, _ = read(raw / "sentinel2" / "s2_post_SCL.tif")
    jrc, _, _ = read(raw / "reference" / "jrc_occurrence_aoi.tif")
    lc, _, _ = read(raw / "landcover" / "worldcover_aoi.tif")
    dem, _, _ = read(raw / "dem" / "dem_aoi.tif")

    pre_db = to_db(pre_lin)
    post_db = to_db(post_lin)
    diff = post_db - pre_db
    valid = np.isfinite(pre_db) & np.isfinite(post_db)

    dem_f = dem.astype("float32")
    dy, dx = np.gradient(dem_f, 10.0, 10.0)
    slope = np.degrees(np.arctan(np.hypot(dx, dy)))
    slope[dem_f <= -9000] = np.nan
    slope_ok = np.isfinite(slope) & (slope <= cfg["masks"]["slope_deg_max"])

    permanent = jrc.astype("float32") >= cfg["masks"]["permanent_water"]["occurrence_threshold"]
    urban = lc == 50
    nonperm = valid & ~permanent

    clear = np.isin(scl, [2, 4, 5, 6, 7]) & (b03 > 0) & (b11 > 0)
    denom = b03.astype("float32") + b11.astype("float32")
    mndwi = np.full(b03.shape, np.nan, dtype="float32")
    ok = clear & (denom > 0)
    mndwi[ok] = (b03[ok].astype("float32") - b11[ok].astype("float32")) / denom[ok]
    s2_water = np.isfinite(mndwi) & (mndwi > cfg["validation"]["mndwi"]["threshold"])
    s2_water_np = s2_water & ~permanent
    s2_clear_np = clear & ~permanent

    otsu = float(threshold_otsu(post_db[valid]))
    post_dark_otsu = valid & (post_db < otsu)
    post_dark16 = valid & (post_db < DARK_DB)
    change_neg = valid & (diff < CHANGE_DB)

    floodlike = (
        post_dark16 & change_neg & ~permanent & slope_ok & valid
    )
    floodlike_clean = clean_mask(
        floodlike, cfg["flood_masks"]["morphology"]["min_component_px"]
    )

    def frac(mask, base):
        total = int(base.sum())
        return float(mask[base].mean()) if total else float("nan")

    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6
    stats = {
        "otsu_threshold_db": round(otsu, 3),
        "valid_fraction": round(float(valid.mean()), 4),
        "s2_clear_fraction": round(float(clear.mean()), 4),
        "s2_water_fraction_clear": round(frac(s2_water, clear), 4),
        "s2_clear_nonpermanent_fraction": round(float(s2_clear_np.mean()), 4),
        "s2_water_fraction_clear_nonpermanent": round(frac(s2_water_np, s2_clear_np), 4),
        "post_dark16_fraction_nonpermanent": round(frac(post_dark16, nonperm), 4),
        "pre_dark16_fraction_nonpermanent": round(frac(valid & (pre_db < DARK_DB), nonperm), 4),
        "change_lt_minus2_fraction_nonpermanent": round(frac(change_neg, nonperm), 4),
        "post_dark16_fraction_urban_nonpermanent": round(frac(post_dark16, nonperm & urban), 4),
        "change_lt_minus2_fraction_urban_nonpermanent": round(frac(change_neg, nonperm & urban), 4),
        "floodlike_fraction_nonpermanent": round(frac(floodlike, nonperm), 4),
        "floodlike_area_km2": round(float(floodlike.sum()) * px_km2, 3),
        "floodlike_clean_area_km2": round(float(floodlike_clean.sum()) * px_km2, 3),
        "post_dark16_where_s2_water_np": round(frac(post_dark16, s2_water_np), 4),
        "post_dark16_where_s2_nonwater_np": round(frac(post_dark16, s2_clear_np & ~s2_water_np), 4),
        "change_neg_where_s2_water_np": round(frac(change_neg, s2_water_np), 4),
        "change_neg_where_s2_nonwater_np": round(frac(change_neg, s2_clear_np & ~s2_water_np), 4),
    }

    bbox = [91.70, 26.13, 91.80, 26.19]
    rs, cs = crop_bounds(transform, pre_lin.shape[0], pre_lin.shape[1], bbox, crs)

    fig, axes = plt.subplots(2, 4, figsize=(20, 10))
    panels = [
        (axes[0, 0], pre_db[rs, cs], "Pre-event VV (dB)", "gray", -22, 0),
        (axes[0, 1], post_db[rs, cs], "Post-event VV (dB)", "gray", -22, 0),
        (axes[0, 2], diff[rs, cs], "Post - pre (dB)", "RdBu", -8, 8),
        (axes[0, 3], mndwi[rs, cs], "S2 MNDWI (clear)", "RdYlBu", -0.5, 0.5),
        (axes[1, 0], np.where(post_dark16[rs, cs], 1, 0), "Post VV < -16 dB", "gray", 0, 1),
        (axes[1, 1], np.where(change_neg[rs, cs], 1, 0), "Change < -2 dB", "gray", 0, 1),
        (axes[1, 2], np.where(floodlike_clean[rs, cs], 1, 0), "Flood-like (cleaned)", "gray", 0, 1),
        (axes[1, 3], np.where(s2_water_np[rs, cs], 1, 0), "S2 water (non-permanent)", "gray", 0, 1),
    ]
    for ax, data, title, cmap, vmin, vmax in panels:
        im = ax.imshow(data, cmap=cmap, vmin=vmin, vmax=vmax)
        ax.set_title(title)
        ax.set_xticks([])
        ax.set_yticks([])
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.suptitle("Day 3 gate — Bharalu / central Guwahati (diagnostic only)")
    fig.tight_layout()

    fig_dir = rel_path(cfg, "outputs") / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    fig.savefig(fig_dir / "day3_gate_zoom.png", dpi=150)
    plt.close(fig)

    table = rel_path(cfg, "outputs") / "tables" / "day3_gate_stats.csv"
    table.parent.mkdir(parents=True, exist_ok=True)
    with open(table, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["metric", "value"])
        for key, value in stats.items():
            writer.writerow([key, value])

    print("Day 3 gate diagnostics (preliminary, not final results):")
    for key, value in stats.items():
        print(f"  {key}: {value}")
    print(f"\nWrote {table}")
    print(f"Wrote {fig_dir / 'day3_gate_zoom.png'}")

    separation = (
        stats["post_dark16_where_s2_water_np"]
        - stats["post_dark16_where_s2_nonwater_np"]
    )
    coherent_area = stats["floodlike_clean_area_km2"]
    usable = (coherent_area >= 1.0) and (separation >= 0.10)
    print(f"\nNon-permanent SAR-vs-S2 separation: {separation:.4f}")
    print(f"Coherent flood-like area: {coherent_area:.3f} km^2")
    event_name = cfg["event"]["name"]
    print("\nGate recommendation:",
          f"{event_name}: USABLE" if usable
          else f"{event_name}: WEAK / INCONCLUSIVE; CONSIDER THE FALLBACK EVENT")
    print("This is a diagnostic recommendation; the final go/no-go is a human decision.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

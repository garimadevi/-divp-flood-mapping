"""Quantify what the Lee speckle filter does to the flood map.

Answers, with numbers, the question "why filter before thresholding?":

  * area called water by the same Otsu threshold, unfiltered vs filtered
  * how much of that is speckle-induced false water
  * how much real (thin) water the smoothing costs
  * speckle reduction measured on open water in the 3x3 km demo crop

The unfiltered image is the raw linear-power RTC subset converted straight to dB
(no filtering); the filtered image is the analysis-ready layer written by
build_stack.py. Both are evaluated with the same threshold, so the comparison is
like-for-like and *before* the permanent-water / slope / morphology cleanup.

Outputs: outputs/tables/lee_effect.csv, outputs/figures/lee_effect.png
Related: matlab/step1_read_filter.m (renders the same crop side by side).
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "preprocessing"))

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import rasterio
from rasterio.warp import transform as warp_transform

from common import load_config, rel_path

DB_NODATA = -9999.0
RAW_NODATA = -32768.0
CROP = (1200, 1500, 300)  # row, col, size — mirrors matlab/step1_read_filter.m


def read(path):
    with rasterio.open(path) as src:
        return src.read(1), src.transform, src.crs


def otsu_threshold_from_table(tables: Path) -> float:
    with open(tables / "mask_stats.csv", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["method"] == "otsu_vv":
                return float(row["threshold"])
    raise RuntimeError("otsu_vv row not found in mask_stats.csv")


def main() -> int:
    cfg = load_config()
    processed = rel_path(cfg, "data_processed")
    raw_dir = rel_path(cfg, "data_raw")
    tables = rel_path(cfg, "outputs") / "tables"
    figures = rel_path(cfg, "outputs") / "figures"
    tables.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)

    lee_db, transform, crs = read(processed / "s1_post_vv_db.tif")
    raw, _, _ = read(raw_dir / "sentinel1" / "s1_rtc_post_vv.tif")

    valid = (lee_db != DB_NODATA) & (raw > 0) & (raw != RAW_NODATA)
    raw_db = np.full(raw.shape, np.nan, dtype="float32")
    raw_db[valid] = 10.0 * np.log10(raw[valid].astype("float64"))

    t = otsu_threshold_from_table(tables)
    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6

    water_raw = valid & (raw_db < t)
    water_lee = valid & (lee_db < t)
    extra = water_raw & ~water_lee          # speckle-induced false water
    lost = water_lee & ~water_raw           # thin water smoothed away

    # ---- the demo crop (same window as the MATLAB figure) ----
    r0, c0, n = CROP
    crop_raw = raw_db[r0:r0 + n, c0:c0 + n]
    crop_lee = lee_db[r0:r0 + n, c0:c0 + n]
    water_mask = crop_raw < -15.0           # defined on the RAW image only, so unbiased
    std_raw = float(np.nanstd(crop_raw[water_mask]))
    std_lee = float(np.nanstd(crop_lee[water_mask]))

    x0, y0 = transform * (c0, r0 + n)
    x1, y1 = transform * (c0 + n, r0)
    lon, lat = warp_transform(crs, "EPSG:4326", [x0, x1], [y0, y1])

    rows = [
        ("threshold_db", f"{t:.4f}"),
        ("raw_water_km2", f"{water_raw.sum() * px_km2:.2f}"),
        ("lee_water_km2", f"{water_lee.sum() * px_km2:.2f}"),
        ("speckle_extra_km2", f"{extra.sum() * px_km2:.2f}"),
        ("speckle_extra_pct_of_raw", f"{100.0 * extra.sum() / water_raw.sum():.2f}"),
        ("lost_km2", f"{lost.sum() * px_km2:.2f}"),
        ("pixel_agreement", f"{(water_raw == water_lee).mean():.4f}"),
        ("crop_window_row_col_size", f"{r0},{c0},{n}"),
        ("crop_size_km", f"{n * cfg['grid']['resolution_m'] / 1000:.2f}"),
        ("crop_water_fraction", f"{water_mask.mean():.4f}"),
        ("crop_std_raw_db", f"{std_raw:.3f}"),
        ("crop_std_lee_db", f"{std_lee:.3f}"),
        ("crop_std_reduction_pct", f"{100.0 * (1.0 - std_lee / std_raw):.1f}"),
        ("crop_lon_min", f"{lon[0]:.5f}"),
        ("crop_lon_max", f"{lon[1]:.5f}"),
        ("crop_lat_min", f"{lat[0]:.5f}"),
        ("crop_lat_max", f"{lat[1]:.5f}"),
    ]
    with open(tables / "lee_effect.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["metric", "value"])
        writer.writerows(rows)

    # ---- figure: histogram effect + area effect ----
    fig, axes = plt.subplots(1, 2, figsize=(14, 5.2))

    lo, hi = -28.0, 6.0
    axes[0].hist(raw_db[valid], bins=220, range=(lo, hi), density=True,
                 color="#b0b0b0", label="unfiltered (speckle)")
    axes[0].hist(lee_db[valid], bins=220, range=(lo, hi), density=True,
                 histtype="step", color="#1f4e79", linewidth=1.6, label="Lee 7×7, 4 looks")
    axes[0].axvline(t, color="#d62728", linestyle="--", linewidth=1.4,
                    label=f"Otsu = {t:.2f} dB")
    axes[0].set_xlabel("VV backscatter (dB)")
    axes[0].set_ylabel("probability density")
    axes[0].set_title("Speckle fills the valley — filtering sharpens the water/land split")
    axes[0].legend(fontsize=9)
    axes[0].grid(alpha=0.3)

    labels = ["unfiltered", "Lee-filtered"]
    areas = [water_raw.sum() * px_km2, water_lee.sum() * px_km2]
    bars = axes[1].bar(labels, areas, color=["#b0b0b0", "#1f4e79"], width=0.55)
    axes[1].bar_label(bars, fmt="%.1f km²", padding=3, fontsize=11)
    axes[1].set_ylabel("area below the same Otsu threshold (km²)")
    axes[1].set_title(
        f"same threshold, before cleanup\n"
        f"{extra.sum() * px_km2:.1f} km² (={100.0 * extra.sum() / water_raw.sum():.1f}%) is speckle, "
        f"{lost.sum() * px_km2:.1f} km² of thin water lost"
    )
    axes[1].set_ylim(0, max(areas) * 1.18)
    axes[1].grid(axis="y", alpha=0.3)

    fig.suptitle(f"Effect of Lee filtering on the flood map — {cfg['event']['name']}", fontsize=13)
    fig.tight_layout()
    fig_path = figures / "lee_effect.png"
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)

    print(f"Threshold (from mask_stats.csv): {t:.4f} dB")
    print(f"  unfiltered water : {water_raw.sum() * px_km2:8.2f} km2")
    print(f"  Lee-filtered     : {water_lee.sum() * px_km2:8.2f} km2")
    print(f"  speckle extra    : {extra.sum() * px_km2:8.2f} km2 "
          f"({100.0 * extra.sum() / water_raw.sum():.1f}% of unfiltered)")
    print(f"  thin water lost  : {lost.sum() * px_km2:8.2f} km2")
    print(f"  pixel agreement  : {(water_raw == water_lee).mean():.4f}")
    print(f"Open-water std in crop: {std_raw:.2f} -> {std_lee:.2f} dB "
          f"({100.0 * (1 - std_lee / std_raw):.0f}% reduction)")
    print(f"Wrote {tables / 'lee_effect.csv'}")
    print(f"Wrote {fig_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

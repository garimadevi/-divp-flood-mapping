"""Build the agreement-based confidence map from the four flood masks (ADR-04).

For N methods, k = number of methods classifying a pixel as flooded:
    k = N     -> High
    k = N-1   -> Medium
    2 <= k    -> Low (and k <= N-2)
    k <= 1    -> Dry
Pixels with k >= 2 are treated as flood-positive.

Inputs are the cleaned masks from run_masks.py; outputs are the confidence
raster, a class stats table, and a figure.
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

from common import load_config, rel_path, write_geotiff

DB_NODATA = -9999.0
CLASS_CODES = {"dry": 0, "low": 1, "medium": 2, "high": 3}
METHOD_IDS = ["otsu_vv", "otsu_vh", "change_vv", "adaptive_vv"]


def read(path):
    with rasterio.open(path) as src:
        return src.read(1), src.transform, src.crs


def main() -> int:
    cfg = load_config()
    root = Path(cfg["_root"])
    processed = rel_path(cfg, "data_processed")
    maps = rel_path(cfg, "outputs") / "maps" / "masks"
    tables = rel_path(cfg, "outputs") / "tables"
    figures = rel_path(cfg, "outputs") / "figures"
    tables.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)

    post_vv, transform, crs = read(processed / "s1_post_vv_db.tif")
    slope, _, _ = read(processed / "slope_deg.tif")
    permanent, _, _ = read(processed / "masks" / "permanent_water.tif")

    valid = (post_vv != DB_NODATA) & (slope != DB_NODATA)
    base = valid & (permanent == 0)
    slope_ok = slope <= cfg["masks"]["slope_deg_max"]
    domain = base & slope_ok

    masks = {name: read(maps / f"{name}.tif")[0].astype(bool) & domain for name in METHOD_IDS}
    k = np.sum([masks[name].astype(int) for name in METHOD_IDS], axis=0)

    high = k == len(METHOD_IDS)
    medium = k == len(METHOD_IDS) - 1
    low = (k >= 2) & ~high & ~medium
    dry = ~high & ~medium & ~low & domain

    confidence = np.zeros(post_vv.shape, dtype="uint8")
    confidence[low] = CLASS_CODES["low"]
    confidence[medium] = CLASS_CODES["medium"]
    confidence[high] = CLASS_CODES["high"]
    confidence = np.where(domain, confidence, 255)  # 255 = out-of-domain nodata

    out_dir = rel_path(cfg, "outputs") / "maps" / "confidence"
    out_dir.mkdir(parents=True, exist_ok=True)
    write_geotiff(out_dir / "agreement_classes.tif", confidence, transform, crs, 255)
    binary = (k >= 2).astype("uint8")
    write_geotiff(out_dir / "agreement_flood.tif", np.where(domain, binary, 255), transform, crs, 255)

    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6
    rows = []
    for label, mask in (("dry", dry), ("low", low), ("medium", medium), ("high", high)):
        rows.append({
            "class": label,
            "k": "0-1" if label == "dry" else ("2" if label == "low" else ("3" if label == "medium" else "4")),
            "area_km2": f"{mask.sum() * px_km2:.3f}",
            "fraction_of_domain": f"{mask[domain].mean():.5f}",
        })

    with open(tables / "confidence_classes.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["class", "k", "area_km2", "fraction_of_domain"])
        writer.writeheader()
        writer.writerows(rows)

    # figure
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    axes[0].imshow(np.where(valid, post_vv, np.nan), cmap="gray", vmin=-22, vmax=0)
    axes[0].set_title("Post-event VV (dB)")
    axes[1].imshow(np.where(domain, k, np.nan), cmap="viridis", vmin=0, vmax=3)
    axes[1].set_title("Agreement count k (0-3 shown; 4 = high)")
    axes[2].imshow(np.where(domain, confidence, np.nan), cmap="RdYlBu_r", vmin=0, vmax=3)
    axes[2].set_title("Confidence class (0 dry, 1 low, 2 med, 3 high)")
    for ax in axes:
        ax.set_xticks([])
        ax.set_yticks([])
    fig.suptitle(f"Agreement confidence map — {cfg['event']['name']}")
    fig.tight_layout()
    fig_path = figures / "confidence_map.png"
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)

    print("Confidence classes:")
    for row in rows:
        print("  ", row)
    print(f"\nWrote {tables / 'confidence_classes.csv'}")
    print(f"Wrote {out_dir / 'agreement_classes.tif'}")
    print(f"Wrote {out_dir / 'agreement_flood.tif'}")
    print(f"Wrote {fig_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

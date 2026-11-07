"""Build four independent flood masks and their agreement diagnostics.

Methods:
  1. global Otsu on post-event VV
  2. global Otsu on post-event VH
  3. VV change detection (post - pre < threshold)
  4. local adaptive threshold on post-event VV

All masks are cleaned with morphology, small-component removal, permanent-water
masking, and a slope mask.
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
from scipy import ndimage as ndi
from skimage.filters import threshold_otsu

from common import load_config, rel_path, write_geotiff

DB_NODATA = -9999.0


def read(path):
    with rasterio.open(path) as src:
        return src.read(1), src.transform, src.crs


def clean(mask, min_px):
    opened = ndi.binary_opening(mask, structure=np.ones((3, 3), dtype=bool))
    closed = ndi.binary_closing(opened, structure=np.ones((3, 3), dtype=bool))
    labels, _ = ndi.label(closed)
    sizes = np.bincount(labels.ravel())
    keep = sizes >= min_px
    keep[0] = False
    return keep[labels]


def kappa(a, b):
    a = a.astype(bool).ravel()
    b = b.astype(bool).ravel()
    if a.size == 0:
        return float("nan")
    po = float((a == b).mean())
    pa = float(a.mean())
    pb = float(b.mean())
    pe = pa * pb + (1 - pa) * (1 - pb)
    return float((po - pe) / (1 - pe)) if pe < 1 else 0.0


def main() -> int:
    cfg = load_config()
    root = Path(cfg["_root"])
    processed = rel_path(cfg, "data_processed")
    maps = rel_path(cfg, "outputs") / "maps" / "masks"
    maps.mkdir(parents=True, exist_ok=True)
    tables = rel_path(cfg, "outputs") / "tables"
    tables.mkdir(parents=True, exist_ok=True)

    post_vv, transform, crs = read(processed / "s1_post_vv_db.tif")
    pre_vv, _, _ = read(processed / "s1_pre_vv_db.tif")
    post_vh, _, _ = read(processed / "s1_post_vh_db.tif")
    slope, _, _ = read(processed / "slope_deg.tif")
    permanent, _, _ = read(processed / "masks" / "permanent_water.tif")

    valid = (post_vv != DB_NODATA) & (slope != DB_NODATA)
    base = valid & (permanent == 0)
    slope_ok = slope <= cfg["masks"]["slope_deg_max"]
    min_px = int(cfg["flood_masks"]["morphology"]["min_component_px"])

    thresholds = {}
    masks = {}

    otsu_vv = float(threshold_otsu(post_vv[valid]))
    thresholds["otsu_vv"] = otsu_vv
    masks["otsu_vv"] = post_vv < otsu_vv

    otsu_vh = float(threshold_otsu(post_vh[valid]))
    thresholds["otsu_vh"] = otsu_vh
    masks["otsu_vh"] = post_vh < otsu_vh

    change_threshold = float(
        next(m for m in cfg["flood_masks"]["methods"] if m["id"] == "change_vv")["threshold_db"]
    )
    thresholds["change_vv"] = change_threshold
    masks["change_vv"] = (post_vv - pre_vv) < change_threshold

    adaptive_cfg = next(
        m for m in cfg["flood_masks"]["methods"] if m["id"] == "adaptive_vv"
    )
    window = int(adaptive_cfg["window"])
    k_std = float(adaptive_cfg.get("k_std", 2.0))
    filled = np.where(valid, post_vv, np.nanmedian(post_vv[valid])).astype("float32")
    local_mean = ndi.uniform_filter(filled, size=window)
    local_sq = ndi.uniform_filter(filled * filled, size=window)
    local_std = np.sqrt(np.maximum(local_sq - local_mean * local_mean, 0.0))
    local_thresh = local_mean - k_std * local_std
    thresholds["adaptive_vv"] = float(np.nanmedian(local_thresh[valid]))
    masks["adaptive_vv"] = post_vv < local_thresh

    cleaned = {}
    for name, mask in masks.items():
        cleaned[name] = clean(mask & base & slope_ok, min_px)
        path = maps / f"{name}.tif"
        write_geotiff(path, cleaned[name].astype("uint8"), transform, crs, 0)
        print(f"  wrote {path.relative_to(root)}")

    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6
    rows = []
    for name, mask in cleaned.items():
        rows.append(
            {
                "method": name,
                "threshold": f"{thresholds[name]:.4f}",
                "flood_px": int(mask.sum()),
                "flood_km2": f"{mask.sum() * px_km2:.3f}",
                "fraction_nonpermanent": f"{mask[base].mean():.5f}",
            }
        )

    with open(tables / "mask_stats.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    names = list(cleaned.keys())
    kappa_rows = []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            kappa_rows.append({"a": a, "b": b, "kappa": f"{kappa(cleaned[a][base], cleaned[b][base]):.4f}"})

    with open(tables / "mask_kappa.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["a", "b", "kappa"])
        writer.writeheader()
        writer.writerows(kappa_rows)

    fig, axes = plt.subplots(2, 3, figsize=(16, 10))
    axes[0, 0].imshow(np.where(valid, post_vv, np.nan), cmap="gray", vmin=-22, vmax=0)
    axes[0, 0].set_title("Post-event VV (dB)")
    for ax, name in zip(
        [axes[0, 1], axes[0, 2], axes[1, 0], axes[1, 1]],
        ["otsu_vv", "otsu_vh", "change_vv", "adaptive_vv"],
    ):
        ax.imshow(cleaned[name], cmap="Blues", vmin=0, vmax=1)
        ax.set_title(name)
    axes[1, 2].imshow(cleaned["otsu_vv"].astype(int) + cleaned["otsu_vh"].astype(int) + cleaned["change_vv"].astype(int),
                      cmap="viridis", vmin=0, vmax=3)
    axes[1, 2].set_title("Otsu VV + Otsu VH + change (count)")
    for ax in axes.ravel():
        ax.set_xticks([])
        ax.set_yticks([])
    fig.suptitle(f"Flood mask ensemble — {cfg['event']['name']} (diagnostic)")
    fig.tight_layout()
    fig_path = rel_path(cfg, "outputs") / "figures" / "masks_overview.png"
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)

    print("\nMask stats:")
    for row in rows:
        print("  ", row)
    print("\nPairwise kappa:")
    for row in kappa_rows:
        print("  ", row)
    print(f"\nWrote {tables / 'mask_stats.csv'}")
    print(f"Wrote {tables / 'mask_kappa.csv'}")
    print(f"Wrote {fig_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

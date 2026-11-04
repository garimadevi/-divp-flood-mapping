"""Fetch S2 for the 31 May 2025 candidate and compare with the S1 signal."""

from __future__ import annotations

import csv
import sys
from datetime import datetime, timedelta
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import rasterio
from rasterio.enums import Resampling

from common import (
    combine_mosaics,
    load_config,
    read_reprojected,
    rel_path,
    sign_item,
    stac_client,
    target_grid,
    write_geotiff,
)

NODATA = -32768.0


def next_day(date: str) -> str:
    return (datetime.strptime(date, "%Y-%m-%d") + timedelta(days=1)).strftime("%Y-%m-%d")


def to_db(arr):
    out = np.full(arr.shape, np.nan, dtype="float32")
    valid = (arr > 0) & (arr != NODATA)
    out[valid] = 10.0 * np.log10(arr[valid])
    return out


def main() -> int:
    cfg = load_config()
    client = stac_client(cfg)
    transform, width, height, dst_crs = target_grid(cfg)
    out_dir = Path(cfg["_root"]) / "data" / "candidates" / "may31"
    out_dir.mkdir(parents=True, exist_ok=True)

    items = list(
        client.search(
            collections=[cfg["stac"]["collections"]["s2_l2a"]],
            bbox=cfg["aoi"]["bbox"],
            datetime=f"2025-06-09/{next_day('2025-06-09')}",
            max_items=10,
        ).items()
    )
    print(f"S2 tiles: {[it.id for it in items]}")
    signed = [sign_item(it) for it in items]

    for band, resampling in (("B03", Resampling.bilinear), ("B11", Resampling.bilinear), ("SCL", Resampling.nearest)):
        arrays = []
        for item in signed:
            arr = read_reprojected(
                item.assets[band].href, dst_crs, transform, width, height,
                resampling, dst_nodata=0,
            )
            if arr is not None:
                arrays.append(arr)
        mosaic = combine_mosaics(arrays, nodata=0)
        write_geotiff(out_dir / f"s2_{band}.tif", mosaic, transform, dst_crs, 0)
        print(f"  wrote s2_{band}.tif")

    pre = to_db(rasterio.open(out_dir / "pre_vv.tif").read(1).astype("float32"))
    post = to_db(rasterio.open(out_dir / "post_vv.tif").read(1).astype("float32"))
    diff = post - pre
    valid = np.isfinite(pre) & np.isfinite(post)

    b03 = rasterio.open(out_dir / "s2_B03.tif").read(1).astype("float32")
    b11 = rasterio.open(out_dir / "s2_B11.tif").read(1).astype("float32")
    scl = rasterio.open(out_dir / "s2_SCL.tif").read(1)
    jrc = rasterio.open(rel_path(cfg, "data_raw") / "reference" / "jrc_occurrence_aoi.tif").read(1)

    clear = np.isin(scl, [2, 4, 5, 6, 7]) & (b03 > 0) & (b11 > 0)
    denom = b03 + b11
    mndwi = np.full(b03.shape, np.nan, dtype="float32")
    ok = clear & (denom > 0)
    mndwi[ok] = (b03[ok] - b11[ok]) / denom[ok]
    s2_water = np.isfinite(mndwi) & (mndwi > 0)
    permanent = jrc.astype("float32") >= cfg["masks"]["permanent_water"]["occurrence_threshold"]
    s2_water_np = s2_water & ~permanent

    dark16 = valid & (post < -16.0)
    floodlike = dark16 & (diff < -2.0) & ~permanent

    def frac(mask, base):
        return float(mask[base].mean()) if base.sum() else float("nan")

    stats = {
        "s2_clear_fraction": round(float(clear.mean()), 4),
        "s2_water_fraction_clear": round(frac(s2_water, clear), 4),
        "s2_water_fraction_clear_nonpermanent": round(frac(s2_water_np, clear & ~permanent), 4),
        "sar_dark16_where_s2_water": round(frac(dark16, s2_water), 4),
        "sar_dark16_where_s2_nonwater": round(frac(dark16, clear & ~s2_water), 4),
        "sar_floodlike_where_s2_water": round(frac(floodlike, s2_water), 4),
        "sar_floodlike_where_s2_nonwater": round(frac(floodlike, clear & ~s2_water), 4),
    }
    print("S2/SAR check:")
    for key, value in stats.items():
        print(f"  {key}: {value}")

    table = rel_path(cfg, "outputs") / "tables" / "candidate_may31_s2.csv"
    with open(table, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["metric", "value"])
        for key, value in stats.items():
            writer.writerow([key, value])

    fig, axes = plt.subplots(1, 4, figsize=(18, 4.5))
    panels = [
        (axes[0], post, "S1 post VV (dB)", "gray", -22, 0),
        (axes[1], mndwi, "S2 MNDWI (9 Jun 2025)", "RdYlBu", -0.5, 0.5),
        (axes[2], np.where(s2_water_np, 1, 0), "S2 water (non-permanent)", "gray", 0, 1),
        (axes[3], np.where(floodlike, 1, 0), "S1 flood-like", "gray", 0, 1),
    ]
    for ax, data, title, cmap, vmin, vmax in panels:
        im = ax.imshow(data, cmap=cmap, vmin=vmin, vmax=vmax)
        ax.set_title(title)
        ax.set_xticks([])
        ax.set_yticks([])
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.suptitle("31 May 2025 candidate: S1 vs Sentinel-2 (9 Jun 2025)")
    fig.tight_layout()
    fig_path = rel_path(cfg, "outputs") / "figures" / "candidate_may31_s2.png"
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)
    print(f"Wrote {table}")
    print(f"Wrote {fig_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

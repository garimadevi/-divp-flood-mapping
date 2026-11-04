"""Fetch windowed AOI subsets and record SHA256 checksums in the manifest.

Downloads only the AOI window of each Cloud-Optimized GeoTIFF; no full scenes.
Run stac_manifest.py first.
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import rasterio
from rasterio.enums import Resampling

from common import (
    combine_mosaics,
    get_item,
    load_config,
    load_json,
    read_reprojected,
    rel_path,
    save_json,
    sha256_file,
    sign_item,
    stac_client,
    target_grid,
    utc_now,
    write_geotiff,
)


def register(manifest: dict, key: str, path: Path, root: Path) -> None:
    manifest["local_files"][key] = {
        "path": str(path.relative_to(root)).replace("\\", "/"),
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
    }
    print(f"  wrote {path.relative_to(root)} ({path.stat().st_size / 1e6:.2f} MB)")


def fetch_s1(cfg, client, manifest, dst_crs, dst_transform, width, height, root):
    out_dir = rel_path(cfg, "data_raw") / "sentinel1"
    jobs = [
        ("s1_rtc_pre_vv", manifest["datasets"]["s1_rtc_pre"]["item_id"], "vv"),
        ("s1_rtc_pre_vh", manifest["datasets"]["s1_rtc_pre"]["item_id"], "vh"),
        ("s1_rtc_post_vv", manifest["datasets"]["s1_rtc_post"]["item_id"], "vv"),
        ("s1_rtc_post_vh", manifest["datasets"]["s1_rtc_post"]["item_id"], "vh"),
    ]
    cache = {}
    for key, item_id, pol in jobs:
        if item_id not in cache:
            cache[item_id] = sign_item(
                get_item(client, cfg["stac"]["collections"]["s1_rtc"], item_id)
            )
        item = cache[item_id]
        arr = read_reprojected(
            item.assets[pol].href,
            dst_crs,
            dst_transform,
            width,
            height,
            Resampling.bilinear,
            dst_nodata=-32768.0,
        )
        if arr is None:
            raise RuntimeError(f"No overlap for {key}")
        path = out_dir / f"{key}.tif"
        write_geotiff(path, arr, dst_transform, dst_crs, -32768.0)
        register(manifest, key, path, root)


def fetch_s2(cfg, client, manifest, dst_crs, dst_transform, width, height, root):
    out_dir = rel_path(cfg, "data_raw") / "sentinel2"
    tile_items = []
    for entry in manifest["datasets"]:
        if entry.startswith("s2_post_tile_"):
            tile_items.append(manifest["datasets"][entry]["item_id"])

    signed = [
        sign_item(get_item(client, cfg["stac"]["collections"]["s2_l2a"], item_id))
        for item_id in tile_items
    ]

    band_resampling = {
        "B03": Resampling.bilinear,
        "B11": Resampling.bilinear,
        "SCL": Resampling.nearest,
    }
    for band, resampling in band_resampling.items():
        arrays = []
        for item in signed:
            arr = read_reprojected(
                item.assets[band].href,
                dst_crs,
                dst_transform,
                width,
                height,
                resampling,
                dst_nodata=0,
            )
            if arr is not None:
                arrays.append(arr)
        if not arrays:
            raise RuntimeError(f"No S2 overlap for {band}")
        mosaic = combine_mosaics(arrays, nodata=0)
        key = f"s2_post_{band}"
        path = out_dir / f"{key}.tif"
        write_geotiff(path, mosaic, dst_transform, dst_crs, 0)
        register(manifest, key, path, root)


def fetch_single(cfg, client, manifest, key, subdir, collection, item_id, asset,
                 resampling, dst_crs, dst_transform, width, height, root, nodata):
    item = sign_item(get_item(client, collection, item_id))
    arr = read_reprojected(
        item.assets[asset].href,
        dst_crs,
        dst_transform,
        width,
        height,
        resampling,
        dst_nodata=nodata,
    )
    if arr is None:
        raise RuntimeError(f"No overlap for {key}")
    path = rel_path(cfg, "data_raw") / subdir / f"{key}_aoi.tif"
    write_geotiff(path, arr, dst_transform, dst_crs, nodata)
    register(manifest, key, path, root)


def quicklook(cfg, manifest, root):
    base = rel_path(cfg, "data_raw") / "sentinel1"
    pre = rasterio.open(base / "s1_rtc_pre_vv.tif").read(1).astype("float32")
    post = rasterio.open(base / "s1_rtc_post_vv.tif").read(1).astype("float32")

    def to_db(arr):
        out = np.full(arr.shape, np.nan, dtype="float32")
        valid = (arr > 0) & (arr != -32768.0)
        out[valid] = 10.0 * np.log10(arr[valid])
        return out

    pre_db, post_db = to_db(pre), to_db(post)
    diff = post_db - pre_db

    fig, axes = plt.subplots(1, 3, figsize=(16, 5))
    for ax, data, title, kw in (
        (axes[0], pre_db, "Pre-event VV (dB)", {"vmin": -25, "vmax": 5}),
        (axes[1], post_db, "Post-event VV (dB)", {"vmin": -25, "vmax": 5}),
        (axes[2], diff, "Post - pre (dB)", {"vmin": -10, "vmax": 10}),
    ):
        im = ax.imshow(data, cmap="gray" if "diff" not in title else "RdBu", **kw)
        ax.set_title(title)
        ax.set_xticks([])
        ax.set_yticks([])
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.suptitle("Day 2 quicklook — Guwahati AOI (EPSG:32646, 10 m)")
    fig.tight_layout()

    out = rel_path(cfg, "outputs") / "figures" / "day2_quicklook.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150)
    plt.close(fig)
    register(manifest, "day2_quicklook", out, root)


def main() -> int:
    cfg = load_config()
    root = Path(cfg["_root"])
    manifest_path = rel_path(cfg, "manifest")
    manifest = load_json(manifest_path)
    client = stac_client(cfg)
    dst_transform, width, height, dst_crs = target_grid(cfg)

    manifest["grid"].update(
        {
            "width": width,
            "height": height,
            "transform": list(dst_transform)[:6],
            "pixel_area_m2": float(cfg["grid"]["resolution_m"]) ** 2,
        }
    )

    print("Fetching S1 RTC subsets...")
    fetch_s1(cfg, client, manifest, dst_crs, dst_transform, width, height, root)

    print("Fetching S2 subsets (mosaicking tiles)...")
    fetch_s2(cfg, client, manifest, dst_crs, dst_transform, width, height, root)

    print("Fetching DEM...")
    fetch_single(
        cfg, client, manifest, "dem", "dem",
        cfg["stac"]["collections"]["dem"],
        manifest["datasets"]["dem"]["item_id"], cfg["stac"]["assets"]["dem"],
        Resampling.bilinear, dst_crs, dst_transform, width, height, root, -9999.0,
    )

    print("Fetching JRC occurrence...")
    fetch_single(
        cfg, client, manifest, "jrc_occurrence", "reference",
        cfg["stac"]["collections"]["jrc_water"],
        manifest["datasets"]["jrc_water"]["item_id"],
        cfg["stac"]["assets"]["jrc_water"], Resampling.nearest,
        dst_crs, dst_transform, width, height, root, 255,
    )

    print("Fetching WorldCover...")
    fetch_single(
        cfg, client, manifest, "worldcover", "landcover",
        cfg["stac"]["collections"]["worldcover"],
        manifest["datasets"]["worldcover"]["item_id"],
        cfg["stac"]["assets"]["worldcover"], Resampling.nearest,
        dst_crs, dst_transform, width, height, root, 0,
    )

    print("Building quicklook...")
    quicklook(cfg, manifest, root)

    manifest["status"] = "subsets-fetched"
    manifest["fetched_utc"] = utc_now()
    save_json(manifest_path, manifest)
    print(f"\nUpdated {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

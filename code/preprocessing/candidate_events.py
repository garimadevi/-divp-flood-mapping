"""Fetch and gate the two fallback candidates.

Candidate A: 19-20 May 2025 event, RTC pair 7 May / 19 May (ASC rel 41).
Candidate B: 31 May 2025 event, RTC pair 21 May / 2 June (DESC rel 77).

Only Sentinel-1 is fetched here; the winning candidate gets the full S2
reference in the main pipeline. These are diagnostics, not final results.
"""

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
from scipy import ndimage as ndi

from common import (
    combine_mosaics,
    get_item,
    load_config,
    read_reprojected,
    rel_path,
    sign_item,
    stac_client,
    target_grid,
    write_geotiff,
)

CANDIDATES = {
    "may19": {
        "label": "19-20 May 2025",
        "pre_date": "2025-05-07",
        "post_date": "2025-05-19",
        "orbit_state": "ascending",
        "rel_orbit": 41,
    },
    "may31": {
        "label": "31 May 2025",
        "pre_date": "2025-05-21",
        "post_date": "2025-06-02",
        "orbit_state": "descending",
        "rel_orbit": 77,
    },
}
NODATA = -32768.0


def next_day(date: str) -> str:
    d = datetime.strptime(date, "%Y-%m-%d") + timedelta(days=1)
    return d.strftime("%Y-%m-%d")


def find_s1(client, cfg, date, orbit_state, rel_orbit):
    items = list(
        client.search(
            collections=[cfg["stac"]["collections"]["s1_rtc"]],
            bbox=cfg["aoi"]["bbox"],
            datetime=f"{date}/{next_day(date)}",
            max_items=20,
        ).items()
    )
    for item in items:
        if (
            item.properties.get("sat:orbit_state") == orbit_state
            and item.properties.get("sat:relative_orbit") == rel_orbit
        ):
            return item
    raise RuntimeError(f"No S1 RTC for {date} {orbit_state} rel{rel_orbit}")


def to_db(arr):
    out = np.full(arr.shape, np.nan, dtype="float32")
    valid = (arr > 0) & (arr != NODATA)
    out[valid] = 10.0 * np.log10(arr[valid])
    return out


def clean(mask, min_px):
    opened = ndi.binary_opening(mask, structure=np.ones((3, 3), dtype=bool))
    labels, _ = ndi.label(opened)
    sizes = np.bincount(labels.ravel())
    keep = sizes >= min_px
    keep[0] = False
    return keep[labels]


def fetch_event(cfg, client, name, spec, dst_crs, dst_transform, width, height, root):
    out_dir = Path(cfg["_root"]) / "data" / "candidates" / name
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n=== {name}: {spec['label']} ===")
    for role, date in (("pre", spec["pre_date"]), ("post", spec["post_date"])):
        item = sign_item(
            find_s1(client, cfg, date, spec["orbit_state"], spec["rel_orbit"])
        )
        print(f"  {role}: {item.id}")
        for pol in ("vv", "vh"):
            arr = read_reprojected(
                item.assets[pol].href, dst_crs, dst_transform, width, height,
                Resampling.bilinear, dst_nodata=-32768.0,
            )
            if arr is None:
                raise RuntimeError(f"No overlap {name} {role} {pol}")
            path = out_dir / f"pre_{pol}.tif" if role == "pre" else out_dir / f"post_{pol}.tif"
            write_geotiff(path, arr, dst_transform, dst_crs, -32768.0)
            print(f"    wrote {path.name}")
    return out_dir


def gate(cfg, name, spec, out_dir, cfg_root, jrc, lc, dem, px_km2, min_px):
    pre = to_db(rasterio.open(out_dir / "pre_vv.tif").read(1).astype("float32"))
    post = to_db(rasterio.open(out_dir / "post_vv.tif").read(1).astype("float32"))
    diff = post - pre
    valid = np.isfinite(pre) & np.isfinite(post)

    dem_f = dem.astype("float32")
    dy, dx = np.gradient(dem_f, 10.0, 10.0)
    slope = np.degrees(np.arctan(np.hypot(dx, dy)))
    slope[dem_f <= -9000] = np.nan
    slope_ok = np.isfinite(slope) & (slope <= cfg["masks"]["slope_deg_max"])
    permanent = jrc.astype("float32") >= cfg["masks"]["permanent_water"]["occurrence_threshold"]
    urban = lc == 50
    nonperm = valid & ~permanent

    dark16 = valid & (post < -16.0)
    change_neg = valid & (diff < -2.0)
    floodlike = dark16 & change_neg & ~permanent & slope_ok
    floodlike_clean = clean(floodlike, min_px)
    floodlike_urban = floodlike_clean & urban

    def frac(mask, base):
        return float(mask[base].mean()) if base.sum() else float("nan")

    stats = {
        "event": name,
        "label": spec["label"],
        "pre_date": spec["pre_date"],
        "post_date": spec["post_date"],
        "post_dark16_nonpermanent": round(frac(dark16, nonperm), 4),
        "post_dark16_urban_nonpermanent": round(frac(dark16, nonperm & urban), 4),
        "change_lt_minus2_nonpermanent": round(frac(change_neg, nonperm), 4),
        "change_lt_minus2_urban_nonpermanent": round(frac(change_neg, nonperm & urban), 4),
        "floodlike_area_km2": round(float(floodlike.sum()) * px_km2, 3),
        "floodlike_clean_area_km2": round(float(floodlike_clean.sum()) * px_km2, 3),
        "floodlike_clean_urban_area_km2": round(float(floodlike_urban.sum()) * px_km2, 3),
    }

    fig, axes = plt.subplots(1, 4, figsize=(18, 4.5))
    panels = [
        (axes[0], pre, "Pre VV (dB)", "gray", -22, 0),
        (axes[1], post, "Post VV (dB)", "gray", -22, 0),
        (axes[2], diff, "Post - pre (dB)", "RdBu", -8, 8),
        (axes[3], np.where(floodlike_clean, 1, 0), "Flood-like (cleaned)", "gray", 0, 1),
    ]
    for ax, data, title, cmap, vmin, vmax in panels:
        im = ax.imshow(data, cmap=cmap, vmin=vmin, vmax=vmax)
        ax.set_title(title)
        ax.set_xticks([])
        ax.set_yticks([])
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.suptitle(f"Candidate gate: {spec['label']} ({name})")
    fig.tight_layout()
    fig_path = rel_path(cfg, "outputs") / "figures" / f"candidate_{name}.png"
    fig_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)
    return stats


def main() -> int:
    cfg = load_config()
    client = stac_client(cfg)
    transform, width, height, dst_crs = target_grid(cfg)
    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6
    min_px = cfg["flood_masks"]["morphology"]["min_component_px"]

    raw = rel_path(cfg, "data_raw")
    jrc = rasterio.open(raw / "reference" / "jrc_occurrence_aoi.tif").read(1)
    lc = rasterio.open(raw / "landcover" / "worldcover_aoi.tif").read(1)
    dem = rasterio.open(raw / "dem" / "dem_aoi.tif").read(1)

    rows = []
    for name, spec in CANDIDATES.items():
        out_dir = fetch_event(
            cfg, client, name, spec, dst_crs, transform, width, height, cfg["_root"]
        )
        rows.append(
            gate(cfg, name, spec, out_dir, cfg["_root"], jrc, lc, dem, px_km2, min_px)
        )

    table = rel_path(cfg, "outputs") / "tables" / "candidate_gate.csv"
    table.parent.mkdir(parents=True, exist_ok=True)
    with open(table, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print("\nCandidate comparison:")
    for row in rows:
        print(f"  {row['event']} ({row['label']}): "
              f"clean flood-like {row['floodlike_clean_area_km2']} km^2, "
              f"urban {row['floodlike_clean_urban_area_km2']} km^2, "
              f"urban change {row['change_lt_minus2_urban_nonpermanent']}")
    print(f"\nWrote {table}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

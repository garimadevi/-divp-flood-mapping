"""Build the analysis-ready stack: Lee-filtered dB SAR, slope, and masks.

Inputs are the Day 2/3 AOI subsets. Filtering is done on linear power,
then converted to dB (ADR-02). All outputs share the common 10 m grid.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import rasterio
from scipy.ndimage import uniform_filter

from common import (
    load_config,
    rel_path,
    save_json,
    sha256_file,
    utc_now,
    write_geotiff,
)

RAW_NODATA = -32768.0
DB_NODATA = -9999.0


def read_tif(path: Path):
    with rasterio.open(path) as src:
        return src.read(1), src.transform, src.crs, src.nodata


def lee_db(arr, nodata, size: int, looks: float) -> np.ndarray:
    """Lee filter on linear power, then convert to dB."""
    data = arr.astype("float32")
    valid = (data > 0) & (data != nodata)
    fill = np.where(valid, data, 0.0).astype("float32")
    count = uniform_filter(valid.astype("float32"), size=size)
    mean = uniform_filter(fill, size=size) / np.maximum(count, 1e-6)
    mean_sq = uniform_filter(fill * fill, size=size) / np.maximum(count, 1e-6)
    var = np.maximum(mean_sq - mean * mean, 0.0)
    noise_var = (mean * mean) / max(looks, 1.0)
    weight = var / (var + noise_var + 1e-6)
    filtered = mean + weight * (fill - mean)
    db = np.full(data.shape, DB_NODATA, dtype="float32")
    good = valid & (filtered > 0)
    db[good] = 10.0 * np.log10(filtered[good])
    return db


def slope_deg(dem, nodata, res_m: float) -> np.ndarray:
    dem_f = dem.astype("float32")
    valid = dem_f > -9000
    dy, dx = np.gradient(dem_f, res_m, res_m)
    slope = np.degrees(np.arctan(np.hypot(dx, dy))).astype("float32")
    slope[~valid] = DB_NODATA
    return slope


def main() -> int:
    cfg = load_config()
    root = Path(cfg["_root"])
    raw = rel_path(cfg, "data_raw")
    processed = rel_path(cfg, "data_processed")
    processed.mkdir(parents=True, exist_ok=True)
    masks_dir = processed / "masks"
    masks_dir.mkdir(parents=True, exist_ok=True)

    size = int(cfg["sentinel1"]["speckle"]["window"])
    looks = float(cfg["sentinel1"]["speckle"].get("looks", 4))
    res_m = float(cfg["grid"]["resolution_m"])
    files = {}

    for role, prefix in (("pre", "s1_pre"), ("post", "s1_post")):
        for pol in ("vv", "vh"):
            arr, transform, crs, nodata = read_tif(
                raw / "sentinel1" / f"s1_rtc_{role}_{pol}.tif"
            )
            db = lee_db(arr, nodata, size, looks)
            path = processed / f"{prefix}_{pol}_db.tif"
            write_geotiff(path, db, transform, crs, DB_NODATA)
            files[f"{prefix}_{pol}_db"] = {
                "path": str(path.relative_to(root)).replace("\\", "/"),
                "sha256": sha256_file(path),
                "bytes": path.stat().st_size,
            }
            print(f"  wrote {path.relative_to(root)}")

    dem, transform, crs, dem_nodata = read_tif(raw / "dem" / "dem_aoi.tif")
    slope = slope_deg(dem, dem_nodata, res_m)
    path = processed / "slope_deg.tif"
    write_geotiff(path, slope, transform, crs, DB_NODATA)
    files["slope_deg"] = {
        "path": str(path.relative_to(root)).replace("\\", "/"),
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
    }
    print(f"  wrote {path.relative_to(root)}")

    jrc, _, _, _ = read_tif(raw / "reference" / "jrc_occurrence_aoi.tif")
    permanent = (jrc.astype("float32") >= cfg["masks"]["permanent_water"]["occurrence_threshold"]).astype("uint8")
    path = masks_dir / "permanent_water.tif"
    write_geotiff(path, permanent, transform, crs, 0)
    files["permanent_water"] = {"path": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256_file(path)}

    lc, _, _, _ = read_tif(raw / "landcover" / "worldcover_aoi.tif")
    urban = (lc == 50).astype("uint8")
    vegetation = np.isin(lc, [10, 20, 30, 40]).astype("uint8")
    for name, arr in (("urban", urban), ("vegetation", vegetation)):
        path = masks_dir / f"{name}.tif"
        write_geotiff(path, arr, transform, crs, 0)
        files[name] = {"path": str(path.relative_to(root)).replace("\\", "/"), "sha256": sha256_file(path)}

    stack_meta = {
        "generated_utc": utc_now(),
        "event": cfg["event"]["name"],
        "grid": cfg["grid"],
        "speckle": {
            "method": "lee",
            "window": size,
            "looks": looks,
            "applied_on": "linear_power",
        },
        "db": {"formula": "10*log10(power)", "nodata": DB_NODATA},
        "files": files,
        "notes": "Masks are 1 = class present, 0 = absent. Slope is degrees.",
    }
    save_json(processed / "stack_meta.json", stack_meta)
    print(f"\nWrote {processed / 'stack_meta.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Verify Day 2 subsets: CRS, resolution, AOI coverage, nodata fraction."""

from __future__ import annotations

import csv
import sys
from pathlib import Path

import numpy as np
import rasterio

from common import load_config, load_json, rel_path


def main() -> int:
    cfg = load_config()
    root = Path(cfg["_root"])
    manifest = load_json(rel_path(cfg, "manifest"))
    expected_crs = cfg["grid"]["crs"]
    expected_res = float(cfg["grid"]["resolution_m"])

    rows = []
    warnings = []
    for key, meta in manifest["local_files"].items():
        path = root / meta["path"]
        if path.suffix.lower() not in (".tif", ".tiff"):
            continue
        with rasterio.open(path) as src:
            data = src.read(1, out_shape=(1, min(512, src.height), min(512, src.width)))
            nodata = src.nodata
            if nodata is None:
                valid = np.ones(data.shape, dtype=bool)
            else:
                valid = data != nodata
            valid_fraction = float(valid.mean())
            rows.append(
                {
                    "key": key,
                    "crs": str(src.crs),
                    "res_x": f"{abs(src.transform.a):.3f}",
                    "res_y": f"{abs(src.transform.e):.3f}",
                    "width": src.width,
                    "height": src.height,
                    "nodata": nodata,
                    "valid_fraction": f"{valid_fraction:.4f}",
                    "bounds": str(tuple(round(v, 2) for v in src.bounds)),
                }
            )
            if str(src.crs) != expected_crs:
                warnings.append(f"{key}: CRS {src.crs} != {expected_crs}")
            if abs(abs(src.transform.a) - expected_res) > 0.01:
                warnings.append(f"{key}: res {src.transform.a} != {expected_res}")
            if valid_fraction < 0.95:
                warnings.append(f"{key}: valid fraction {valid_fraction:.3f} < 0.95")

    out = rel_path(cfg, "outputs") / "tables" / "day2_coverage.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    grid = manifest["grid"]
    area_km2 = grid["width"] * grid["height"] * grid["pixel_area_m2"] / 1e6
    print(f"Grid: {grid['width']} x {grid['height']} px at "
          f"{cfg['grid']['resolution_m']} m = {area_km2:.2f} km^2")
    print(f"Wrote {out}")
    if warnings:
        print("\nWARNINGS:")
        for warning in warnings:
            print("  -", warning)
    else:
        print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Area of the agreement-based binary flood map, for both 4-member ensembles.

agreement.py builds the confidence map with `adaptive_vv` as the 4th member, but
ADR-23 adopts `gmm` instead. Neither table records the binary area that results,
which leaves two loose ends:

  * the report quotes 122.59 km2 for "the binary flood map (k >= 2)", which is
    the adaptive ensemble, while the refined conclusion adopts GMM;
  * the MATLAB cross-check (matlab/step3_comparing_algorithms.m) needs the GMM
    area as an acceptance value, not a hardcoded constant.

This script computes both from the mask rasters that the report's numbers come
from (outputs/maps/masks/*.tif), so the value is traceable to a file.

Outputs: outputs/tables/ensemble_area.csv
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "preprocessing"))

import numpy as np
import rasterio

from common import load_config, rel_path

ENSEMBLES = {
    "adaptive_4th": ["otsu_vv", "otsu_vh", "change_vv", "adaptive_vv"],
    "gmm_4th": ["otsu_vv", "otsu_vh", "change_vv", "gmm"],
}


def read_mask(path: Path) -> np.ndarray:
    with rasterio.open(path) as src:
        return src.read(1) > 0


def main() -> int:
    cfg = load_config()
    masks_dir = rel_path(cfg, "outputs") / "maps" / "masks"
    tables = rel_path(cfg, "outputs") / "tables"
    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6

    rows = []
    for name, members in ENSEMBLES.items():
        k = np.zeros(read_mask(masks_dir / f"{members[0]}.tif").shape, dtype="uint8")
        for member in members:
            k += read_mask(masks_dir / f"{member}.tif").astype("uint8")
        row = {"ensemble": name, "members": "+".join(members), "n_members": len(members)}
        for cut in (2, 3, 4):
            n = int((k >= cut).sum())
            row[f"k_ge{cut}_px"] = n
            row[f"k_ge{cut}_km2"] = f"{n * px_km2:.3f}"
        rows.append(row)

    with open(tables / "ensemble_area.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print("Binary flood map area by ensemble (k = number of members calling flood):")
    for row in rows:
        print(
            f"  {row['ensemble']:<13} k>=2 {row['k_ge2_km2']:>7} km2 | "
            f"k>=3 {row['k_ge3_km2']:>7} km2 | k>=4 {row['k_ge4_km2']:>6} km2"
        )
    print(f"Wrote {tables / 'ensemble_area.csv'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Sensitivity check: drop the adaptive member and re-measure confidence (ADR-21).

Tests whether a 3-method ensemble (Otsu VV, Otsu VH, change VV) yields a
monotonic reliability curve — i.e. whether High (3/3) becomes the most precise
class once the adaptive method is removed. Reuses the masks and S2 MNDWI already
on disk; downloads nothing.

Reference: Sentinel-2 MNDWI > 0 on clear, non-permanent pixels within the
analysis domain (same as code/confidence/validate.py).
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "preprocessing"))

import numpy as np
import rasterio

from common import load_config, rel_path

DB_NODATA = -9999.0
METHODS_4 = ["otsu_vv", "otsu_vh", "change_vv", "adaptive_vv"]
METHODS_3 = ["otsu_vv", "otsu_vh", "change_vv"]


def read(path):
    with rasterio.open(path) as src:
        return src.read(1)


def binary_metrics(pred, ref, evaluable):
    tp = int((pred & ref & evaluable).sum())
    fp = int((pred & ~ref & evaluable).sum())
    fn = int((~pred & ref & evaluable).sum())
    tn = int((~pred & ~ref & evaluable).sum())
    prec = tp / (tp + fp) if (tp + fp) else float("nan")
    rec = tp / (tp + fn) if (tp + fn) else float("nan")
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else float("nan")
    iou = tp / (tp + fp + fn) if (tp + fp + fn) else float("nan")
    oa = (tp + tn) / (tp + fp + fn + tn) if (tp + fp + fn + tn) else float("nan")
    return {"precision": round(prec, 4), "recall": round(rec, 4), "f1": round(f1, 4),
            "iou": round(iou, 4), "overall_accuracy": round(oa, 4)}


def class_table(k, domain, s2_water, evaluable, px_km2, levels):
    """Return per-class rows for agreement count k with the given class levels."""
    rows = []
    for label, cond in levels:
        cls = cond(k) & domain
        tp = int((cls & s2_water).sum())
        eval_px = int((cls & evaluable).sum())
        prec = tp / eval_px if eval_px else float("nan")
        rec = tp / s2_water.sum() if s2_water.sum() else float("nan")
        rows.append({"class": label, "area_km2": f"{cls.sum() * px_km2:.3f}",
                     "precision": round(prec, 4), "recall": round(rec, 4)})
    return rows


def main() -> int:
    cfg = load_config()
    processed = rel_path(cfg, "data_processed")
    maps = rel_path(cfg, "outputs") / "maps" / "masks"
    tables = rel_path(cfg, "outputs") / "tables"
    tables.mkdir(parents=True, exist_ok=True)

    post_vv = read(processed / "s1_post_vv_db.tif")
    slope = read(processed / "slope_deg.tif")
    permanent = read(processed / "masks" / "permanent_water.tif")

    valid = (post_vv != DB_NODATA) & (slope != DB_NODATA)
    base = valid & (permanent == 0)
    slope_ok = slope <= cfg["masks"]["slope_deg_max"]
    domain = base & slope_ok

    s2p = rel_path(cfg, "data_raw") / "sentinel2"
    b03 = read(s2p / "s2_post_B03.tif").astype("float32")
    b11 = read(s2p / "s2_post_B11.tif").astype("float32")
    scl = read(s2p / "s2_post_SCL.tif")
    clear = np.isin(scl, [2, 4, 5, 6, 7]) & (b03 > 0) & (b11 > 0)
    denom = b03 + b11
    mndwi = np.full(b03.shape, np.nan, dtype="float32")
    ok = clear & (denom > 0)
    mndwi[ok] = (b03[ok] - b11[ok]) / denom[ok]
    s2_water = np.isfinite(mndwi) & (mndwi > cfg["validation"]["mndwi"]["threshold"]) & domain
    evaluable = clear & domain

    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6
    masks4 = {n: read(maps / f"{n}.tif").astype(bool) & domain for n in METHODS_4}
    masks3 = {n: masks4[n] for n in METHODS_3}

    k4 = np.sum([masks4[n].astype(int) for n in METHODS_4], axis=0)
    k3 = np.sum([masks3[n].astype(int) for n in METHODS_3], axis=0)

    levels4 = [("dry", lambda k: k <= 1), ("low", lambda k: k == 2),
               ("medium", lambda k: k == 3), ("high", lambda k: k == 4)]
    levels3 = [("dry", lambda k: k <= 0), ("low", lambda k: k == 1),
               ("medium", lambda k: k == 2), ("high", lambda k: k == 3)]

    rows4 = class_table(k4, domain, s2_water, evaluable, px_km2, levels4)
    rows3 = class_table(k3, domain, s2_water, evaluable, px_km2, levels3)

    # binary flood-positive: k>=2 (both ensembles use >=2)
    bin4 = binary_metrics((k4 >= 2) & domain, s2_water, evaluable)
    bin3 = binary_metrics((k3 >= 2) & domain, s2_water, evaluable)

    # write long-format table
    with open(tables / "sensitivity_drop_adaptive.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.writer(h)
        w.writerow(["ensemble", "class", "area_km2", "precision", "recall"])
        for r in rows4:
            w.writerow(["4-method", r["class"], r["area_km2"], r["precision"], r["recall"]])
        for r in rows3:
            w.writerow(["3-method", r["class"], r["area_km2"], r["precision"], r["recall"]])

    with open(tables / "sensitivity_drop_adaptive_binary.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.writer(h)
        w.writerow(["ensemble", "metric", "value"])
        for kk in ["precision", "recall", "f1", "iou", "overall_accuracy"]:
            w.writerow(["4-method", kk, bin4[kk]])
            w.writerow(["3-method", kk, bin3[kk]])

    print("Domain {:.1f} km2; S2 water {:.2f} km2".format(domain.sum() * px_km2, s2_water.sum() * px_km2))
    print("\nPer-class precision (class -> precision):")
    print("  4-method:", {r["class"]: r["precision"] for r in rows4})
    print("  3-method:", {r["class"]: r["precision"] for r in rows3})
    print("\nBinary flood (k>=2):")
    print("  4-method:", bin4)
    print("  3-method:", bin3)

    # monotonicity verdict
    p4 = {r["class"]: r["precision"] for r in rows4}
    p3 = {r["class"]: r["precision"] for r in rows3}
    h3, m3, l3 = p3["high"], p3["medium"], p3["low"]
    mono3 = (h3 >= m3) and (m3 >= l3)
    print("\n3-method reliability monotonic (high>=medium>=low)?", mono3)
    print("  4-method: high {:.4f} vs medium {:.4f} (high is {} precise)".format(
        p4["high"], p4["medium"], "MORE" if p4["high"] > p4["medium"] else "LESS"))
    print("  3-method: high {:.4f} vs medium {:.4f} (high is {} precise)".format(
        h3, m3, "MORE" if h3 > m3 else "LESS"))

    print("\nWrote outputs/tables/sensitivity_drop_adaptive.csv")
    print("Wrote outputs/tables/sensitivity_drop_adaptive_binary.csv")
    return 0


if __name__ == "__main__":
    sys.exit(main())

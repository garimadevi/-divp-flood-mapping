"""Validate the flood ensemble and agreement-confidence map against Sentinel-2 MNDWI.

Reference: non-permanent surface water from Sentinel-2 MNDWI > 0 on clear
pixels within the analysis domain (ADR-05). Outputs per-method and
per-confidence-class metrics, plus a reliability curve.
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

from common import load_config, rel_path

DB_NODATA = -9999.0
METHOD_IDS = ["otsu_vv", "otsu_vh", "change_vv", "adaptive_vv"]


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
            "iou": round(iou, 4), "overall_accuracy": round(oa, 4), "tp": tp, "fp": fp, "fn": fn, "tn": tn}


def main() -> int:
    cfg = load_config()
    processed = rel_path(cfg, "data_processed")
    maps = rel_path(cfg, "outputs") / "maps" / "masks"
    tables = rel_path(cfg, "outputs") / "tables"
    figures = rel_path(cfg, "outputs") / "figures"
    tables.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)

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
    print(f"Domain {domain.sum() * px_km2:.1f} km2; S2 clear {evaluable.sum() * px_km2:.1f} km2 "
          f"({evaluable[domain].mean():.3f}); S2 non-perm water {s2_water.sum() * px_km2:.2f} km2")

    masks = {name: read(maps / f"{name}.tif").astype(bool) & domain for name in METHOD_IDS}
    k = np.sum([masks[name].astype(int) for name in METHOD_IDS], axis=0)
    flood = (k >= 2) & domain

    # per-method metrics
    method_rows = []
    for name in METHOD_IDS:
        m = binary_metrics(masks[name], s2_water, evaluable)
        method_rows.append({"method": name, **{kk: m[kk] for kk in
                            ["precision", "recall", "f1", "iou", "overall_accuracy"]}})
    with open(tables / "metrics_by_method.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["method", "precision", "recall", "f1", "iou", "overall_accuracy"])
        writer.writeheader()
        writer.writerows(method_rows)

    # binary flood (k>=2)
    bf = binary_metrics(flood, s2_water, evaluable)
    with open(tables / "metrics_flood_binary.csv", "w", newline="", encoding="utf-8") as handle:
        w = csv.writer(handle)
        w.writerow(["metric", "value"])
        for kk in ["precision", "recall", "f1", "iou", "overall_accuracy"]:
            w.writerow([kk, bf[kk]])

    # per-class reliability
    class_rows = []
    classes = [("dry", (k <= 1) & domain), ("low", (k == 2) & domain),
               ("medium", (k == 3) & domain), ("high", (k == 4) & domain)]
    for label, cls in classes:
        tp = int((cls & s2_water).sum())
        eval_px = int((cls & evaluable).sum())
        prec = tp / eval_px if eval_px else float("nan")
        rec = tp / s2_water.sum() if s2_water.sum() else float("nan")
        class_rows.append({"class": label, "area_km2": f"{cls.sum() * px_km2:.3f}",
                           "precision": round(prec, 4), "recall": round(rec, 4)})
    with open(tables / "metrics_by_class.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["class", "area_km2", "precision", "recall"])
        writer.writeheader()
        writer.writerows(class_rows)

    # reliability figure
    order = ["dry", "low", "medium", "high"]
    precs = {r["class"]: r["precision"] for r in class_rows}
    areas = {r["class"]: float(r["area_km2"]) for r in class_rows}
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    axes[0].plot(order, [precs[o] for o in order], "o-", color="tab:blue")
    axes[0].set_ylabel("Observed precision (vs S2 water)")
    axes[0].set_xlabel("Confidence class")
    axes[0].set_title("Reliability curve (class vs precision)")
    axes[0].set_ylim(0, 1)
    axes[0].grid(alpha=0.3)
    axes[1].bar(order, [areas[o] for o in order], color=["0.8", "tab:orange", "tab:green", "tab:red"])
    axes[1].set_ylabel("Area (km^2)")
    axes[1].set_title("Class areas")
    fig.suptitle(f"Confidence validation — {cfg['event']['name']}")
    fig.tight_layout()
    fig_path = figures / "reliability_curve.png"
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)

    print("\nPer-method metrics (vs S2 non-perm water, clear pixels):")
    for row in method_rows:
        print("  ", row)
    print("\nBinary flood (k>=2):", bf)
    print("\nPer-class reliability:")
    for row in class_rows:
        print("  ", row)
    print(f"\nWrote {tables / 'metrics_by_method.csv'}")
    print(f"Wrote {tables / 'metrics_by_class.csv'}")
    print(f"Wrote {tables / 'metrics_flood_binary.csv'}")
    print(f"Wrote {fig_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Block bootstrap confidence intervals for the flood-map and reliability metrics.

Pixels are spatially autocorrelated, so a naive pixel bootstrap underestimates
variance. This uses a spatial block bootstrap (block size from config, default
500 m) over the evaluated (clear, non-permanent) pixels, resampling blocks with
replacement and recomputing precision / recall / F1 / IoU.

Two outputs:
  * binary flood map (GMM ensemble, k >= 2) metric CIs,
  * per-confidence-class precision CIs (the reliability curve with error bars).

Outputs: outputs/tables/bootstrap_ci.csv, outputs/figures/reliability_ci.png
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
METHODS = ["otsu_vv", "otsu_vh", "change_vv", "gmm"]


def read(path):
    with rasterio.open(path) as src:
        return src.read(1)


def blockify(a, block_px):
    H, W = a.shape
    H2 = ((H + block_px - 1) // block_px) * block_px
    W2 = ((W + block_px - 1) // block_px) * block_px
    padded = np.pad(a.astype(bool), ((0, H2 - H), (0, W2 - W)), constant_values=False)
    return padded.reshape(H2 // block_px, block_px, W2 // block_px, block_px).sum(axis=(1, 3))


def ci(arr):
    arr = np.asarray(arr)
    return {"lo": float(np.percentile(arr, 2.5)), "med": float(np.percentile(arr, 50)),
            "hi": float(np.percentile(arr, 97.5))}


def block_bootstrap(tp, fp, fn, tn, block_px, n_iter, seed=42):
    rng = np.random.default_rng(seed)
    tp_b = blockify(tp, block_px).ravel()
    fp_b = blockify(fp, block_px).ravel()
    fn_b = blockify(fn, block_px).ravel()
    tn_b = blockify(tn, block_px).ravel()
    nb = tp_b.size
    prec, rec, f1, iou = [], [], [], []
    for _ in range(n_iter):
        idx = rng.integers(0, nb, size=nb)
        tp_ = int(tp_b[idx].sum())
        fp_ = int(fp_b[idx].sum())
        fn_ = int(fn_b[idx].sum())
        tn_ = int(tn_b[idx].sum())
        p = tp_ / (tp_ + fp_) if (tp_ + fp_) else np.nan
        r = tp_ / (tp_ + fn_) if (tp_ + fn_) else np.nan
        f = 2 * p * r / (p + r) if (p + r) else np.nan
        i = tp_ / (tp_ + fp_ + fn_) if (tp_ + fp_ + fn_) else np.nan
        prec.append(p)
        rec.append(r)
        f1.append(f)
        iou.append(i)
    return {"precision": ci(prec), "recall": ci(rec), "f1": ci(f1), "iou": ci(iou)}


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

    k = sum(read(maps / f"{m}.tif").astype(bool).astype(int) for m in METHODS)
    flood = (k >= 2) & domain

    bs = cfg["validation"]["bootstrap"]
    n_iter = int(bs["n"])
    block_px = int(round(bs["block_m"] / cfg["grid"]["resolution_m"]))

    # ---- binary flood ----
    tp = flood & s2_water & evaluable
    fp = flood & ~s2_water & evaluable
    fn = ~flood & s2_water & evaluable
    tn = ~flood & ~s2_water & evaluable
    binary = block_bootstrap(tp, fp, fn, tn, block_px, n_iter)

    # ---- per-class precision ----
    classes = [("dry", (k <= 1)), ("low", (k == 2)), ("medium", (k == 3)), ("high", (k == 4))]
    class_ci = {}
    for label, cond in classes:
        cls = cond & domain
        tp_c = cls & s2_water & evaluable
        fp_c = cls & ~s2_water & evaluable
        fn_c = ~cls & s2_water & evaluable
        tn_c = ~cls & ~s2_water & evaluable
        class_ci[label] = block_bootstrap(tp_c, fp_c, fn_c, tn_c, block_px, n_iter)

    # ---- write CSV ----
    rows = []
    rows.append({"scope": "binary", "class": "-", "metric": "precision", **binary["precision"]})
    rows.append({"scope": "binary", "class": "-", "metric": "recall", **binary["recall"]})
    rows.append({"scope": "binary", "class": "-", "metric": "f1", **binary["f1"]})
    rows.append({"scope": "binary", "class": "-", "metric": "iou", **binary["iou"]})
    for label, _ in classes:
        rows.append({"scope": "class", "class": label, "metric": "precision", **class_ci[label]["precision"]})

    with open(tables / "bootstrap_ci.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=["scope", "class", "metric", "lo", "med", "hi"])
        w.writeheader()
        w.writerows(rows)

    # ---- figure: reliability curve with 95% CI ----
    order = ["dry", "low", "medium", "high"]
    labels = ["Dry", "Low", "Medium", "High"]
    meds = [class_ci[c]["precision"]["med"] for c in order]
    los = [class_ci[c]["precision"]["lo"] for c in order]
    his = [class_ci[c]["precision"]["hi"] for c in order]
    err_lo = [m - l for m, l in zip(meds, los)]
    err_hi = [h - m for h, m in zip(his, meds)]

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.errorbar(labels, meds, yerr=[err_lo, err_hi], fmt="o-", capsize=6, lw=2, color="tab:blue")
    for x, m in zip(labels, meds):
        ax.text(x, m, f"{m * 100:.1f}%", ha="center", va="bottom", fontsize=9)
    ax.set_ylim(0, 1.05)
    ax.set_ylabel("Observed precision (vs S2 water)")
    ax.set_xlabel("Confidence class")
    ax.set_title("GMM-ensemble reliability curve with 95% bootstrap CI")
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig_path = figures / "reliability_ci.png"
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)

    print(f"Block bootstrap: block {block_px} px, {n_iter} iterations")
    print(f"Binary flood F1: {binary['f1']['med']:.4f} [95% CI {binary['f1']['lo']:.4f}, {binary['f1']['hi']:.4f}]")
    print(f"Binary precision: {binary['precision']['med']:.4f} [{binary['precision']['lo']:.4f}, {binary['precision']['hi']:.4f}]")
    print(f"Binary recall: {binary['recall']['med']:.4f} [{binary['recall']['lo']:.4f}, {binary['recall']['hi']:.4f}]")
    print("Per-class precision (median [95% CI]):")
    for label, _ in classes:
        c = class_ci[label]["precision"]
        print(f"  {label:7s} {c['med']:.4f} [{c['lo']:.4f}, {c['hi']:.4f}]")
    print(f"Wrote {tables / 'bootstrap_ci.csv'}")
    print(f"Wrote {fig_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

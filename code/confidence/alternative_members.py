"""Alternative 4th ensemble member: Kittler-Illingworth and GMM thresholding.

Extends the sensitivity analysis (ADR-22): instead of only dropping the adaptive
member, this compares candidate replacements for the 4th slot — the local
adaptive threshold, the Kittler-Illingworth minimum-error threshold, and a
2-component Gaussian-mixture threshold — and runs a leave-one-out ablation over
the four original methods.

For each candidate it reports:
  * its own precision / recall / F1 / IoU vs Sentinel-2 MNDWI,
  * its mean pairwise kappa against the three "good" methods,
  * whether a 4-method ensemble (3 good + candidate) yields a monotonic
    reliability curve, and the resulting binary-flood F1.

Reuses the masks and S2 MNDWI already on disk; downloads nothing.
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

from common import load_config, rel_path, write_geotiff

DB_NODATA = -9999.0
GOOD = ["otsu_vv", "otsu_vh", "change_vv"]
ALL_METHODS = ["otsu_vv", "otsu_vh", "change_vv", "adaptive_vv"]


def read(path):
    with rasterio.open(path) as src:
        return src.read(1)


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


def kittler_threshold(x, bins=256):
    """Kittler-Illingworth minimum-error threshold (histogram, 2 Gaussians)."""
    x = np.asarray(x, dtype=np.float64)
    x = x[np.isfinite(x)]
    lo, hi = float(x.min()), float(x.max())
    if hi <= lo:
        return float("nan")
    hist, edges = np.histogram(x, bins=bins, range=(lo, hi))
    centers = (edges[:-1] + edges[1:]) / 2.0
    total = float(hist.sum())
    best_t, best_j = None, np.inf
    for i in range(1, len(centers)):
        h1, h2 = hist[:i], hist[i:]
        c1, c2 = centers[:i], centers[i:]
        n1, n2 = float(h1.sum()), float(h2.sum())
        if n1 == 0 or n2 == 0:
            continue
        p1, p2 = n1 / total, n2 / total
        m1 = float((h1 * c1).sum() / n1)
        m2 = float((h2 * c2).sum() / n2)
        v1 = float((h1 * (c1 - m1) ** 2).sum() / n1)
        v2 = float((h2 * (c2 - m2) ** 2).sum() / n2)
        if v1 <= 0 or v2 <= 0:
            continue
        s1, s2 = np.sqrt(v1), np.sqrt(v2)
        j = 1.0 + 2.0 * (p1 * np.log(s1) + p2 * np.log(s2)) - 2.0 * (p1 * np.log(p1) + p2 * np.log(p2))
        if j < best_j:
            best_j, best_t = j, float(centers[i])
    return best_t


def gmm_threshold(x, n_iter=40, n_grid=20001):
    """2-component Gaussian-mixture threshold via EM; decision boundary between modes."""
    x = np.asarray(x, dtype=np.float64)
    x = x[np.isfinite(x)]
    if x.size == 0:
        return float("nan")
    mu1 = float(np.percentile(x, 35))
    mu2 = float(np.percentile(x, 65))
    s1 = s2 = float(np.std(x))
    w1 = w2 = 0.5
    for _ in range(n_iter):
        p1 = np.exp(-0.5 * ((x - mu1) / s1) ** 2) / (s1 * np.sqrt(2 * np.pi))
        p2 = np.exp(-0.5 * ((x - mu2) / s2) ** 2) / (s2 * np.sqrt(2 * np.pi))
        r = w1 * p1 / (w1 * p1 + w2 * p2 + 1e-300)
        n1 = r.sum()
        n2 = x.size - n1
        w1 = float(n1 / x.size)
        w2 = 1.0 - w1
        mu1 = float((r * x).sum() / n1)
        mu2 = float(((1.0 - r) * x).sum() / n2)
        s1 = max(float(np.sqrt((r * (x - mu1) ** 2).sum() / n1)), 1e-6)
        s2 = max(float(np.sqrt(((1.0 - r) * (x - mu2) ** 2).sum() / n2)), 1e-6)
    if mu1 > mu2:
        mu1, mu2 = mu2, mu1
        s1, s2 = s2, s1
        w1, w2 = w2, w1
    xs = np.linspace(mu1, mu2, n_grid)
    lp1 = np.log(w1) - np.log(s1) - 0.5 * ((xs - mu1) / s1) ** 2
    lp2 = np.log(w2) - np.log(s2) - 0.5 * ((xs - mu2) / s2) ** 2
    d = lp1 - lp2
    cross = np.where(np.diff(np.sign(d)) != 0)[0]
    return float(xs[cross[0]]) if cross.size else float((mu1 + mu2) / 2.0)


def binary_metrics(pred, ref, evaluable):
    tp = int((pred & ref & evaluable).sum())
    fp = int((pred & ~ref & evaluable).sum())
    fn = int((~pred & ref & evaluable).sum())
    tn = int((~pred & ~ref & evaluable).sum())
    prec = tp / (tp + fp) if (tp + fp) else float("nan")
    rec = tp / (tp + fn) if (tp + fn) else float("nan")
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else float("nan")
    iou = tp / (tp + fp + fn) if (tp + fp + fn) else float("nan")
    return {"precision": round(prec, 4), "recall": round(rec, 4), "f1": round(f1, 4), "iou": round(iou, 4)}


def class_precisions(k, N, domain, s2_water, evaluable, px_km2):
    defs = {
        4: {"high": (k == 4), "medium": (k == 3), "low": (k == 2), "dry": (k <= 1)},
        3: {"high": (k == 3), "medium": (k == 2), "low": (k == 1), "dry": (k == 0)},
    }
    out = {}
    for label, m in defs[N].items():
        cls = m & domain
        tp = int((cls & s2_water).sum())
        eval_px = int((cls & evaluable).sum())
        out[label] = {
            "area_km2": round(float(cls.sum()) * px_km2, 3),
            "precision": round(tp / eval_px, 4) if eval_px else float("nan"),
        }
    return out


def main() -> int:
    cfg = load_config()
    processed = rel_path(cfg, "data_processed")
    maps = rel_path(cfg, "outputs") / "maps" / "masks"
    tables = rel_path(cfg, "outputs") / "tables"
    figures = rel_path(cfg, "outputs") / "figures"
    maps.mkdir(parents=True, exist_ok=True)
    tables.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)

    post_vv, transform, crs = (lambda s: (s.read(1), s.transform, s.crs))(rasterio.open(processed / "s1_post_vv_db.tif"))
    post_vh = read(processed / "s1_post_vh_db.tif")
    slope = read(processed / "slope_deg.tif")
    permanent = read(processed / "masks" / "permanent_water.tif")

    valid = (post_vv != DB_NODATA) & (slope != DB_NODATA)
    base = valid & (permanent == 0)
    slope_ok = slope <= cfg["masks"]["slope_deg_max"]
    domain = base & slope_ok
    min_px = int(cfg["flood_masks"]["morphology"]["min_component_px"])
    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6

    # ---- reference: S2 MNDWI water (same as validate.py) ----
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

    # ---- candidate thresholds (Kittler, GMM) on post-event VV ----
    x_fit = post_vv[valid].astype("float64")
    x_fit_gmm = x_fit[::8]  # deterministic subsample keeps EM fast
    thresholds = {
        "kittler": kittler_threshold(x_fit),
        "gmm": gmm_threshold(x_fit_gmm),
    }
    # original four thresholds come from the canonical mask run (mask_stats.csv)
    if (tables / "mask_stats.csv").exists():
        with open(tables / "mask_stats.csv", newline="", encoding="utf-8") as h:
            for row in csv.DictReader(h):
                thresholds.setdefault(row["method"], float(row["threshold"]))

    # ---- build candidate masks ----
    candidate_masks = {
        "adaptive_vv": read(maps / "adaptive_vv.tif").astype(bool) & domain,
        "kittler": clean((post_vv < thresholds["kittler"]) & base & slope_ok, min_px),
        "gmm": clean((post_vv < thresholds["gmm"]) & base & slope_ok, min_px),
    }
    for name in ("kittler", "gmm"):
        write_geotiff(maps / f"{name}.tif", candidate_masks[name].astype("uint8"), transform, crs, 0)
        print(f"  wrote {name}.tif (threshold {thresholds[name]:.4f} dB)")

    good_masks = {n: read(maps / f"{n}.tif").astype(bool) & domain for n in GOOD}

    # ---- per-method metrics (all 6 methods) ----
    method_rows = []
    all_masks = {**good_masks, **candidate_masks}
    for name in ALL_METHODS + ["kittler", "gmm"]:
        m = all_masks[name]
        bm = binary_metrics(m, s2_water, evaluable)
        k_mean = float(np.nanmean([kappa(m[domain], good_masks[g][domain]) for g in GOOD]))
        method_rows.append({
            "method": name,
            "threshold": f"{thresholds.get(name, float('nan')):.4f}",
            "area_km2": round(float(m.sum()) * px_km2, 3),
            "kappa_mean": round(k_mean, 3),
            **bm,
        })

    # ---- 4-method ensemble comparison (3 good + candidate) ----
    ens_rows = []
    ens_curves = {}
    for cand in ("adaptive_vv", "kittler", "gmm"):
        members = [good_masks[n] for n in GOOD] + [candidate_masks[cand]]
        k = np.sum([mm.astype(int) for mm in members], axis=0)
        cp = class_precisions(k, 4, domain, s2_water, evaluable, px_km2)
        bf = binary_metrics((k >= 2) & domain, s2_water, evaluable)
        mono = bool(cp["high"]["precision"] >= cp["medium"]["precision"] >= cp["low"]["precision"])
        ens_rows.append({
            "candidate_4th": cand,
            "high_prec": cp["high"]["precision"],
            "medium_prec": cp["medium"]["precision"],
            "low_prec": cp["low"]["precision"],
            "monotonic": mono,
            "binary_f1": bf["f1"],
            "binary_precision": bf["precision"],
            "binary_recall": bf["recall"],
        })
        ens_curves[cand] = cp

    # ---- leave-one-out ablation (drop each of the 4 original methods) ----
    loo_rows = []
    loo_curves = {}
    for drop in ALL_METHODS:
        remaining = [n for n in ALL_METHODS if n != drop]
        members = [all_masks[n] for n in remaining]
        k = np.sum([mm.astype(int) for mm in members], axis=0)
        cp = class_precisions(k, 3, domain, s2_water, evaluable, px_km2)
        bf = binary_metrics((k >= 2) & domain, s2_water, evaluable)
        mono = bool(cp["high"]["precision"] >= cp["medium"]["precision"] >= cp["low"]["precision"])
        loo_rows.append({
            "dropped": drop,
            "high_prec": cp["high"]["precision"],
            "medium_prec": cp["medium"]["precision"],
            "low_prec": cp["low"]["precision"],
            "monotonic": mono,
            "binary_f1": bf["f1"],
        })
        loo_curves[drop] = cp

    # ---- figures ----
    # (a) per-method metrics
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    meth = [r["method"] for r in method_rows]
    prec = [r["precision"] for r in method_rows]
    rec = [r["recall"] for r in method_rows]
    f1 = [r["f1"] for r in method_rows]
    xp = np.arange(len(meth))
    axes[0].bar(xp - 0.27, prec, 0.24, label="precision", color="tab:blue")
    axes[0].bar(xp, rec, 0.24, label="recall", color="tab:orange")
    axes[0].bar(xp + 0.27, f1, 0.24, label="F1", color="tab:green")
    axes[0].set_xticks(xp)
    axes[0].set_xticklabels(meth, rotation=30, ha="right", fontsize=8)
    axes[0].set_ylim(0, 1)
    axes[0].set_title("Per-method metrics vs S2 water")
    axes[0].legend()
    axes[0].grid(alpha=0.3)
    kappa_vals = [r["kappa_mean"] for r in method_rows]
    axes[1].bar(xp, kappa_vals, color="tab:purple")
    axes[1].set_xticks(xp)
    axes[1].set_xticklabels(meth, rotation=30, ha="right", fontsize=8)
    axes[1].set_ylabel("mean kappa vs 3 good methods")
    axes[1].set_ylim(0, 1)
    axes[1].set_title("Agreement with the three 'good' methods")
    axes[1].grid(alpha=0.3)
    fig.suptitle("Candidate 4th member — individual quality")
    fig.tight_layout()
    fig.savefig(figures / "candidate_members.png", dpi=140)
    plt.close(fig)

    # (b) reliability curves: adaptive-4 vs kittler-4 vs gmm-4 vs drop-adaptive-3
    order = ["dry", "low", "medium", "high"]
    labels = ["Dry", "Low", "Medium", "High"]
    panels = [
        ("adaptive_vv", "4-method + adaptive", ens_curves["adaptive_vv"]),
        ("kittler", "4-method + Kittler", ens_curves["kittler"]),
        ("gmm", "4-method + GMM", ens_curves["gmm"]),
        ("drop-adaptive", "3-method (drop adaptive)", loo_curves["adaptive_vv"]),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(13, 9), sharey=True)
    for ax, (_, title, cp) in zip(axes.ravel(), panels):
        vals = [cp[c]["precision"] for c in order]
        ax.plot(labels, vals, "o-", color="tab:blue", lw=2, markersize=9)
        for xx, v in zip(labels, vals):
            ax.text(xx, v, f"{v * 100:.1f}%", ha="center", va="bottom", fontsize=8)
        mono = cp["high"]["precision"] >= cp["medium"]["precision"]
        ax.set_title(f"{title}  ({'monotonic ✓' if mono else 'non-monotonic ✗'})", fontsize=10)
        ax.set_ylim(0, 1.05)
        ax.grid(alpha=0.3)
        ax.set_xlabel("Confidence class")
        if ax in (axes[0, 0], axes[1, 0]):
            ax.set_ylabel("Observed precision")
    fig.suptitle("Reliability curves: which 4th member restores monotonicity?")
    fig.tight_layout()
    fig.savefig(figures / "alternative_members_reliability.png", dpi=140)
    plt.close(fig)

    # ---- write tables + recommendation ----
    with open(tables / "candidate_members.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=list(method_rows[0].keys()))
        w.writeheader()
        w.writerows(method_rows)

    with open(tables / "ensemble_4th_member.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=list(ens_rows[0].keys()))
        w.writeheader()
        w.writerows(ens_rows)

    with open(tables / "leave_one_out.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=list(loo_rows[0].keys()))
        w.writeheader()
        w.writerows(loo_rows)

    # recommendation: prefer monotonic 4-method; among those, highest binary F1
    mono_rows = [r for r in ens_rows if r["monotonic"]]
    if mono_rows:
        best = max(mono_rows, key=lambda r: r["binary_f1"])
        rec = f"Best 4th member: {best['candidate_4th']} (monotonic, binary F1 {best['binary_f1']})"
    else:
        best = max(ens_rows, key=lambda r: r["binary_f1"])
        rec = (f"No 4-method ensemble is monotonic; best binary F1 is {best['candidate_4th']} "
               f"({best['binary_f1']}); recommend the 3-method ensemble instead.")

    print("\n=== per-method ===")
    for r in method_rows:
        print("  ", r)
    print("\n=== 4-method ensembles (3 good + candidate) ===")
    for r in ens_rows:
        print("  ", r)
    print("\n=== leave-one-out (3-method after dropping) ===")
    for r in loo_rows:
        print("  ", r)
    print("\nRECOMMENDATION:", rec)

    print("\nWrote outputs/tables/candidate_members.csv")
    print("Wrote outputs/tables/ensemble_4th_member.csv")
    print("Wrote outputs/tables/leave_one_out.csv")
    print("Wrote outputs/figures/candidate_members.png")
    print("Wrote outputs/figures/alternative_members_reliability.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())

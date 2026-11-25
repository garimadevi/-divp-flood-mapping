"""Static-mask parameter sensitivity: is 50 % the right JRC cut?

Two questions, one script.

1. WHY 50?  The permanent-water mask exists to stop water that was already
   there from being counted as flood. That is testable: compare the JRC
   occurrence bands against the PRE-EVENT SAR (11 June, 12 days before the
   flood peak). If a band is already water before the event, removing it is
   correct; if it only becomes water at the peak, removing it deletes flood.
   This is the evidence for ADR-06's 50 % cut -- not the fact that the number
   was written down early.

2. HOW MUCH DOES IT MATTER?  Hold every other parameter fixed and move one at
   a time (JRC 0/50/70/90, slope 10/15/20, adaptive window 51/151, k_std
   1.5/2.0), rebuilding the adopted GMM ensemble each time, and report the
   analysis-domain area and the k >= 2 flood area.

Nothing canonical is modified. Thresholds are recomputed exactly as
run_masks.py / alternative_members.py do (the Otsu cut and the GMM cut are
invariant to the JRC and slope masks because they are fitted on `valid`), the
rasters are opened read-only, and every output is a new CSV under
outputs/tables.

Closes claims_ledger C-009 ("flood extent with and without permanent-water
masking") and discharges ADR-06's stated consequence.

Outputs:
  outputs/tables/jrc_preevent_test.csv
  outputs/tables/static_masks_sensitivity.csv
  outputs/tables/adaptive_member_sensitivity.csv
  outputs/tables/jrc_validation_sensitivity.csv
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "preprocessing"))

import numpy as np
import rasterio
from scipy import ndimage as ndi
from skimage.filters import threshold_otsu

from alternative_members import gmm_threshold
from common import load_config, rel_path

DB_NODATA = -9999.0
ADOPTED = ["otsu_vv", "otsu_vh", "change_vv", "gmm"]


def read(path: Path) -> np.ndarray:
    with rasterio.open(path) as src:
        return src.read(1)


def clean(mask: np.ndarray, min_px: int) -> np.ndarray:
    """Exactly run_masks.py clean(): opening -> closing -> drop < min_px."""
    opened = ndi.binary_opening(mask, structure=np.ones((3, 3), dtype=bool))
    closed = ndi.binary_closing(opened, structure=np.ones((3, 3), dtype=bool))
    labels, _ = ndi.label(closed)
    sizes = np.bincount(labels.ravel())
    keep = sizes >= min_px
    keep[0] = False
    return keep[labels]


def binary_metrics(pred, ref, evaluable) -> dict:
    tp = int((pred & ref & evaluable).sum())
    fp = int((pred & ~ref & evaluable).sum())
    fn = int((~pred & ref & evaluable).sum())
    tn = int((~pred & ~ref & evaluable).sum())
    prec = tp / (tp + fp) if (tp + fp) else float("nan")
    rec = tp / (tp + fn) if (tp + fn) else float("nan")
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else float("nan")
    iou = tp / (tp + fp + fn) if (tp + fp + fn) else float("nan")
    oa = (tp + tn) / (tp + tn + fp + fn) if (tp + tn + fp + fn) else float("nan")
    return {
        "precision": round(prec, 4),
        "recall": round(rec, 4),
        "f1": round(f1, 4),
        "iou": round(iou, 4),
        "overall_accuracy": round(oa, 4),
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn,
    }


def build_adopted(post_vv, post_vh, pre_vv, domain, thr, min_px) -> dict:
    raw = {
        "otsu_vv": post_vv < thr["otsu_vv"],
        "otsu_vh": post_vh < thr["otsu_vh"],
        "change_vv": (post_vv - pre_vv) < thr["change_vv"],
        "gmm": post_vv < thr["gmm"],
    }
    return {name: clean(mask & domain, min_px) for name, mask in raw.items()}


def votes(masks: dict) -> np.ndarray:
    k = np.zeros(next(iter(masks.values())).shape, dtype="uint8")
    for mask in masks.values():
        k += mask
    return k


def main() -> int:
    cfg = load_config()
    processed = rel_path(cfg, "data_processed")
    raw_dir = rel_path(cfg, "data_raw")
    tables = rel_path(cfg, "outputs") / "tables"
    tables.mkdir(parents=True, exist_ok=True)

    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6
    min_px = int(cfg["flood_masks"]["morphology"]["min_component_px"])
    slope_max = float(cfg["masks"]["slope_deg_max"])
    jrc_cut = float(cfg["masks"]["permanent_water"]["occurrence_threshold"])
    mndwi_t = float(cfg["validation"]["mndwi"]["threshold"])

    post_vv = read(processed / "s1_post_vv_db.tif")
    post_vh = read(processed / "s1_post_vh_db.tif")
    pre_vv = read(processed / "s1_pre_vv_db.tif")
    slope = read(processed / "slope_deg.tif")
    occ = read(raw_dir / "reference" / "jrc_occurrence_aoi.tif")
    permanent = read(processed / "masks" / "permanent_water.tif")

    valid = (post_vv != DB_NODATA) & (slope != DB_NODATA)
    base = valid & (permanent == 0)
    slope_ok = slope <= slope_max
    domain = base & slope_ok

    # ---- thresholds, recomputed exactly as the canonical scripts do ----
    # Otsu and GMM are fitted on `valid`, so they do not move when the JRC or
    # slope mask moves: only the domain changes. That is what makes the
    # one-at-a-time sensitivity below a clean comparison.
    thr = {
        "otsu_vv": float(threshold_otsu(post_vv[valid])),
        "otsu_vh": float(threshold_otsu(post_vh[valid])),
        "change_vv": float(
            next(m for m in cfg["flood_masks"]["methods"] if m["id"] == "change_vv")[
                "threshold_db"
            ]
        ),
        "gmm": float(gmm_threshold(post_vv[valid][::8])),
    }

    print("Thresholds (fitted on `valid`, invariant to the static masks):")
    for name in ADOPTED:
        print(f"  {name:<10} {thr[name]:8.4f} dB")
    print(
        f"\nvalid {valid.sum() * px_km2:.1f} km2 | base {base.sum() * px_km2:.1f} km2 "
        f"| domain {domain.sum() * px_km2:.3f} km2"
    )

    # =====================================================================
    # Part 1 - what does the permanent-water mask actually remove?
    # =====================================================================
    both = valid & np.isfinite(pre_vv)
    t_pre = float(threshold_otsu(pre_vv[both]))
    pre_water = pre_vv < t_pre
    post_water = post_vv < thr["otsu_vv"]
    new_water = ~pre_water & post_water

    print(f"\n=== Part 1 - pre-event test (pre Otsu {t_pre:.3f} dB, post Otsu {thr['otsu_vv']:.3f} dB) ===")
    print(f"{'JRC band':<10}{'km2':>10}{'water BEFORE':>15}{'NEW water':>12}")

    pre_rows = []
    for lo in range(0, 100, 10):
        hi = lo + 10
        band = both & (occ >= lo) & (occ < hi)  # occ == 255 nodata excluded
        n = int(band.sum())
        if n == 0:
            continue
        wb = int((pre_water & band).sum()) / n
        nw = int((new_water & band).sum()) / n
        pre_rows.append(
            {
                "kind": "band",
                "label": f"{lo}-{hi}%",
                "area_km2": f"{n * px_km2:.2f}",
                "water_before_pct": f"{100 * wb:.1f}",
                "new_water_pct": f"{100 * nw:.1f}",
            }
        )
        print(f"{lo:>3}-{hi:<3}%{'':<2}{n * px_km2:>10.2f}{100 * wb:>14.1f}%{100 * nw:>11.1f}%")

    print(f"\n{'cut':<10}{'excluded km2':>14}{'water BEFORE':>15}{'NEW water':>12}")
    for cut in (50, 70, 90):
        excluded = valid & (occ >= cut) & slope_ok
        n = int(excluded.sum())
        wb = int((pre_water & excluded).sum()) / n
        nw = int((new_water & excluded).sum()) / n
        pre_rows.append(
            {
                "kind": "cut",
                "label": f"JRC>={cut}% excluded",
                "area_km2": f"{n * px_km2:.2f}",
                "water_before_pct": f"{100 * wb:.1f}",
                "new_water_pct": f"{100 * nw:.1f}",
            }
        )
        print(f"{cut:>3}%{'':<5}{n * px_km2:>14.2f}{100 * wb:>14.1f}%{100 * nw:>11.1f}%")

    with open(tables / "jrc_preevent_test.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=["kind", "label", "area_km2", "water_before_pct", "new_water_pct"])
        w.writeheader()
        w.writerows(pre_rows)

    # =====================================================================
    # Part 2 - sensitivity of the adopted GMM ensemble (k >= 2)
    # =====================================================================
    sens_rows = []
    maps_for_validation = {}

    def record(parameter, value, dom, flood, note):
        dom_km2 = dom.sum() * px_km2
        flood_km2 = flood.sum() * px_km2
        sens_rows.append(
            {
                "parameter": parameter,
                "value": value,
                "domain_km2": f"{dom_km2:.3f}",
                "flood_k2_km2": f"{flood_km2:.3f}",
                "note": note,
            }
        )
        return dom_km2, flood_km2

    canonical = {}
    print("\n=== Part 2 - one parameter at a time, adopted GMM ensemble (k >= 2) ===")

    # --- JRC permanent-water cut: 0 (no mask), 50, 70, 90 ---
    for cut in (0, 50, 70, 90):
        dom = valid & slope_ok if cut == 0 else valid & ~(occ >= cut) & slope_ok
        masks = build_adopted(post_vv, post_vh, pre_vv, dom, thr, min_px)
        flood = (votes(masks) >= 2) & dom
        note = (
            "no permanent-water mask (ADR-06 comparison)"
            if cut == 0
            else ("canonical" if cut == int(jrc_cut) else "alternative cut")
        )
        dom_km2, flood_km2 = record("jrc_occurrence", cut, dom, flood, note)
        canonical.setdefault(cut, (dom_km2, flood_km2))
        if cut in (0, 50, 90):
            maps_for_validation[cut] = (dom, flood)
        print(f"  JRC {cut:>3}%   domain {dom_km2:8.2f} km2   flood {flood_km2:8.2f} km2   {note}")
        del masks, flood

    # --- slope cut: 10, 15, 20 ---
    for smax in (10.0, 15.0, 20.0):
        dom = valid & ~(occ >= jrc_cut) & (slope <= smax)
        masks = build_adopted(post_vv, post_vh, pre_vv, dom, thr, min_px)
        flood = (votes(masks) >= 2) & dom
        note = "canonical" if smax == slope_max else "alternative cut"
        dom_km2, flood_km2 = record("slope_deg_max", smax, dom, flood, note)
        print(f"  slope {smax:>4.0f} deg  domain {dom_km2:8.2f} km2   flood {flood_km2:8.2f} km2   {note}")
        del masks, flood

    with open(tables / "static_masks_sensitivity.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(
            h,
            fieldnames=["parameter", "value", "domain_km2", "flood_k2_km2", "note"],
        )
        w.writeheader()
        w.writerows(sens_rows)

    # --- adaptive member: window / k_std (NOT in the adopted ensemble) ---
    print("\n=== Part 3 - adaptive member (diagnostic; not in the adopted ensemble) ===")
    filled = np.where(valid, post_vv, np.nanmedian(post_vv[valid])).astype("float32")
    adaptive_rows = []
    for window, k_std in ((51, 1.5), (151, 1.5), (51, 2.0)):
        mu = ndi.uniform_filter(filled, size=window)
        mu2 = ndi.uniform_filter(filled * filled, size=window)
        local_thresh = mu - k_std * np.sqrt(np.maximum(mu2 - mu * mu, 0.0))
        median_db = float(np.nanmedian(local_thresh[valid]))
        mask = clean((post_vv < local_thresh) & domain, min_px)
        km2 = mask.sum() * px_km2
        adaptive_rows.append(
            {
                "window_px": window,
                "k_std": k_std,
                "median_threshold_db": f"{median_db:.4f}",
                "member_km2": f"{km2:.3f}",
                "note": "canonical" if (window, k_std) == (51, 1.5) else "alternative",
            }
        )
        print(
            f"  window {window:>3}  k {k_std:.1f}   median {median_db:8.4f} dB   "
            f"member {km2:7.2f} km2"
        )
        del mu, mu2, local_thresh, mask

    with open(tables / "adaptive_member_sensitivity.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(
            h,
            fieldnames=["window_px", "k_std", "median_threshold_db", "member_km2", "note"],
        )
        w.writeheader()
        w.writerows(adaptive_rows)

    # =====================================================================
    # Part 4 - does the JRC cut change the validation score?
    # =====================================================================
    print("\n=== Part 4 - validation against Sentinel-2 MNDWI, by JRC cut ===")
    s2p = raw_dir / "sentinel2"
    b03 = read(s2p / "s2_post_B03.tif").astype("float32")
    b11 = read(s2p / "s2_post_B11.tif").astype("float32")
    scl = read(s2p / "s2_post_SCL.tif")
    clear = np.isin(scl, [2, 4, 5, 6, 7]) & (b03 > 0) & (b11 > 0)
    denom = b03 + b11
    mndwi = np.full(b03.shape, np.nan, dtype="float32")
    ok = clear & (denom > 0)
    mndwi[ok] = (b03[ok] - b11[ok]) / denom[ok]

    # Of the band JRC 90 re-admits, how much is water in the optical reference?
    band = valid & (occ >= 50) & (occ < 90) & slope_ok & clear
    band_s2_water = (mndwi > mndwi_t) & band
    band_water_pct = 100 * band_s2_water.sum() / max(int(band.sum()), 1)
    print(f"  S2 water in the 50-90 % occurrence band: {band_water_pct:.1f}% (n={int(band.sum())} clear px)")

    val_rows = []
    for mode in ("own_domain", "fixed_domain"):
        label = (
            "each cut's own domain (what the report would say)"
            if mode == "own_domain"
            else "the fixed canonical domain (like-for-like)"
        )
        print(f"  -- scored on {label}")
        for cut in (0, 50, 90):
            dom, flood = maps_for_validation[cut]
            if mode == "own_domain":
                evaluable = clear & dom
                ref = np.isfinite(mndwi) & (mndwi > mndwi_t) & dom
                pred = flood
            else:
                evaluable = clear & domain
                ref = np.isfinite(mndwi) & (mndwi > mndwi_t) & domain
                pred = flood & domain
            m = binary_metrics(pred, ref, evaluable)
            note = (
                "canonical"
                if cut == int(jrc_cut)
                else (
                    "reference and evaluation set move with the domain"
                    if mode == "own_domain"
                    else "same evaluation set for every map"
                )
            )
            val_rows.append(
                {
                    "mode": mode,
                    "jrc_cut": cut,
                    "domain_km2": f"{dom.sum() * px_km2:.2f}",
                    "evaluable_km2": f"{evaluable.sum() * px_km2:.2f}",
                    "reference_water_km2": f"{ref.sum() * px_km2:.2f}",
                    **{k: m[k] for k in ("precision", "recall", "f1", "iou", "overall_accuracy")},
                    "tp": m["tp"],
                    "fp": m["fp"],
                    "fn": m["fn"],
                    "tn": m["tn"],
                    "note": note,
                }
            )
            print(
                f"  JRC {cut:>3}%   precision {m['precision']:.4f}  recall {m['recall']:.4f}  "
                f"F1 {m['f1']:.4f}"
            )

    with open(tables / "jrc_validation_sensitivity.csv", "w", newline="", encoding="utf-8") as h:
        w = csv.DictWriter(h, fieldnames=list(val_rows[0].keys()))
        w.writeheader()
        w.writerows(val_rows)

    # =====================================================================
    # Self-check
    # =====================================================================
    print("\n--- static_masks_sensitivity verification ---")

    report(domain.sum() == int((valid & (permanent == 0) & slope_ok).sum()),
           "canonical domain is identical to the pipeline's base & slope_ok")

    # the rebuilt canonical masks must be pixel-identical to the committed ones
    rebuilt = build_adopted(post_vv, post_vh, pre_vv, domain, thr, min_px)
    exact = True
    for name in ADOPTED:
        stored = read(rel_path(cfg, "outputs") / "maps" / "masks" / f"{name}.tif").astype(bool)
        diff = int(np.count_nonzero(rebuilt[name] != stored))
        exact = exact and diff == 0
        if diff:
            print(f"       {name}: {diff} px differ from the committed mask")
    report(exact, "rebuilt canonical masks are pixel-identical to outputs/maps/masks/*.tif")

    canonical_flood = int(((votes(rebuilt) >= 2) & domain).sum()) * px_km2
    with open(tables / "ensemble_area.csv", newline="", encoding="utf-8") as h:
        ea = {row["ensemble"]: row for row in csv.DictReader(h)}
    expected = float(ea["gmm_4th"]["k_ge2_km2"])
    report(abs(canonical_flood - expected) < 0.01,
           f"canonical k>=2 area {canonical_flood:.3f} km2 matches ensemble_area.csv {expected:.3f}")

    # the pre-event water fraction must rise with occurrence (bands >= 10 %)
    rises = [
        float(r["water_before_pct"])
        for r in pre_rows
        if r["kind"] == "band" and not r["label"].startswith("0-")
    ]
    report(all(b >= a - 1.0 for a, b in zip(rises, rises[1:])),
           "pre-event water fraction rises monotonically with JRC occurrence")

    report(abs(sum(float(r["area_km2"]) for r in pre_rows if r["kind"] == "band")
               - valid.sum() * px_km2) < 1.0,
           "occurrence bands partition the valid area")

    print(f"\nWrote {tables / 'jrc_preevent_test.csv'}")
    print(f"Wrote {tables / 'static_masks_sensitivity.csv'}")
    print(f"Wrote {tables / 'adaptive_member_sensitivity.csv'}")
    print(f"Wrote {tables / 'jrc_validation_sensitivity.csv'}")

    # =====================================================================
    # Take-away
    # =====================================================================
    ex50 = next(r for r in pre_rows if r["label"] == "JRC>=50% excluded")
    print("\n--- take-away ---")
    print(
        f"At 50 %, the mask removes {ex50['area_km2']} km2 of which "
        f"{ex50['water_before_pct']}% was already water on the pre-event date and only "
        f"{ex50['new_water_pct']}% becomes water at the flood peak."
    )
    print(
        "So the cut is not justified by being written down first: it is justified by what "
        "it removes. Moving to 90 % keeps the 50-89 % band in the map, and "
        f"{band_water_pct:.1f}% of that band is water in the optical reference -- i.e. river, "
        "not flood."
    )
    fixed = {int(r["jrc_cut"]): float(r["f1"]) for r in val_rows if r["mode"] == "fixed_domain"}
    print(
        f"On a fixed evaluation set the score barely moves (F1 {fixed[0]:.4f} / "
        f"{fixed[50]:.4f} / {fixed[90]:.4f} at JRC 0 / 50 / 90): the cut changes the map's "
        "area and definition, not its accuracy on common ground. The larger F1 in the "
        "'own domain' rows comes from the reference moving with the domain."
    )
    return 0


def report(ok: bool, msg: str) -> None:
    print(f"{'PASS' if ok else 'FAIL'}  {msg}")


if __name__ == "__main__":
    sys.exit(main())

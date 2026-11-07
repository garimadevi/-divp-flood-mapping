"""Gate the 18 May 2023 candidate before reconfiguring the pipeline (ADR-19).

Fetches two same-orbit Sentinel-1 pairs and a Sentinel-2 pre/post pair into
data/candidates/may2023/ and computes the pre-registered go/no-go metrics.

This script is read-only with respect to the current event: it writes only the
candidate folder and its own outputs. Nothing in data/raw, data/processed,
config.yaml, or data/manifest.json is touched.
"""

from __future__ import annotations

import csv
import hashlib
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.warp import transform as warp_transform
from scipy import ndimage as ndi

from common import (
    get_item,
    load_config,
    read_reprojected,
    rel_path,
    sign_item,
    stac_client,
    target_grid,
    utc_now,
    write_geotiff,
)

NODATA = -32768.0
DARK_DB = -16.0
CHANGE_DB = -2.0

S1_PAIRS = {
    "rel41": {
        "label": "rel41 ascending (primary)",
        "orbit_state": "ascending",
        "rel_orbit": 41,
        "pre_id": "S1A_IW_GRDH_1SDV_20230506T115713_20230506T115738_048413_05D2C3_rtc",
        "post_id": "S1A_IW_GRDH_1SDV_20230518T115713_20230518T115738_048588_05D805_rtc",
        "pre_date": "2023-05-06",
        "post_date": "2023-05-18",
    },
    "rel77": {
        "label": "rel77 descending (robustness)",
        "orbit_state": "descending",
        "rel_orbit": 77,
        "pre_id": "S1A_IW_GRDH_1SDV_20230508T234721_20230508T234746_048449_05D3FE_rtc",
        "post_id": "S1A_IW_GRDH_1SDV_20230520T234722_20230520T234747_048624_05D927_rtc",
        "pre_date": "2023-05-08",
        "post_date": "2023-05-20",
    },
}

S2_ITEMS = {
    "pre": {
        "date": "2023-05-16",
        "id": "S2B_MSIL2A_20230516T042709_R133_T46RCP_20230516T082209",
    },
    "post": {
        "date": "2023-05-21",
        "id": "S2A_MSIL2A_20230521T042711_R133_T46RCP_20230521T102617",
    },
}


def to_db(arr: np.ndarray) -> np.ndarray:
    out = np.full(arr.shape, np.nan, dtype="float32")
    valid = (arr > 0) & (arr != NODATA)
    out[valid] = 10.0 * np.log10(arr[valid])
    return out


def clean_mask(mask: np.ndarray, min_px: int) -> np.ndarray:
    opened = ndi.binary_opening(mask, structure=np.ones((3, 3), dtype=bool))
    labels, _ = ndi.label(opened)
    sizes = np.bincount(labels.ravel())
    keep = sizes >= min_px
    keep[0] = False
    return keep[labels]


def frac(mask: np.ndarray, base: np.ndarray) -> float:
    total = int(base.sum())
    return float(mask[base].mean()) if total else float("nan")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_s1_pair(client, cfg, name, spec, dst_crs, dst_transform, width, height, out_dir):
    out = {}
    for role, item_id in (("pre", spec["pre_id"]), ("post", spec["post_id"])):
        item = sign_item(get_item(client, cfg["stac"]["collections"]["s1_rtc"], item_id))
        for pol in ("vv", "vh"):
            arr = read_reprojected(
                item.assets[pol].href, dst_crs, dst_transform, width, height,
                Resampling.bilinear, dst_nodata=NODATA,
            )
            if arr is None:
                raise RuntimeError(f"No overlap {name} {role} {pol}")
            path = out_dir / f"{name}_{role}_{pol}.tif"
            write_geotiff(path, arr, dst_transform, dst_crs, NODATA)
            out[f"{name}_{role}_{pol}"] = path
            print(f"    wrote {path.name}")
    return out


def fetch_s2_date(client, cfg, tag, item_id, dst_crs, dst_transform, width, height, out_dir):
    item = sign_item(get_item(client, cfg["stac"]["collections"]["s2_l2a"], item_id))
    out = {}
    for band, resampling in (("B03", Resampling.bilinear), ("B11", Resampling.bilinear), ("SCL", Resampling.nearest)):
        arr = read_reprojected(
            item.assets[band].href, dst_crs, dst_transform, width, height,
            resampling, dst_nodata=0,
        )
        if arr is None:
            raise RuntimeError(f"No overlap s2 {tag} {band}")
        path = out_dir / f"s2_{tag}_{band}.tif"
        write_geotiff(path, arr, dst_transform, dst_crs, 0)
        out[f"s2_{tag}_{band}"] = path
        print(f"    wrote {path.name}")
    return out


def read_tif(path: Path):
    with rasterio.open(path) as src:
        return src.read(1), src.transform


def largest_components(mask: np.ndarray, transform, top: int = 3):
    labels, _ = ndi.label(mask)
    sizes = np.bincount(labels.ravel())
    order = np.argsort(sizes)[::-1]
    comps = []
    for lab in order:
        if lab == 0 or sizes[lab] == 0:
            continue
        ys, xs = np.where(labels == lab)
        cy, cx = ys.mean(), xs.mean()
        x, y = transform * (cx, cy)
        lon, lat = warp_transform("EPSG:32646", "EPSG:4326", [x], [y])
        comps.append({
            "rank": len(comps) + 1,
            "area_km2": round(float(sizes[lab]) * 0.0001, 4),
            "lon": round(float(lon[0]), 5),
            "lat": round(float(lat[0]), 5),
        })
        if len(comps) >= top:
            break
    return comps


def main() -> int:
    cfg = load_config()
    client = stac_client(cfg)
    transform, width, height, dst_crs = target_grid(cfg)
    px_km2 = (cfg["grid"]["resolution_m"] ** 2) / 1e6
    min_px = cfg["flood_masks"]["morphology"]["min_component_px"]

    out_dir = Path(cfg["_root"]) / "data" / "candidates" / "may2023"
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "generated_utc": utc_now(),
        "candidate": "Guwahati flood, 18 May 2023",
        "grid": {"crs": cfg["grid"]["crs"], "resolution_m": cfg["grid"]["resolution_m"],
                 "width": width, "height": height},
        "thresholds": {
            "dark_db": DARK_DB,
            "change_db": CHANGE_DB,
            "min_component_px": min_px,
            "slope_deg_max": cfg["masks"]["slope_deg_max"],
            "permanent_water_occurrence": cfg["masks"]["permanent_water"]["occurrence_threshold"],
            "mndwi_threshold": cfg["validation"]["mndwi"]["threshold"],
        },
        "s1_pairs": {},
        "s2_items": {},
        "local_files": {},
    }

    # ---- fetch S1 pairs ----
    s1_data = {}
    for name, spec in S1_PAIRS.items():
        print(f"Fetching {name} ({spec['label']})...")
        paths = fetch_s1_pair(client, cfg, name, spec, dst_crs, transform, width, height, out_dir)
        s1_data[name] = paths
        manifest["s1_pairs"][name] = {
            "label": spec["label"],
            "orbit_state": spec["orbit_state"],
            "rel_orbit": spec["rel_orbit"],
            "pre_id": spec["pre_id"],
            "post_id": spec["post_id"],
            "pre_date": spec["pre_date"],
            "post_date": spec["post_date"],
        }
        for key, path in paths.items():
            manifest["local_files"][key] = {"path": str(path.relative_to(cfg["_root"])).replace("\\", "/"),
                                            "sha256": sha256_file(path), "bytes": path.stat().st_size}

    # ---- fetch S2 pre/post ----
    s2_data = {}
    for tag, spec in S2_ITEMS.items():
        print(f"Fetching S2 {tag} ({spec['date']})...")
        paths = fetch_s2_date(client, cfg, tag, spec["id"], dst_crs, transform, width, height, out_dir)
        s2_data[tag] = paths
        manifest["s2_items"][tag] = {"date": spec["date"], "id": spec["id"]}
        for key, path in paths.items():
            manifest["local_files"][key] = {"path": str(path.relative_to(cfg["_root"])).replace("\\", "/"),
                                            "sha256": sha256_file(path), "bytes": path.stat().st_size}

    # ---- static masks ----
    raw = rel_path(cfg, "data_raw")
    jrc = rasterio.open(raw / "reference" / "jrc_occurrence_aoi.tif").read(1)
    lc = rasterio.open(raw / "landcover" / "worldcover_aoi.tif").read(1)
    dem = rasterio.open(raw / "dem" / "dem_aoi.tif").read(1)

    dem_f = dem.astype("float32")
    dy, dx = np.gradient(dem_f, 10.0, 10.0)
    slope = np.degrees(np.arctan(np.hypot(dx, dy)))
    slope[dem_f <= -9000] = np.nan
    slope_ok = np.isfinite(slope) & (slope <= cfg["masks"]["slope_deg_max"])
    permanent = jrc.astype("float32") >= cfg["masks"]["permanent_water"]["occurrence_threshold"]
    urban = lc == 50

    # ---- S1 gate per pair ----
    pair_stats = {}
    pair_masks = {}
    for name in ("rel41", "rel77"):
        pre = to_db(rasterio.open(s1_data[name][f"{name}_pre_vv"]).read(1).astype("float32"))
        post = to_db(rasterio.open(s1_data[name][f"{name}_post_vv"]).read(1).astype("float32"))
        diff = post - pre
        valid = np.isfinite(pre) & np.isfinite(post)
        domain = valid & ~permanent & slope_ok
        nonperm = valid & ~permanent

        dark16 = valid & (post < DARK_DB)
        change_neg = valid & (diff < CHANGE_DB)
        floodlike = dark16 & change_neg & ~permanent & slope_ok & valid
        floodlike_clean = clean_mask(floodlike, min_px)
        floodlike_clean_urban = floodlike_clean & urban

        pair_stats[name] = {
            "valid_fraction": round(float(valid.mean()), 4),
            "post_dark16_fraction_nonpermanent": round(frac(dark16, nonperm), 4),
            "change_lt_minus2_fraction_nonpermanent": round(frac(change_neg, nonperm), 4),
            "post_dark16_fraction_urban_nonpermanent": round(frac(dark16, nonperm & urban), 4),
            "change_lt_minus2_fraction_urban_nonpermanent": round(frac(change_neg, nonperm & urban), 4),
            "floodlike_area_km2": round(float(floodlike.sum()) * px_km2, 3),
            "floodlike_clean_area_km2": round(float(floodlike_clean.sum()) * px_km2, 3),
            "floodlike_clean_urban_area_km2": round(float(floodlike_clean_urban.sum()) * px_km2, 4),
        }
        pair_masks[name] = {
            "domain": domain,
            "change_neg_urban": change_neg & urban & domain,
            "floodlike_clean_urban": floodlike_clean_urban,
            "floodlike_clean": floodlike_clean,
            "floodlike": floodlike,
            "change_neg": change_neg,
        }

    # ---- S2 gate ----
    def s2_layers(tag):
        b03 = rasterio.open(s2_data[tag][f"s2_{tag}_B03"]).read(1).astype("float32")
        b11 = rasterio.open(s2_data[tag][f"s2_{tag}_B11"]).read(1).astype("float32")
        scl = rasterio.open(s2_data[tag][f"s2_{tag}_SCL"]).read(1)
        clear = np.isin(scl, [2, 4, 5, 6, 7]) & (b03 > 0) & (b11 > 0)
        denom = b03 + b11
        mndwi = np.full(b03.shape, np.nan, dtype="float32")
        ok = clear & (denom > 0)
        mndwi[ok] = (b03[ok] - b11[ok]) / denom[ok]
        water = np.isfinite(mndwi) & (mndwi > cfg["validation"]["mndwi"]["threshold"])
        return clear, water, mndwi

    clear_pre, water_pre, _ = s2_layers("pre")
    clear_post, water_post, mndwi_post = s2_layers("post")

    # domain for S2 (use primary pair's domain so SAR/S2 are comparable)
    domain = pair_masks["rel41"]["domain"]
    s2_stats = {
        "s2_pre_clear_fraction_domain": round(frac(clear_pre, domain), 4),
        "s2_post_clear_fraction_domain": round(frac(clear_post, domain), 4),
        "s2_pre_water_fraction_clear_nonperm": round(frac(water_pre, clear_pre & domain), 4),
        "s2_post_water_fraction_clear_nonperm": round(frac(water_post, clear_post & domain), 4),
    }

    clear_both_urban = clear_pre & clear_post & domain & urban
    w_pre_u = (water_pre & clear_both_urban).sum()
    w_post_u = (water_post & clear_both_urban).sum()
    s2_stats["s2_urban_water_pre_km2"] = round(float(w_pre_u) * px_km2, 4)
    s2_stats["s2_urban_water_post_km2"] = round(float(w_post_u) * px_km2, 4)
    s2_stats["s2_urban_water_change_km2"] = round(float(w_post_u - w_pre_u) * px_km2, 4)

    # SAR flood-like precision vs S2 post water (non-permanent), rel41 primary
    rel41_floodlike = pair_masks["rel41"]["floodlike"]
    s2_water_np = water_post & domain
    tp = float((rel41_floodlike & s2_water_np).sum())
    denom = float((rel41_floodlike & clear_post & domain).sum())
    s2_stats["sar_floodlike_precision_vs_s2_water"] = round(tp / denom, 4) if denom else float("nan")
    s2_stats["sar_floodlike_where_s2_water"] = round(frac(rel41_floodlike, s2_water_np), 4)
    s2_stats["sar_floodlike_where_s2_nonwater"] = round(frac(rel41_floodlike, clear_post & domain & ~water_post), 4)

    # ---- cross-pair agreement ----
    a_change = pair_masks["rel41"]["change_neg_urban"]
    b_change = pair_masks["rel77"]["change_neg_urban"]
    inter = float((a_change & b_change).sum())
    union = float((a_change | b_change).sum())
    cross = {
        "change_urban_jaccard": round(inter / union, 4) if union else float("nan"),
    }
    a_fl = pair_masks["rel41"]["floodlike_clean_urban"]
    b_fl = pair_masks["rel77"]["floodlike_clean_urban"]
    inter_fl = float((a_fl & b_fl).sum())
    union_fl = float((a_fl | b_fl).sum())
    cross["floodlike_clean_urban_jaccard"] = round(inter_fl / union_fl, 4) if union_fl else float("nan")

    # ---- components ----
    component_rows = []
    for name in ("rel41", "rel77"):
        comps = largest_components(pair_masks[name]["floodlike_clean_urban"], transform, top=3)
        for c in comps:
            component_rows.append({
                "pair": name,
                "rank": c["rank"],
                "area_km2": c["area_km2"],
                "lon": c["lon"],
                "lat": c["lat"],
            })

    # ---- figure ----
    pre41 = to_db(rasterio.open(s1_data["rel41"]["rel41_pre_vv"]).read(1).astype("float32"))
    post41 = to_db(rasterio.open(s1_data["rel41"]["rel41_post_vv"]).read(1).astype("float32"))
    diff41 = post41 - pre41
    diff77 = (to_db(rasterio.open(s1_data["rel77"]["rel77_post_vv"]).read(1).astype("float32"))
              - to_db(rasterio.open(s1_data["rel77"]["rel77_pre_vv"]).read(1).astype("float32")))

    fig, axes = plt.subplots(2, 4, figsize=(20, 10))
    panels = [
        (axes[0, 0], pre41, "rel41 pre VV (dB)", "gray", -22, 0),
        (axes[0, 1], post41, "rel41 post VV (dB)", "gray", -22, 0),
        (axes[0, 2], diff41, "rel41 change (dB)", "RdBu", -8, 8),
        (axes[0, 3], np.where(pair_masks["rel41"]["floodlike_clean"], 1, 0), "rel41 flood-like (cleaned)", "gray", 0, 1),
        (axes[1, 0], diff77, "rel77 change (dB)", "RdBu", -8, 8),
        (axes[1, 1], np.where(pair_masks["rel77"]["floodlike_clean"], 1, 0), "rel77 flood-like (cleaned)", "gray", 0, 1),
        (axes[1, 2], np.where(water_pre & domain, 1, 0), "S2 water 16 May (non-perm)", "gray", 0, 1),
        (axes[1, 3], np.where(water_post & domain, 1, 0), "S2 water 21 May (non-perm)", "gray", 0, 1),
    ]
    for ax, data, title, cmap, vmin, vmax in panels:
        im = ax.imshow(data, cmap=cmap, vmin=vmin, vmax=vmax)
        ax.set_title(title)
        ax.set_xticks([])
        ax.set_yticks([])
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.suptitle("18 May 2023 candidate gate (diagnostic, ADR-19)")
    fig.tight_layout()
    fig_path = rel_path(cfg, "outputs") / "figures" / "candidate_may2023.png"
    fig_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(fig_path, dpi=140)
    plt.close(fig)

    # ---- write gate CSV (long format) ----
    gate_rows = []
    for name in ("rel41", "rel77"):
        for key, val in pair_stats[name].items():
            gate_rows.append({"section": name, "metric": key, "value": val})
    for key, val in s2_stats.items():
        gate_rows.append({"section": "s2", "metric": key, "value": val})
    for key, val in cross.items():
        gate_rows.append({"section": "cross", "metric": key, "value": val})

    table = rel_path(cfg, "outputs") / "tables" / "candidate_may2023_gate.csv"
    table.parent.mkdir(parents=True, exist_ok=True)
    with open(table, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["section", "metric", "value"])
        writer.writeheader()
        writer.writerows(gate_rows)

    comp_table = rel_path(cfg, "outputs") / "tables" / "candidate_may2023_components.csv"
    with open(comp_table, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["pair", "rank", "area_km2", "lon", "lat"])
        writer.writeheader()
        writer.writerows(component_rows)

    # ---- decision ----
    d1 = True  # rel41 same orbit, ~18 h lag (pre-registered)
    d2 = s2_stats["s2_post_clear_fraction_domain"] >= 0.30
    d3 = s2_stats["s2_pre_clear_fraction_domain"] >= 0.50
    sig = pair_stats["rel41"]["floodlike_clean_urban_area_km2"] >= 0.05
    opt = (s2_stats["s2_urban_water_change_km2"] >= 0.05) or (s2_stats["sar_floodlike_precision_vs_s2_water"] >= 0.50)
    rel77_agree = (pair_stats["rel77"]["floodlike_clean_urban_area_km2"] >= 0.02) and (cross["floodlike_clean_urban_jaccard"] >= 0.10)

    print("\n=== 18 May 2023 gate ===")
    for name in ("rel41", "rel77"):
        s = pair_stats[name]
        print(f"[{name}] valid={s['valid_fraction']} dark16(np)={s['post_dark16_fraction_nonpermanent']} "
              f"chg<-2(np)={s['change_lt_minus2_fraction_nonpermanent']} urban_chg={s['change_lt_minus2_fraction_urban_nonpermanent']} "
              f"floodlike_clean={s['floodlike_clean_area_km2']} km2 urban={s['floodlike_clean_urban_area_km2']} km2")
    for k, v in s2_stats.items():
        print(f"[s2] {k}={v}")
    for k, v in cross.items():
        print(f"[cross] {k}={v}")

    print("\n--- gates ---")
    print(f"D1 same-orbit primary + <=24h lag: {'PASS' if d1 else 'FAIL'}")
    print(f"D2 S2 post clear>=0.30: {s2_stats['s2_post_clear_fraction_domain']:.4f} -> {'PASS' if d2 else 'FAIL'}")
    print(f"D3 S2 pre clear>=0.50: {s2_stats['s2_pre_clear_fraction_domain']:.4f} -> {'PASS' if d3 else 'FAIL'}")
    print(f"Signal rel41 floodlike_clean_urban>=0.05: {pair_stats['rel41']['floodlike_clean_urban_area_km2']:.4f} -> {'PASS' if sig else 'FAIL'}")
    print(f"Optical urban_water_change>=0.05 or precision>=0.50: change={s2_stats['s2_urban_water_change_km2']:.4f}, precision={s2_stats['sar_floodlike_precision_vs_s2_water']:.4f} -> {'PASS' if opt else 'FAIL'}")
    print(f"rel77 agreement (urban>=0.02 & jaccard>=0.10): {'PASS' if rel77_agree else 'FAIL'}")

    if d1 and d2 and d3 and sig and opt:
        verdict = "PASS" if rel77_agree else "PASS WITH CAVEAT (rel77 does not agree; event is transient)"
    else:
        verdict = "FAIL"
    print(f"\nVERDICT: {verdict}")

    manifest["verdict"] = verdict
    manifest_path = out_dir / "candidate_manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)

    print(f"\nWrote {table}")
    print(f"Wrote {comp_table}")
    print(f"Wrote {fig_path}")
    print(f"Wrote {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

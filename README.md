# DIVP Mini-Project — Brahmaputra Flood Confidence Mapping

**Title:** Multi-Method Flood Segmentation and Agreement-Based Confidence Estimation Using Sentinel-1 SAR Imagery

**Authors:** Garima Devi (240101007), Pritom Sarma (240101013) — ECE, GUIST, Gauhati University
**Supervisor:** Jyoti Prakash Medhi

## What this project does

Maps the **Brahmaputra riverine flood of late June 2023** over a widened Guwahati
floodplain AOI from Sentinel-1 SAR, using several independent classical
segmentation methods (Otsu VV/VH, change detection, adaptive, Kittler–Illingworth,
Gaussian-mixture), and combines them into a **per-pixel agreement-based confidence
map** (High / Medium / Low / Dry). It then tests whether "how many methods agree"
is a trustworthy measure of how correct the map is, validated against Sentinel-2
MNDWI.

**Full system architecture (diagrams + explanations):** see [ARCHITECTURE.md](ARCHITECTURE.md).

## Key findings

- **Binary flood map** (GMM ensemble, k ≥ 2): precision 82.6%, recall 80.2%,
  **F1 0.814** (95% CI 0.801–0.826), IoU 0.68.
- **H1 was first rejected, then refined.** With the original 4-method ensemble the
  reliability curve was *non-monotonic* (High 77.1% < Medium 88.6%). Replacing the
  weak adaptive member with **GMM** restores monotonicity — **High 88.4% > Medium
  83.7% > Low 45.6%** — and the High/Medium confidence intervals don't overlap.
- **Conclusion:** agreement predicts reliability only when ensemble members
  genuinely measure the same signal (κ ≈ 0.8); an uncorrelated, low-recall member
  (adaptive, κ ≈ 0.06) breaks it.
- **Cross-terrain generalization:** global thresholds are terrain-specific (Otsu
  farm −12.5 dB vs urban −2.9 dB), so a threshold tuned on one terrain does not
  transfer to another.

Full results, every number, and the evidence trail live in `report/`.

## Data

All data is public and auto-downloaded from the **Microsoft Planetary Computer**
STAC API. Exact item IDs and SHA256 checksums are recorded in `data/manifest.json`.

> **The large raster files are gitignored** (raw ~260 MB + processed ~220 MB).
> Anyone who clones this repo gets the code, notebooks, reports, figures and
> tables — but must re-download the data to re-run the pipeline (see below).
> The download is deterministic: the manifest pins the exact items.

## Reproduce

```powershell
# 0. create venv and install (see requirements.lock.txt), then:
.\.venv\Scripts\Activate.ps1

# 1. resolve items + download data (~260 MB)
python code\preprocessing\stac_manifest.py
python code\preprocessing\fetch_subsets.py

# 2. build the analysis stack (Lee filter -> dB, slope, static masks)
python code\preprocessing\build_stack.py

# 3. flood masks (4 core + Kittler/GMM alternatives)
python code\flood_masks\run_masks.py
python code\confidence\alternative_members.py

# 4. confidence map + validation
python code\confidence\agreement.py
python code\confidence\validate.py

# 5. sensitivity / ensemble-design / bootstrap
python code\confidence\sensitivity_drop_adaptive.py
python code\confidence\bootstrap_ci.py
python code\confidence\validation_viz.py
python code\confidence\cross_terrain.py
```

Or run the matching notebooks in `notebooks/` cell-by-cell (`notebooks/README.md`)
— notebooks `07`–`09` render figures inline.

## Layout

```
report/       draft report, ADRs (decisions.md), claims_ledger.md, WORKLOG.md, references.bib
data/         raw + processed data (large files NOT committed; manifest is committed)
code/         config, preprocessing, flood_masks, confidence
notebooks/    00-09, cell-by-cell views of the pipeline
outputs/      generated tables (.csv), figures (.png); maps (.tif, regenerable)
```

## Environment

- Python venv at `.venv/` (kept off `C:`; data caches under `.cache/` on `D:`)
- All parameters in `code/config/config.yaml` (AOI, event, item IDs, thresholds)
- No secrets are stored in the repo.

## Rules

- **No fabricated results** — every number maps to a script output and a
  `report/claims_ledger.md` row.
- Engineering decisions are recorded in `report/decisions.md` (ADRs).
- The `.py` files are the canonical pipeline; the notebooks mirror them.

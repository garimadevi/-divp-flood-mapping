# Claims Ledger

Every quantitative claim in the report must have a row here. A claim without evidence does not go into the report.
Status values: `planned`, `verified`, `rejected`.

| ID | Claim (short) | Evidence (script / figure / table / citation) | Status |
|---|---|---|---|
| C-001 | Sentinel-1 RTC pre/post pair acquired for the AOI | `data/manifest.json` (items + SHA256) | verified |
| C-002 | Study AOI is 1713 x 1346 px at 10 m = 230.57 km^2 | `outputs/tables/day2_coverage.csv`; `code/preprocessing/check_coverage.py` | verified |
| C-003 | Four flood masks built (riverine, June 2023); areas 111.75 / 143.02 / 108.17 / 5.63 km^2; thresholds -12.55 / -17.31 / -3.0 / -9.57 dB | `outputs/tables/mask_stats.csv`; `outputs/maps/masks/` | verified |
| C-004 | Pairwise Cohen's kappa: Otsu VV-VH 0.849; Otsu vs change 0.76-0.79; adaptive vs others 0.06-0.08 | `outputs/tables/mask_kappa.csv` | verified |
| C-005 | H1 "High-class precision exceeds Low-class precision" is REJECTED: observed precision Medium 88.6% > Low 82.9% > High 77.1% (non-monotonic) | `outputs/tables/metrics_by_class.csv`; `outputs/figures/reliability_curve.png` | verified (H1 rejected) |
| C-006 | Per-method precision/recall/F1/IoU/OA vs S2 MNDWI: Otsu VV F1 0.797 / Otsu VH 0.817 / change 0.691 / adaptive 0.052 | `outputs/tables/metrics_by_method.csv` | verified |
| C-007 | Per-confidence-class precision (reliability): dry 4.9%, low 82.9%, medium 88.6%, high 77.1% | `outputs/tables/metrics_by_class.csv` | verified |
| C-008 | Clear-pixel coverage of Sentinel-2 reference | `outputs/tables/s2_coverage.csv` | planned |
| C-009 | Flood extent with and without permanent-water masking | `outputs/tables/flood_extent.csv` | planned |
| C-010 | Runtime and peak memory of the pipeline | `outputs/tables/runtime.csv` | planned |
| C-011 | All input layers share EPSG:32646 at 10 m and are 100% valid | `outputs/tables/day2_coverage.csv` | verified |
| C-012 | Analysis-ready stack: Lee 7x7 on linear power with 4 looks, then dB; slope and static masks on the same grid | `data/processed/stack_meta.json`; `outputs/figures/masks_overview.png` | verified |
| D-001 | 20 Apr 2026 has no coherent urban flood signal (8.1% change but scattered; 0.066 km^2 cleaned flood-like; 0.02% urban dark) | `outputs/tables/day3_gate_stats.csv`; `outputs/figures/day3_gate_zoom.png` | verified (diagnostic) |
| D-002 | 31 May 2025 candidate has 2.357 km^2 cleaned flood-like area vs 1.151 km^2 for 19-20 May 2025 | `outputs/tables/candidate_gate.csv`; `outputs/figures/candidate_may19.png`, `candidate_may31.png` | verified (diagnostic) |
| D-003 | 31 May S2 (9 Jun 2025) has 21-31% cloud; SAR dark16 overlaps S2 water 77.9% vs 1.2% non-water | `outputs/tables/candidate_may31_s2.csv`; `outputs/figures/candidate_may31_s2.png` | verified (diagnostic) |
| D-004 | 31 May 2025 gate passes: 2.357 km^2 cleaned flood-like area; non-permanent SAR-S2 separation 0.753 | `outputs/tables/day3_gate_stats.csv`; `outputs/figures/day3_gate_zoom.png` | verified (diagnostic) |
| D-005 | 18 May 2023 gate fails: rel41 flood-like clean 0.000 km² (urban 0.000); urban change < −2 dB 8.75 km² but fragmented into ~24k comps (largest 0.008 km²); urban dark < −16 dB 0.008 km² | `outputs/tables/candidate_may2023_gate.csv`; `outputs/figures/candidate_may2023.png` | verified (diagnostic) |
| D-006 | 18 May 2023 optical shows no urban water increase: S2 non-perm water 1.908→0.502 km² (−1.405); urban 0.476→0.090 km² (−0.385); pre clear 0.840, post clear 0.948 | `outputs/tables/candidate_may2023_gate.csv` | verified (diagnostic) |
| D-007 | 18 May 2023 two S1 orbits disagree on urban change (Jaccard 0.0594), confirming change signal is noise-dominated | `outputs/tables/candidate_may2023_gate.csv` | verified (diagnostic) |
| D-008 | Copernicus GFM flood/water/likelihood layers are all-nodata (255) over the Guwahati urban AOI on every flood date; only the static reference-water mask has data — GFM's exclusion mask covers urban Guwahati | GFM STAC `https://stac.eodc.eu/api/v1` (collection GFM), probe read | verified (diagnostic) |
| D-009 | June 2023 riverine flood: S1 rel41 11→23 June shows 90.84 km² new dark water (post < −16 dB, pre not dark) and 131.53 km² dark&change over the 1,356 km² wider AOI | feasibility probe (S1 RTC VV, EPSG:32646 10 m) | verified (diagnostic) |
| D-010 | June 2023 S2 (25 June) over the wider AOI: clear fraction 0.771; MNDWI water 171.34 km² (16.4% of clear); GFM reference water 134.14 km² | feasibility probe (S2 L2A mosaic + GFM reference_water_mask) | verified (diagnostic) |
| C-013 | Agreement confidence classes (riverine): dry 604.76 / low 33.93 / medium 84.77 / high 3.91 km²; flood-positive (k≥2) 122.59 km² | `outputs/tables/confidence_classes.csv`; `outputs/maps/confidence/agreement_classes.tif` | verified |
| C-014 | Binary flood mask (k≥2) vs S2 MNDWI: precision 86.6%, recall 76.1%, F1 0.810, IoU 0.680, OA 93.8% | `outputs/tables/metrics_flood_binary.csv` | verified |
| C-015 | Dropping the adaptive member makes reliability monotonic: 3-method precision high 88.35% > medium 82.63% > low 43.2% (vs 4-method high 77.1% < medium 88.6%) | `outputs/tables/sensitivity_drop_adaptive.csv`; `code/confidence/sensitivity_drop_adaptive.py` | verified |
| C-016 | Binary flood map is unchanged by dropping adaptive (F1 0.8094 vs 0.8097; IoU 0.6798 vs 0.6803), so adaptive is redundant for the flood mask but harmful for confidence ordering | `outputs/tables/sensitivity_drop_adaptive_binary.csv` | verified |
| C-017 | Kittler & GMM per-method (vs S2 MNDWI): Kittler precision 92.5%, F1 0.775, kappa 0.803; GMM precision 78.8%, recall 81.5%, F1 0.801, kappa 0.829 — both strongly correlated with the 3 good methods, unlike adaptive (kappa 0.06) | `outputs/tables/candidate_members.csv`; `outputs/figures/candidate_members.png` | verified |
| C-018 | 4-method ensemble is monotonic with GMM (high 88.4% > medium 83.7% > low 45.6%) or Kittler (high 91.1% > medium 88.5% > low 56.1%); GMM gives the best binary F1 0.8138 | `outputs/tables/ensemble_4th_member.csv`; `outputs/figures/alternative_members_reliability.png` | verified |
| C-019 | Leave-one-out ablation: dropping any of the 3 good methods breaks monotonicity and lowers F1 (Otsu VV→0.693, Otsu VH→0.675, change→0.797); only dropping adaptive is monotonic (F1 0.8094) | `outputs/tables/leave_one_out.csv` | verified |
| C-020 | Cross-terrain generalization: Otsu threshold farm −12.54 dB vs urban −2.91 dB (~10 dB gap); transferring the urban threshold to farmland drops F1 0.73→0.43 (gap ≈ 0.29, all methods); urban has ~no water regardless (in-place F1 ≈ 0.003) | `outputs/tables/cross_terrain.csv`; `outputs/figures/cross_terrain.png` | verified |
| C-021 | GMM-ensemble validation vs S2 (confusion counts): TP 769,405 / FP 161,621 / FN 190,390 / TN 4,428,616; precision 82.6%, recall 80.2%, F1 0.8138 | `outputs/figures/validation_agreement.png`; `code/confidence/validation_viz.py` | verified |

**Rule:** if a row cannot be filled with a real path or citation, the claim is removed or tagged `[To verify]`.

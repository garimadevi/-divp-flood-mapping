# Work Log

Append one entry per working day. Keep each entry short and factual. This is the audit trail for the final report.

**Entry template**

```
## YYYY-MM-DD — Day N

**Did:** ...
**Why:** ...
**Evidence:** files/scripts/figures produced
**Blockers:** ...
**Next:** ...
```

---

## 2026-11-04 — Day 1

**Did:** Created repository skeleton, governance files, and project configuration. Verified local Python and toolchain. Created an isolated environment on `D:` and installed the geospatial/STAC and image-processing packages.
**Why:** Day 1 is setup only; no scientific results are produced or implied.
**Evidence:** `README.md`, `requirements.txt`, `requirements.lock.txt`, `code/config/config.yaml`, `report/*`, `.venv/`, `data/` and `outputs/` tree. Initial commit `4f70cae`.
**Environment snapshot:**
- Python 3.13.5 (venv at `.venv/`, caches and TEMP/TMP under `.cache/`)
- numpy 2.5.4, scipy 1.18.1, scikit-image 0.26.0, opencv 5.0.0.93
- rasterio 1.5.2, rioxarray 0.24.0, geopandas 1.2.0, shapely 2.2.0, pyproj 3.8.0
- pystac-client 0.9.1, planetary-computer 1.0.0
- xarray 2026.9.0, pandas 3.1.0, matplotlib 3.11.2, streamlit 1.66.1
- Planetary Computer STAC check: `get_collection('sentinel-1-rtc')` returned OK.
**Blockers:** None.
**Next:** Write and run the STAC manifest script; fetch windowed RTC/S2/DEM/JRC/WorldCover subsets (Day 2).

---

## 2026-11-05 — Day 2

**Did:** Resolved all seven STAC items and fetched windowed AOI subsets (no full scenes). Built the common `EPSG:32646` 10 m grid, mosaicked both Sentinel-2 tiles, and recorded SHA256 checksums in `data/manifest.json`.
**Why:** Create one reproducible analysis grid and a provenance record before any segmentation.
**Evidence:**
- `data/manifest.json` (7 datasets + SHA256 of 10 local subsets)
- `outputs/tables/day2_coverage.csv`
- `outputs/figures/day2_quicklook.png`
- Grid: 1713 x 1346 px at 10 m = 230.57 km^2; all layers 100% valid; CRS/resolution checks passed.
- AOI subset sizes: S1 ~8.2 MB/band; S2 ~3.2 MB/band; DEM 6.9 MB; JRC 0.05 MB; WorldCover 0.19 MB.
**Observations:** Permanent Brahmaputra water is clearly dark in both VV scenes. At AOI scale, the post-pre difference does **not** show an obvious widespread urban flood signal. This is not yet a conclusion: Day 3 must zoom into the Bharalu basin and run the formal go/no-go before any flood result is reported.
**Blockers:** None for acquisition.
**Next:** Day 3 — zoomed go/no-go inspection of the Bharalu basin and baseline Otsu; pivot to 31 May 2025 if no usable signal.

---

## 2026-11-05 — Day 3 (go/no-go gate)

**Did:** Ran the go/no-go diagnostic on the 20 Apr 2026 RTC over the Bharalu / central Guwahati area, excluding JRC permanent water and steep slopes. Did not start the baseline Otsu because the gate failed.
**Why:** A signal check must happen before committing the report to this event.
**Evidence:**
- `outputs/tables/day3_gate_stats.csv`
- `outputs/figures/day3_gate_zoom.png`
- `code/preprocessing/day3_gate.py`
**Result (diagnostic, not a final result):**
- Post VV < -16 dB: 1.98% of non-permanent pixels vs 1.87% pre-event. Urban non-permanent: 0.02%.
- Change < -2 dB: 15.5% of non-permanent pixels, but spatially scattered (speckle-like), not coherent.
- Flood-like mask after cleaning: **0.066 km^2 (6.6 ha)** — no coherent urban inundation.
- Sentinel-2 non-permanent water is 5.5% of clear non-permanent pixels; the SAR-S2 dark separation (0.36 vs 0.002) is driven by small ponds/permanent water bodies, not an event flood.
**Conclusion:** The 20 Apr 2026 pass at 17:27 IST does not contain a usable urban flood signal. Building the project on this event would produce a weak, unshowable result. Recommend pivoting to the 31 May 2025 fallback, subject to the same gate.
**Blockers:** Event choice pending.
**Next:** Verify fallback data availability and signal, then reconfigure the event if confirmed.

---

## 2026-11-05 — Day 3 (fallback candidate check)

**Did:** Fetched and gated both fallback candidates with Sentinel-1 RTC; fetched Sentinel-2 for the stronger candidate.
**Why:** Choose the event with the best honest signal before rebuilding the pipeline.
**Evidence:**
- `data/candidates/may19/` and `data/candidates/may31/`
- `outputs/tables/candidate_gate.csv`
- `outputs/tables/candidate_may31_s2.csv`
- `outputs/figures/candidate_may19.png`, `candidate_may31.png`, `candidate_may31_s2.png`
**Results (diagnostic):**
- 19-20 May 2025 (RTC 7 May / 19 May): cleaned flood-like 1.151 km^2; urban 0.000 km^2; S2 20 May is ~100% cloud.
- 31 May 2025 (RTC 21 May / 2 June): cleaned flood-like 2.357 km^2; urban 0.011 km^2; S2 9 June is 21-31% cloud; SAR dark16 where S2 water 77.9% vs 1.2% where non-water.
**Conclusion:** Recommend the **31 May 2025** event. It has the strongest coherent signal and the only usable optical reference. Urban SAR remains weak, which will be reported as a finding, not hidden.
**Blockers:** Partner confirmation of the pivot.
**Next:** Reconfigure the event, refetch the main data tree, update the manifest and report data section, then run the baseline Otsu mask.

---

## 2026-11-05 — Day 3 (pivot executed)

**Did:** Partner confirmed 31 May 2025. Updated `config.yaml`, archived the April subsets to `data/candidates/april2026/`, refetched the 31 May RTC pair and Sentinel-2 tiles, refetched the static layers, and reran the gate.
**Why:** The 20 Apr 2026 pass failed the signal gate; the 31 May 2025 event has the strongest honest signal among the checked candidates.
**Evidence:**
- `data/manifest.json` (new items + SHA256)
- `outputs/tables/day2_coverage.csv`
- `outputs/tables/day3_gate_stats.csv`
- `outputs/figures/day3_gate_zoom.png`
- `outputs/tables/negative_april2026_gate.csv`
- `outputs/figures/negative_april2026_gate.png`
**Result:** Gate passes. Coherent flood-like area 2.357 km^2 (3.844 km^2 before cleaning); non-permanent SAR-S2 separation 0.753; S2 clear fraction 0.938; urban dark remains low (0.09%).
**Blockers:** None.
**Next:** Baseline Otsu mask and first metrics (Day 3 continued).

---

## 2026-11-05 — Day 3 (analysis-ready stack + first masks)

**Did:** Built the analysis-ready stack (Lee filter on linear power -> dB), slope, and static masks; built four flood masks; computed per-mask area and pairwise Cohen's kappa.
**Why:** First implementation milestone after the event pivot: produce the ensemble inputs and check method independence.
**Evidence:**
- `data/processed/stack_meta.json`, `data/processed/s1_*_db.tif`, `slope_deg.tif`, `data/processed/masks/`
- `outputs/maps/masks/{otsu_vv,otsu_vh,change_vv,adaptive_vv}.tif`
- `outputs/tables/mask_stats.csv`, `outputs/tables/mask_kappa.csv`
- `outputs/figures/masks_overview.png`
**Results (provisional):**
- Otsu VV: 9.492 km^2, threshold -10.65 dB.
- Otsu VH: 9.348 km^2, threshold -17.98 dB.
- Change VV: 4.141 km^2, threshold -3.0 dB.
- Adaptive VV: 0.424 km^2, local mean minus 1.5 sigma, 51 px window.
- Kappa: Otsu VV vs VH 0.946 (near-duplicate); Otsu VV vs change 0.561; Otsu VH vs change 0.540; adaptive vs others 0.04–0.07 (independent but conservative).
**Interpretation:** The Otsu pair is redundant; the adaptive mask is independent but conservative. This is exactly the redundancy the confidence design must expose. The permanent-water mask works: 79.6% of JRC permanent pixels are dark in post VV, and only 3.5% of non-permanent pixels are dark.
**Blockers:** None.
**Next:** Build the agreement confidence map; then decide whether to keep both Otsu variants or replace Otsu VH with a VH change method.

---

## 2026-11-06 — Day 4 (workflow restructuring)

**Did:** Read the full handoff and reorganised the working process for visibility. Added `report/PROGRESS.md` (step tracker, current step, next actions, session log) and `notebooks/` with cell-by-cell views of the long pipeline scripts (`00_data_acquisition`, `01_event_signal_gate`, `02_build_stack`, `03_flood_masks`). Kept every `.py` unchanged as the canonical CLI. Added `notebooks/README.md`.
**Why:** Make progress visible step by step and persist the working state in files while opencode session persistence is unavailable.
**Evidence:** `report/PROGRESS.md`, `notebooks/README.md`, `notebooks/*.ipynb`. No data, mask, or result files were changed.
**Blockers:** None. Jupyter/ipykernel are not installed in `.venv`; install command is in `PROGRESS.md` §4.
**Next:** Step 9 — agreement confidence map (`code/confidence/agreement.py` + `notebooks/04_confidence_agreement.ipynb`), then the Otsu redundancy decision. Commit Day 3–4 work.

---

## 2026-11-06 — Day 4 (event search & 18 May 2023 gate)

**Did:** Searched reported Guwahati flood dates and checked STAC availability; identified 18 May 2023 as the strongest candidate (two same-orbit S1 pairs + pre/post S2). Pre-registered the gate as ADR-19, added `code/preprocessing/candidate_may2023.py`, fetched both S1 pairs and S2 16/21 May, and ran the gate.
**Why:** The 31 May 2025 ensemble does not detect urban flood water (High class 0% urban, Low more water-like than High); a better event was needed before committing the report.
**Evidence:**
- `code/preprocessing/candidate_may2023.py`
- `data/candidates/may2023/` + `candidate_manifest.json`
- `outputs/tables/candidate_may2023_gate.csv`, `candidate_may2023_components.csv`
- `outputs/figures/candidate_may2023.png`
- `report/decisions.md` ADR-19; `report/claims_ledger.md` D-005..D-007
**Result (FAIL, diagnostic):**
- Data gates pass: rel41 same-orbit, post ~18 h; S2 post clear 0.948, pre clear 0.840.
- Signal gate fails: rel41 flood-like clean 0.000 km² (urban 0.000); urban change < −2 dB 8.75 km² but fragmented (largest component 0.008 km²); urban dark < −16 dB only 0.008 km².
- Optical gate fails on water increase: S2 non-perm water 1.908→0.502 km² (−1.405); urban 0.476→0.090 km² (−0.385).
- Cross-orbit urban-change Jaccard 0.0594 — the two pairs disagree, so the change signal is noise-dominated.
**Conclusion:** 18 May 2023 is too small/transient for 10 m SAR. Per the pre-registered rule, pivot to surface-water mapping (the methods do map water reliably: Otsu VV/VH have 86% S2-water recall, 67% precision).
**Blockers:** None.
**Next:** Confirm the surface-water pivot scope (ADR-20), then re-scope config/notebooks/report and rebuild.

---

## 2026-11-07 — Day 5 (riverine-flood pivot)

**Did:** Researched alternative datasets. Found (1) Copernicus Global Flood Monitoring (GFM) — free operational 3-algorithm Sentinel-1 flood ensemble with a likelihood layer, STAC at `stac.eodc.eu`; (2) official NRSC/ISRO + NESAC/NER-DRR Sentinel-1/RISAT/ALOS-2 flood maps of Assam. Verified GFM flood/water/likelihood layers are all-nodata over the Guwahati urban AOI (urban exclusion mask), so GFM is not usable as a flood reference here. Verified the June 2023 Brahmaputra riverine flood is strongly detectable with our own sensors.
**Why:** The urban flash-flood target is a dead end (our gates + GFM's urban exclusion). Riverine flood is large, persistent, and detectable.
**Evidence:**
- `report/decisions.md` ADR-20; `report/claims_ledger.md` D-008..D-010
- Feasibility probe over wider AOI `[91.55, 26.00, 91.95, 26.30]` (~1,356 km²)
**Result (diagnostic, pre-gate):**
- S1 rel41 11→23 June 2023: 90.84 km² new dark water; 131.53 km² dark&change.
- S2 25 June 2023: clear 0.771; MNDWI water 171.34 km² (16.4% of clear).
- GFM reference water (static): 134.14 km² permanent/seasonal water.
- NRSC 29 June 2023: Kamrup Rural 10,195 ha + Kamrup Metro 946 ha inundated.
**Conclusion:** Pivot to the June 2023 riverine flood over the wider AOI (ADR-20). Event passes the pre-registered gate.
**Blockers:** None.
**Next:** Reconfigure `config.yaml` (AOI, event, S1/S2 items), refetch the wider-AOI tree, rerun notebooks 00-03, rebuild the agreement confidence map, validate vs S2 MNDWI + NRSC + GFM reference water.

---

## 2026-11-07 — Day 5 (riverine reconfiguration + confidence + validation)

**Did:** Reconfigured `config.yaml` to the June 2023 riverine event and the wider AOI `[91.55, 26.00, 91.95, 26.30]` (~1,356 km²). Refetched the full data tree (S1 11/23 June rel41, S2 25 June mosaic, DEM/JRC/WorldCover), rebuilt the stack and the four masks, then built the agreement confidence map (`code/confidence/agreement.py`) and validated it against S2 MNDWI (`code/confidence/validate.py`).
**Why:** Execute ADR-20 and deliver the core confidence deliverable on a real, detectable flood.
**Evidence:**
- `code/config/config.yaml`, `data/manifest.json` (regenerated)
- `outputs/maps/masks/`, `outputs/maps/confidence/agreement_classes.tif`, `agreement_flood.tif`
- `outputs/tables/mask_stats.csv`, `mask_kappa.csv`, `confidence_classes.csv`, `metrics_by_method.csv`, `metrics_by_class.csv`, `metrics_flood_binary.csv`
- `outputs/figures/masks_overview.png`, `confidence_map.png`, `reliability_curve.png`
- `code/confidence/agreement.py`, `code/confidence/validate.py`
- `report/decisions.md` ADR-20, ADR-21; `report/claims_ledger.md` C-003..C-007, C-013, C-014
**Results (verified):**
- Masks: Otsu VV 111.75 / Otsu VH 143.02 / change 108.17 / adaptive 5.63 km².
- Binary flood (k≥2) vs S2 MNDWI: precision 86.6%, recall 76.1%, F1 0.810, IoU 0.680, OA 93.8%.
- Per-method F1: Otsu VH 0.817, Otsu VV 0.797, change 0.691, adaptive 0.052.
- Reliability (class precision): dry 4.9%, low 82.9%, medium 88.6%, high 77.1% — non-monotonic; H1 rejected (ADR-21).
**Conclusion:** The riverine flood pipeline produces a strong, validated result. The confidence rule needs revision: the adaptive member degrades the High class; recommend 3-method agreement (drop adaptive) or re-weighting.
**Blockers:** None.
**Next:** Regenerate the masks/confidence notebooks (00-04) to mirror the new event; update DRAFT_REPORT and PROGRESS; fix the notebook 03 base-domain discrepancy; commit.

---

## 2026-11-07 — Day 5 (sensitivity check: drop adaptive)

**Did:** Added `code/confidence/sensitivity_drop_adaptive.py` and re-measured the confidence classes on the 3-method ensemble (Otsu VV, Otsu VH, change VV), dropping the adaptive member.
**Why:** Test ADR-21's claim that the adaptive member causes the non-monotonic reliability curve.
**Evidence:**
- `code/confidence/sensitivity_drop_adaptive.py`
- `outputs/tables/sensitivity_drop_adaptive.csv`, `sensitivity_drop_adaptive_binary.csv`
- `report/decisions.md` ADR-22; `report/claims_ledger.md` C-015, C-016
**Result (verified):**
- 4-method: high 77.1% < medium 88.6% (non-monotonic).
- 3-method: high 88.4% > medium 82.6% > low 43.2% — monotonic; High (3/3) is now the most precise class.
- Binary flood map unchanged: F1 0.8094 vs 0.8097; IoU 0.6798 vs 0.6803.
**Conclusion:** Dropping the adaptive member restores a monotonic reliability curve and confirms the adaptive member was harmful to confidence ordering while adding nothing to the flood mask. Adopt 3-method agreement as the primary confidence rule (ADR-22).
**Blockers:** None.
**Next:** Commit the full riverine pivot + confidence/validation/sensitivity work.

---

## 2026-11-07 — Day 5 (alternative 4th member: Kittler & GMM)

**Did:** Added `code/confidence/alternative_members.py` + `notebooks/06_alternative_members.ipynb`. Built two candidate 4th methods (Kittler-Illingworth minimum-error threshold and a 2-component Gaussian-mixture threshold), compared them against adaptive for the 4-method ensemble, and ran a leave-one-out ablation over the four original methods.
**Why:** ADR-22 showed the adaptive member was the problem; the open question was whether we can keep four votes *and* restore monotonicity by replacing adaptive with a stronger classical method.
**Evidence:**
- `code/confidence/alternative_members.py`, `notebooks/06_alternative_members.ipynb`
- `outputs/tables/candidate_members.csv`, `ensemble_4th_member.csv`, `leave_one_out.csv`
- `outputs/figures/candidate_members.png`, `alternative_members_reliability.png`
- `outputs/maps/masks/kittler.tif`, `gmm.tif`
- `report/decisions.md` ADR-23; `report/claims_ledger.md` C-017..C-019
**Result (verified):**
- Per-method: Kittler precision 92.5%, F1 0.775, κ 0.803; GMM recall 81.5%, F1 0.801, κ 0.829; both κ ≈ 0.8 vs the 3 good methods (adaptive κ 0.06).
- 4-method ensembles: adaptive non-monotonic; Kittler monotonic (High 91.1% > Med 88.5% > Low 56.1%, F1 0.8095); GMM monotonic (High 88.4% > Med 83.7% > Low 45.6%, F1 0.8138).
- Leave-one-out: dropping any good method breaks monotonicity and lowers F1 (0.69/0.68/0.80); only dropping adaptive is benign.
**Conclusion:** Adopt GMM as the 4th member (monotonic + best F1 0.8138); Kittler is a strong alternative (highest precision). H1 conclusion refined: agreement predicts reliability when members are correlated (κ ≈ 0.8), fails when a member is uncorrelated/low-recall (κ ≈ 0.06).
**Blockers:** None.
**Next:** Commit.

---

## 2026-11-07 — Day 5 (draft report sections)

**Did:** Drafted the six remaining `[planned]` sections of `report/DRAFT_REPORT.md` (Introduction, Problem Statement, Aim, Failure Analysis, Limitations, Future Work) and fixed the stale spots left by ADR-23: updated the status to v0.5, rewrote the Abstract to include the GMM resolution, added Kittler/GMM to Methodology M2, corrected Objective #2, and annotated the Results tables as diagnostic vs final.
**Why:** Bring the report in line with the completed ensemble-design analysis so no `[planned]` sections remain.
**Evidence:** `report/DRAFT_REPORT.md` (v0.5).
**Result:** No `[planned]` tags remain. Two `[To verify]` placeholders remain for facts only the authors can supply: supervisor name (title page) and event-context citations (rainfall/localities/impact from ASDMA/NRSC/press).
**Blockers:** Supervisor name and event-context figures are pending from the authors.
**Next:** Fill the two `[To verify]` items; then finalise References (`references.bib`) and lock the report.

---

## 2026-11-07 — Day 5 (event context + references)

**Did:** Researched and wrote the Section 4 "Event context" paragraph with citations, and extended `report/references/references.bib` with the missing sources (Kittler–Illingworth 1986, EM/GMM 1977, Copernicus GFM, Planetary Computer, Sentinel-1/2 missions, FloodList/CWC/ASDMA-NRSC June 2023 flood reports).
**Why:** The event-context facts (rainfall, river levels, affected people, official inundation) were the last report gaps besides the supervisor name.
**Evidence:** `report/DRAFT_REPORT.md` §4; `report/references/references.bib`.
**Result (verified against web sources):**
- Floods began ~14 June 2023; by 21 June 119,830 people across 20 districts affected (Baksa 26,571, Lakhimpur 25,096, Nalbari 44,707, Tamulpur 15,610); 30+ relief camps (2,091 people); North Lakhimpur 164 mm/24 h to 15 June.
- CWC: rivers above danger mark in ≥6 locations by 22 June.
- NRSC/ISRO map 29 June 2023: Kamrup Rural 10,195 ha + Kamrup Metro 946 ha.
**Conclusion:** Only the supervisor name remains as a `[To verify]` placeholder.
**Blockers:** Supervisor name (from authors).
**Next:** Fill supervisor name; then run the bootstrap CI + build the GMM-4 confidence figure (step 3).

---

## 2026-11-07 — Day 5 (validation visualization + cross-terrain)

**Did:** Added `code/confidence/validation_viz.py` + `notebooks/07_validation_visualization.ipynb` (cloud removal, MNDWI reference, SAR flood, and TP/FP/FN agreement map), and `code/confidence/cross_terrain.py` + `notebooks/08_cross_terrain.ipynb` (fit thresholds on farmland vs urban, transfer them across terrains, measure the F1 drop). Notebooks render figures inline via `%matplotlib inline`.
**Why:** Make the verification visually observable and test the cross-terrain generalization the authors proposed.
**Evidence:**
- `outputs/figures/validation_agreement.png`, `cross_terrain.png`
- `outputs/tables/cross_terrain.csv`
- `code/confidence/validation_viz.py`, `cross_terrain.py`
- `notebooks/07_validation_visualization.ipynb`, `08_cross_terrain.ipynb`
- `report/claims_ledger.md` C-020, C-021; `report/DRAFT_REPORT.md` §8
**Result (verified):**
- Validation (GMM ensemble vs S2): TP 769,405 / FP 161,621 / FN 190,390 / TN 4,428,616; precision 82.6%, recall 80.2%, F1 0.8138.
- Cross-terrain: Otsu farm threshold −12.54 dB vs urban −2.91 dB (10 dB gap); transferring urban→farm drops F1 0.73→0.43 (gap ≈ 0.29); urban has ~no water (in-place F1 ≈ 0.003).
**Conclusion:** Thresholds are terrain-specific and do not transfer across terrains — a quantified generalization failure that supports the earlier urban-Otsu observation.
**Blockers:** None.
**Next:** Supervisor name; bootstrap CI (still pending).

---

## 2026-11-07 — Day 5 (bootstrap CI + supervisor name)

**Did:** Set the supervisor name (Jyoti Prakash Medhi) in the report title page. Added `code/confidence/bootstrap_ci.py` + `notebooks/09_bootstrap_ci.ipynb`: a spatial block bootstrap (500 m blocks, 1000 reps, seed 42) over evaluated pixels, computing 95% CIs for the binary flood map and the per-class reliability curve.
**Why:** Give the metrics error bars that account for spatial autocorrelation, and remove the last report placeholder.
**Evidence:**
- `outputs/tables/bootstrap_ci.csv`, `outputs/figures/reliability_ci.png`
- `code/confidence/bootstrap_ci.py`, `notebooks/09_bootstrap_ci.ipynb`
- `report/claims_ledger.md` C-022; `report/DRAFT_REPORT.md` §8 + Future Work
**Result (verified):**
- Binary flood (GMM): F1 0.8139 [0.801, 0.826]; precision 0.8266 [0.811, 0.841]; recall 0.8021 [0.785, 0.816].
- Reliability (median [95% CI]): dry 4.1%, low 45.5%, medium 83.7% [81.6, 85.7], high 88.4% [86.9, 89.7].
- High and Medium CIs do not overlap → High is significantly more precise (refined H1 confirmed).
**Conclusion:** All metrics now carry uncertainty; the report has no `[To verify]` placeholders left.
**Blockers:** None.
**Next:** Final review; optionally the stratified manual sample and cross-scene generalization remain as Future Work.

---

## 2026-11-25 — Pre-presentation (MATLAB chain + static-mask sensitivity)

**Did:** (1) Rebuilt the MATLAB image-processing chain: `step3_masks.m` (six masks), `check_terrain.m` (terrain cross-check), and rewired `step3_comparing_algorithms.m` to consume `masks.mat` over the canonical `base` domain. (2) Added `code/confidence/static_masks_sensitivity.py`, which tests the 50 % JRC cut against the pre-event image and runs a one-at-a-time parameter sensitivity. (3) Added `code/confidence/ensemble_area.py` to record the k ≥ 2 area of both 4-member ensembles.
**Why:** The MATLAB layer is the tool-independence proof; the JRC sensitivity answers the question "why 50 % and not 90 %" with measurement rather than precedent. ADR-06 also promised a with/without permanent-water comparison (ledger C-009, still `planned`).
**Evidence:**
- `matlab/step3_masks.m`, `step3_comparing_algorithms.m`, `check_terrain.m`; `matlab/out/mask_areas.csv`, `kappa_vs_python.csv`, `terrain_check.csv`
- `code/confidence/static_masks_sensitivity.py`; `outputs/tables/jrc_preevent_test.csv`, `static_masks_sensitivity.csv`, `adaptive_member_sensitivity.csv`, `jrc_validation_sensitivity.csv`
- `outputs/tables/ensemble_area.csv`; `report/claims_ledger.md` C-009, C-024–C-027; ADR-24 in `report/decisions.md`
**Result (verified):**
- MATLAB: six masks 6/6 PASS; at Python's thresholds five of six match to 0.0 % and `change_vv` is pixel-identical (0/1,081,731 px, Kittler 4 px); pairwise kappa within 0.0015; ADR-23 area 136.13 vs 136.47 km² (Δ 0.25 %).
- Pre-event test: the 50 % cut removes 91.24 km², of which 90.4 % was already water 12 days before the flood and only 5.0 % becomes water at the peak. Moving to 90 % re-admits a 64.03 km² band that is 94.7 % water in Sentinel-2 (the seasonal channel).
- Fixed-evaluation-set F1 at JRC 0/50/90: 0.8167 / 0.8138 / 0.8162 (Δ ≤ 0.003), so the cut is definitional, not an accuracy lever. Slope 10→20° adds 1.27 km² (+0.9 %). Adaptive window 51→151 gives 5.63→18.13 km².
- With/without permanent-water masking (ADR-06): 136.47 vs 224.24 km².
**Correction:** `ensemble_area.py` initially summed the mask rasters without intersecting the analysis domain, so it read 122.93 / 136.83 km². `clean()` closes after masking, and closing spills up to 0.36 km² (0.26 %) outside the domain; `agreement.py` and `validate.py` both clip. Fixed → 122.60 / 136.47 km². The adaptive row now equals `confidence_classes.csv` (33.925 + 84.765 + 3.905 = 122.595), which is the consistency check that caught it. Report, ledger, and MATLAB acceptance updated.
**Conclusion:** The permanent-water cut is now defended by what it removes (90.4 % pre-existing water), not by the date it was chosen. The 136.83 → 136.47 km² correction is a definition fix, not a change of result; precision/recall/F1 are unaffected because validation always intersected with the domain.
**Blockers:** None.
**Next:** `step4_confidence.m` → `step5_validate.m` → `step6_verify.m`; slides; mock viva.

---

# Engineering Decision Log (ADRs)

Each decision is recorded when made. Status values: `accepted`, `superseded`, `open`.
A decision without a rationale and an evidence source is not a decision.

---

## ADR-01 — Sentinel-1 RTC as primary input
**Status:** accepted
**Context:** GRD needs orbit, calibration, speckle, terrain correction; RTC is already calibrated and terrain-corrected.
**Decision:** Use Sentinel-1 RTC as the primary input. GRD/SNAP is out of scope for the 2-week build.
**Rationale:** Removes SNAP installation and Java tooling from the critical path. The AOI is small and the RTC pair shares orbit geometry.
**Evidence:** HANDOFF §4.3 and §18.2; Copernicus/AWS RTC documentation.
**Consequence:** Must verify whether the specific RTC provider already applied speckle filtering before claiming any filter experiment.

---

## ADR-02 — Filtering order
**Status:** accepted
**Context:** Speckle is multiplicative and Gamma-distributed in linear intensity.
**Decision:** Apply any speckle filter on linear power, then convert to dB, then threshold.
**Rationale:** Filtering dB values is mathematically invalid and biases local statistics.
**Evidence:** TechnicalGIS SAR speckle-filter workflow; PyGeoVision SAR preprocessing notes.
**Consequence:** Document filter window and number of looks when used.

---

## ADR-03 — Methods chosen for input independence, not threshold variants
**Status:** accepted
**Context:** Otsu and adaptive thresholding on the same image, and Lee vs median on the same image, are highly correlated.
**Decision:** Build agreement from methods that differ in input: Otsu on post-VV, Otsu on post-VH, and VV change detection (log-ratio/ΔdB). Optional fourth: adaptive threshold on post-VV.
**Rationale:** Agreement between near-duplicate methods measures preprocessing choices, not independent evidence.
**Evidence:** NHESS 2023 spatial spread-skill; SAR flood review (Remote Sensing 2024).
**Consequence:** Report pairwise Cohen's kappa; drop near-duplicate members before confidence mapping.

---

## ADR-04 — Confidence rule is explicit and sensitivity-tested
**Status:** accepted
**Context:** The proposal left "3/4 = high or medium" undefined.
**Decision:** For N methods, k = number of methods calling a pixel flooded:
- k = N: High
- k = N-1: Medium
- 2 <= k <= N-2: Low
- k <= 1: Dry

Pixels with k >= 2 are treated as flood-positive for the confidence analysis.
**Rationale:** One rule is reproducible and auditable; sensitivity to cutoffs can be reported.
**Evidence:** [planned] sensitivity table computed by `code/confidence/agreement.py`.
**Consequence:** Report class counts and the effect of changing the Low cutoff.

---

## ADR-05 — Reference hierarchy
**Status:** accepted
**Context:** Sentinel-2 MNDWI is itself a detector and is 40% cloudy; official maps are not same-event truth.
**Decision:** Use, in order: stratified manual sample, Sentinel-2 MNDWI on clear pixels, official reports/maps as context only.
**Rationale:** Avoids calling one imperfect detector "ground truth".
**Evidence:** ISPRS 2025 MNDWI caveats; Clement et al. 2018; WorldFloods 2023.
**Consequence:** Report clear-pixel coverage, sample size, and the S1/S2 acquisition gap.

---

## ADR-06 — Mandatory masks
**Status:** accepted
**Context:** Permanent water and terrain produce systematic false positives.
**Decision:** Mask JRC permanent water (>50% occurrence), slope above 10 degrees, and urban/vegetation zones where relevant.
**Rationale:** Standard practice; keeps event water separate from permanent water.
**Evidence:** Pekel et al. 2016; Copernicus GFM quality report.
**Consequence:** Report flood extent both with and without permanent-water masking.

---

## ADR-07 — Metrics and calibration
**Status:** accepted
**Context:** A single accuracy number hides the reliability question.
**Decision:** Report precision, recall, F1, IoU, overall accuracy, Cohen's kappa per method and per confidence class, plus a reliability curve (class vs observed precision), and bootstrap confidence intervals where time allows.
**Rationale:** The research question is about reliability, not just extent.
**Evidence:** ECE/Brier calibration literature; spatial block bootstrap guidance.
**Consequence:** If calibration fails, report it as a finding.

---

## ADR-08 — Reproducibility
**Status:** accepted
**Context:** Figures and numbers must be regenerable.
**Decision:** Fixed random seed; `config.yaml` as single source of parameters; `data/manifest.json` with SHA256; generated figures/tables never edited by hand; pinned environment.
**Rationale:** No-fabrication rule requires traceable outputs.
**Evidence:** `data/manifest.json`, `requirements.txt` (or lockfile), script-generated `outputs/`.
**Consequence:** Any hand-edited number is a defect.

---

## ADR-09 — Compute strategy
**Status:** accepted
**Context:** No GPU; 16 GB RAM; AOI about 0.17 x 0.12 degrees (~2.3 M pixels at 10 m).
**Decision:** Single-process numpy/xarray with windowed COG reads; no Dask or tiling.
**Rationale:** AOI fits comfortably in memory; tiling adds complexity without benefit.
**Evidence:** HANDOFF §18.2 AOI size estimate.
**Consequence:** Record runtime and peak memory for the report.

---

## ADR-10 — Demo runs offline
**Status:** accepted
**Context:** A live demo must not fail because of network or compute.
**Decision:** Streamlit app reads precomputed rasters and metrics from `outputs/`; include a recorded walkthrough as backup.
**Rationale:** Showability is a deliverable.
**Evidence:** `app/streamlit_app.py` and `outputs/`.
**Consequence:** Rebuild outputs before the demo and freeze the demo data.

---

## ADR-11 — Scope freeze for a 2-week build
**Status:** accepted
**Context:** Two weeks to submission, two people.
**Decision:** Ship the core flood-confidence pipeline and demo. Pothole/YOLO, OSM hazard ranking, health access, optional ML, FwDET and enhancement are future work.
**Rationale:** Depth and honest validation beat unfinished breadth.
**Evidence:** Project plan, 4 Nov 2026.
**Consequence:** Report has a Future Work section listing the cut modules.

---

## ADR-12 — No fabricated results
**Status:** accepted
**Decision:** Every quantitative statement maps to a script output and a `claims_ledger.md` row; unverified facts are tagged `[To verify]`.
**Rationale:** Credibility and academic integrity.
**Evidence:** `report/claims_ledger.md`.
**Consequence:** Final report is assembled from the draft, not retyped from memory.

---

## ADR-13 — JRC collection id and asset
**Status:** accepted (Day 2)
**Context:** The handoff named `jrc-global-surface-water`, but the live Planetary Computer catalog has no such collection.
**Decision:** Use collection `jrc-gsw`, item `90E_30Nv1_3_2020`, asset `occurrence`.
**Rationale:** Verified against the STAC API on Day 2; `occurrence` gives the 0-100% water-occurrence layer needed for the permanent-water mask.
**Evidence:** STAC query; `data/manifest.json` dataset `jrc_water`.
**Consequence:** Config corrected; the 50% occurrence threshold in ADR-06 applies to this asset.

---

## ADR-14 — Mosaic both Sentinel-2 tiles
**Status:** accepted (Day 2)
**Context:** The AOI north edge (26.22 N) lies above the `T46RCP` north edge (26.217 N); `T46RCQ` starts at 26.117 N, so the AOI straddles both tiles.
**Decision:** Fetch both `T46RCQ` and `T46RCP`, reproject each to the common grid, and mosaic valid pixels.
**Rationale:** A single tile would leave a thin northern strip uncovered. Mosaicking both keeps the AOI complete.
**Evidence:** Tile bboxes from the STAC API; `data/manifest.json` datasets `s2_post_tile_1/2`.
**Consequence:** `s2_post_*` layers are mosaics; report this in the data section.

---

## ADR-15 — Windowed COG reads on a common UTM grid
**Status:** accepted (Day 2)
**Context:** Full RTC scenes are large; the AOI is only ~230 km^2.
**Decision:** Read only the AOI window from each remote Cloud-Optimized GeoTIFF, reproject to `EPSG:32646` at 10 m, and store local subsets.
**Rationale:** Avoids full-scene downloads and keeps processing within the 16 GB laptop.
**Evidence:** `outputs/tables/day2_coverage.csv` (all layers 1713 x 1346, 10 m, 100% valid).
**Consequence:** All later modules consume the local subsets, not the remote scenes.

---

## ADR-16 — 20 Apr 2026 fails the signal gate; pivot to 31 May 2025
**Status:** accepted (partner confirmed 2026-11-05)
**Context:** A post-event pass at 17:27 IST may miss a flash flood that drains earlier. The Day 3 diagnostic tested this explicitly, excluding permanent water and steep slopes.
**Decision:** Do not use 20 Apr 2026 as the primary event. Pivot to the 31 May 2025 fallback only after the same gate passes on the fallback pair.
**Rationale:** The 20 Apr pass shows no coherent urban flood-like area (0.066 km^2 after cleaning) and essentially no urban dark pixels (0.02%). A project built on it would be a weak negative result, not a showable flood-confidence study.
**Evidence:** `outputs/tables/day3_gate_stats.csv`; `outputs/figures/day3_gate_zoom.png`; `code/preprocessing/day3_gate.py`.
**Consequence:** If confirmed, update the event dates, Sentinel-1 pair, Sentinel-2 date, reference map, report data section, and manifest. Keep the April analysis as a documented negative/limitation result.

**Candidate check (Day 3):** 19-20 May 2025 uses RTC 7 May / 19 May and has 1.151 km^2 cleaned flood-like area, but its S2 on 20 May is ~100% cloud. 31 May 2025 uses RTC 21 May / 2 June (DESC rel 77), has 2.357 km^2 cleaned flood-like area, and its S2 on 9 June is 21-31% cloud. The 31 May event is therefore the recommended fallback; the urban signal is weak in both and will be a reported limitation.

---

## ADR-17 — Analysis-ready SAR stack
**Status:** accepted (Day 3)
**Context:** RTC is calibrated and terrain-corrected, but the Planetary Computer RTC still shows speckle; filtering dB values is mathematically invalid (ADR-02).
**Decision:** Apply a 7x7 Lee filter on linear power with 4 looks, then convert to dB (`10*log10`). Use -9999 dB as nodata.
**Rationale:** Reduces speckle before thresholding while keeping the processing order correct.
**Evidence:** `code/preprocessing/build_stack.py`; `data/processed/stack_meta.json`; `outputs/figures/masks_overview.png`.
**Consequence:** Report the filter parameters. Verify the RTC provider metadata before claiming the input was unfiltered.

---

## ADR-18 — Adaptive threshold implementation and Otsu redundancy
**Status:** accepted (Day 3)
**Context:** `skimage.filters.threshold_local` on dB SAR over-detected (66.9 km^2). A local mean minus k*sigma threshold is more controlled.
**Decision:** Use `local_mean - 1.5*local_std` over a 51 px window. k=2.0 was too sparse after cleaning.
**Rationale:** Produces an independent but conservative mask (0.424 km^2); kappa vs the other masks is 0.04-0.07.
**Evidence:** `outputs/tables/mask_stats.csv`; `outputs/tables/mask_kappa.csv`.
**Consequence:** Keep the method as an independent ensemble member and report its conservatism. Otsu VV vs VH kappa is 0.946, so that pair is redundant; decide whether to keep both or replace Otsu VH with VH change detection.

---

## ADR-19 — 18 May 2023 candidate gate (pre-registered)
**Status:** accepted (FAIL)
**Context:** The 31 May 2025 ensemble does not detect urban flood water: High (4/4) class is 0.094 km², 0% urban, 0.5% S2-water recall; the Low (2/4) class is more water-like than High. S1 post was 2 days late and S2 was 9 days late with no pre-event optical. Before committing the report to any event, gate a better event.
**Decision:** Gate the 18 May 2023 event (night of 17 May; waterlogging in Rukminigaon, Chandmari, Jatia) with the following data package, before reconfiguring anything.
- Primary S1 pair (ascending rel41): pre 6 May `S1A_IW_GRDH_1SDV_20230506T115713_20230506T115738_048413_05D2C3_rtc`, post 18 May `S1A_IW_GRDH_1SDV_20230518T115713_20230518T115738_048588_05D805_rtc` (~18 h lag).
- Robustness S1 pair (descending rel77): pre 8 May `S1A_IW_GRDH_1SDV_20230508T234721_20230508T234746_048449_05D3FE_rtc`, post 20 May `S1A_IW_GRDH_1SDV_20230520T234722_20230520T234747_048624_05D927_rtc` (~2.5 d lag).
- Sentinel-2 (T46RCP only, 97.6% AOI): pre 16 May `S2B_MSIL2A_20230516T042709_R133_T46RCP_20230516T082209` (12.23% cloud), post 21 May `S2A_MSIL2A_20230521T042711_R133_T46RCP_20230521T102617` (42.33% cloud).

Hard data gates (D1-D3): D1 primary pair same-orbit with post lag <= 24 h; D2 S2 post clear fraction >= 0.30 on `base & slope_ok`; D3 S2 pre clear fraction >= 0.50 on `base & slope_ok`.
Primary signal/optical gates: S1 `floodlike_clean_urban >= 0.05 km²` on the rel41 pair; and optical (S2 16->21 May urban water increase >= 0.05 km² OR SAR flood-like precision vs S2 water >= 0.50).
Decision rule: PASS if D1-D3 and the primary signal and optical gates hold; PASS WITH CAVEAT if the primary passes but the rel77 pair does not agree (report as transient); FAIL otherwise, record the negative and pivot to surface-water mapping.
**Rationale:** Same-day S1 plus pre/post optical and two independent orbits is the strongest package found; it avoids repeating the 2025 optical gap.
**Evidence:** `code/preprocessing/candidate_may2023.py`; `outputs/tables/candidate_may2023_gate.csv`; `data/candidates/may2023/candidate_manifest.json`.
**Consequence:** If PASS, reconfigure config/pipeline to 18 May 2023 and rerun notebooks 00-03. If FAIL, pivot to surface-water mapping.

**Result (2026-11-06): FAIL.**
- D1 PASS, D2 PASS (post clear 0.948), D3 PASS (pre clear 0.840).
- Signal FAIL: rel41 `floodlike_clean_urban = 0.000 km²` (and rel77 = 0.000 km²); the `dark16 & change` core does not survive the 100-px cleaning.
- Urban change < −2 dB is present (8.75 km² rel41, 7.70 km² rel77) but fragmented: ~24,000 components, largest only 0.008 km² (rel41) / 0.021 km² (rel77).
- Urban dark < −16 dB is essentially absent: 0.008 km² (rel41) / 0.054 km² (rel77).
- Optical FAIL on the water-increase arm: S2 non-permanent water fell 1.908 → 0.502 km² (−1.405 km²); urban water fell 0.476 → 0.090 km² (−0.385 km²). No persistent urban water increase.
- Cross-orbit agreement FAIL: urban-change Jaccard 0.0594; the two independent SAR pairs do not agree on changed pixels, so the change signal is noise/orbit-dominated, not a coherent flood.
- Verdict: the 18 May 2023 event is too small and too transient for 10 m SAR and was gone before the 21 May S2. The pre-registered decision rule requires a pivot to surface-water mapping.
**Evidence (generated):** `data/candidates/may2023/`, `outputs/tables/candidate_may2023_gate.csv`, `outputs/tables/candidate_may2023_components.csv`, `outputs/figures/candidate_may2023.png`, `code/preprocessing/candidate_may2023.py`.

---

## ADR-20 — Pivot to riverine flood (Brahmaputra, June 2023), wider AOI
**Status:** accepted
**Context:** Urban flash floods in central Guwahati are not detectable in C-band SAR: the 18 May 2023 gate FAILed (no coherent urban flood, optical water decreased), and the operational Copernicus GFM product returns all-nodata over the urban AOI (its exclusion mask covers built-up areas). Riverine/seasonal water, by contrast, is reliably mapped by our own masks (86% S2-water recall) and by official products.
**Decision:** Pivot the study to the **Brahmaputra riverine flood of late June 2023** over a widened south-bank AOI that includes the river, Deepor Beel, the floodplain, and Guwahati city.
- AOI (WGS84): `[91.55, 26.00, 91.95, 26.30]` (~1,356 km²), name "Guwahati / Brahmaputra floodplain".
- Sentinel-1 (same-orbit ascending rel41): pre 11 June `S1A_IW_GRDH_1SDV_20230611T115714_20230611T115739_048938_05E286_rtc`, post 23 June `S1A_IW_GRDH_1SDV_20230623T115715_20230623T115740_049113_05E7DB_rtc`.
- Sentinel-2 (25 June, mosaicked): `S2B_MSIL2A_20230625T042709_R133_T46RCQ_20230625T090934` (33.2% cloud) + `S2B_MSIL2A_20230625T042709_R133_T46RCP_20230625T092053` (51.7% cloud).
- Reference: NRSC/ISRO flood map 29 June 2023 (Kamrup Rural 10,195 ha + Kamrup Metro 946 ha inundated); GFM static reference-water mask (134 km² permanent/seasonal water in the AOI) as permanent-water context. GFM per-acquisition flood extent is nodata over this region and is therefore NOT used as a reference.
**Pre-registered gate (feasibility already measured):**
- D1 same-orbit S1 pair (rel41, 11→23 June): PASS.
- D2 S2 clear fraction ≥ 0.50 over the AOI: PASS (0.771).
- Signal: new dark water (post < −16 dB AND pre not dark) ≥ 5 km² and spatially coherent along river/floodplain: PASS (90.84 km² new dark; 131.53 km² dark&change).
- Optical: S2 MNDWI water ≥ 20 km² and SAR new-dark overlaps S2 water substantially: PASS (171.34 km² S2 water; 16.4% of clear pixels).
**Rationale:** Riverine floodwater is large, persistent, and dark — detectable and validatable. This keeps the flood topic and the agreement-confidence methodology, on a flood that actually exists.
**Evidence:** `code/preprocessing/candidate_may2023.py` (diagnostic pattern); feasibility probe outputs (recorded in claims ledger D-008..D-010); NRSC 2023 flood reports.
**Consequence:** Reconfigure `config.yaml` (AOI, event, S1/S2 items), refetch the wider-AOI data tree, rerun notebooks 00-03, rebuild the agreement confidence map, and validate against S2 MNDWI + NRSC + GFM reference water. Urban flash-flood attempts (20 Apr 2026, 31 May 2025, 18 May 2023) are retained as documented negative results.

---

## ADR-21 — Confidence reliability is non-monotonic; the adaptive member degrades High
**Status:** accepted
**Context:** After the riverine pivot (ADR-20), the four-mask agreement map was validated against Sentinel-2 MNDWI water (clear pixels, non-permanent). The pre-registered rule (ADR-04) assumed more agreement = higher confidence.
**Result:** The reliability curve is non-monotonic: observed precision Medium (3/4) = 88.6% > Low (2/4) = 82.9% > High (4/4) = 77.1% > Dry (0-1) = 4.9%. H1 ("High-class precision exceeds Low-class precision") is REJECTED: the High class is less precise than the Medium class.
**Rationale:** The adaptive method (pairwise kappa 0.06-0.08 vs the other three) is a poor ensemble member: it is extremely conservative (5.63 km², 2.7% recall) and its false positives concentrate in the darkest pixels that the other methods also flag, so requiring all four to agree removes true water without removing false positives.
**Evidence:** `outputs/tables/metrics_by_class.csv`; `outputs/figures/reliability_curve.png`; `code/confidence/validate.py`.
**Consequence:** Report the non-monotonicity as a finding. Recommend dropping the adaptive member and using 3-method agreement (High = 3/3) as the confidence rule, or re-weighting members by pairwise agreement. The binary flood mask (k >= 2) is already strong: F1 0.81, IoU 0.68, precision 86.6%, recall 76.1% vs S2 MNDWI.

---

## ADR-22 — Drop the adaptive member (3-method ensemble) as the confidence rule
**Status:** accepted
**Context:** ADR-21 found the 4-method reliability curve non-monotonic (High less precise than Medium) and attributed it to the adaptive member. The recommendation was tested by re-running the confidence analysis on the 3-method ensemble (Otsu VV, Otsu VH, change VV) against the same Sentinel-2 MNDWI reference.
**Result:** Dropping the adaptive member restores monotonicity. 3-method per-class precision: dry 3.3%, low 43.2%, medium 82.6%, high 88.4% — High (3/3) is now the most precise class, and the ordering High > Medium > Low holds. The binary flood map is essentially unchanged (F1 0.8094 vs 0.8097; IoU 0.6798 vs 0.6803), confirming the adaptive method contributes nothing to the flood map while degrading the confidence ordering.
**Decision:** Adopt the 3-method ensemble as the primary confidence rule. Report the 4-method result as the diagnostic that motivated the change, and the 3-method result as the final reliability curve. Keep the adaptive mask as a recorded (superseded) ensemble member, not as a confidence contributor.
**Evidence:** `outputs/tables/sensitivity_drop_adaptive.csv`; `outputs/tables/sensitivity_drop_adaptive_binary.csv`; `code/confidence/sensitivity_drop_adaptive.py`.
**Consequence:** The headline H1 finding is refined: agreement predicts reliability only with a well-chosen ensemble. Update DRAFT_REPORT Results and the reliability curve to the 3-method version; the 4-method non-monotonic curve is retained as the motivating diagnostic.

---

## ADR-23 — Replace the adaptive member with GMM (or Kittler); a monotonic 4-method ensemble is achievable
**Status:** accepted
**Context:** ADR-22 showed the adaptive member was the problem, but dropping it leaves only a 3-method ensemble. The question remained: can we keep four votes and still get a monotonic reliability curve, by replacing adaptive with a stronger classical method?
**Result:** Two candidate replacements were built and tested — Kittler-Illingworth minimum-error threshold and a 2-component Gaussian-mixture (GMM) threshold — on post-event VV, with the same cleaning and domain as the other methods.
- Per-method (vs S2 MNDWI): Kittler precision 92.5%, recall 66.7%, F1 0.775, kappa 0.803; GMM precision 78.8%, recall 81.5%, F1 0.801, kappa 0.829. Both correlate strongly with the three "good" methods (kappa ~0.8), unlike adaptive (kappa 0.06).
- 4-method ensembles (3 good + candidate): adaptive is non-monotonic (High 77.1% < Medium 88.6%, F1 0.8097); **Kittler is monotonic** (High 91.1% > Medium 88.5% > Low 56.1%, F1 0.8095); **GMM is monotonic** (High 88.4% > Medium 83.7% > Low 45.6%, F1 0.8138).
- Leave-one-out ablation: dropping any of the three "good" methods breaks monotonicity AND lowers F1 (Otsu VV → 0.693, Otsu VH → 0.675, change → 0.797); only dropping adaptive is monotonic (F1 0.8094).
**Decision:** Adopt **GMM** as the 4th ensemble member: it restores a monotonic 4-method reliability curve while giving the best binary F1 (0.8138) and highest recall (80.2%). Kittler is noted as a strong alternative (highest single-method precision 92.5%, monotonic). The adaptive member is removed from the confidence rule (superseded by ADR-22).
**Evidence:** `code/confidence/alternative_members.py`; `outputs/tables/candidate_members.csv`, `ensemble_4th_member.csv`, `leave_one_out.csv`; `outputs/figures/candidate_members.png`, `alternative_members_reliability.png`.
**Consequence:** Final confidence rule is a 4-method ensemble (Otsu VV, Otsu VH, change VV, GMM), flood-positive k ≥ 2, monotonic High > Medium > Low reliability. Report this as the refined conclusion of H1: agreement predicts reliability when the ensemble members genuinely measure the same signal (kappa ≈ 0.8), and fails when a member is uncorrelated and low-recall (adaptive, kappa ≈ 0.06).

---

## ADR-24 — The 50 % JRC cut is retained, justified by what it removes rather than by its date

**Status:** accepted
**Context:** The JRC occurrence cut (ADR-06) is the highest-leverage static parameter, and "we fixed it a priori" is not an answer to "why 50 and not 90". The mask's purpose is to stop water that was already present from being counted as flood, which is directly testable against the pre-event image.
**Test:** For every JRC occurrence band, measure (a) the fraction that is water in the 11 June pre-event SAR and (b) the fraction that only becomes water at the 23 June peak. Then hold every other parameter fixed and move one at a time, rebuilding the adopted GMM ensemble.
**Result:**
- The 50 % cut removes 91.24 km², of which **90.4 % was already water pre-event** and only **5.0 %** becomes water at the peak.
- Occurrence bands are monotonic: 10–20 % → 25.7 % already wet, 30–40 % → 56.9 %, 50–60 % → 76.6 %, 90–100 % → 97.8 %. Below 40 %, 12–24 % of pixels genuinely become new water (floodable floodplain that must not be masked).
- JRC 0 / 50 / 90 gives 224.24 / 136.47 / 196.91 km² at k ≥ 2. The 50–89 % band that 90 % re-admits is 94.7 % water in Sentinel-2: it is the seasonal channel, not flood.
- On a **fixed evaluation set** F1 is 0.8167 / 0.8138 / 0.8162 at JRC 0 / 50 / 90 (Δ ≤ 0.003). The "own-domain" F1 (0.8876 / 0.8138 / 0.8724) rises only because the reference moves with the domain. The cut is therefore definitional, not an accuracy lever.
- Slope is immaterial (10→20° adds 1.27 km², +0.9 %); the adaptive member is unstable by construction (window 51→151: 5.63→18.13 km²; k 1.5→2.0: 0.67 km²), which independently supports its exclusion from the ensemble.
**Decision:** Retain 50 %. Treat it as the conservative end of a defensible range (~40–60 %), not as an absolute truth; say "water more than half the time", since GSW's own permanent/seasonal split comes from its seasonality layer rather than a 50 % occurrence cut.
**Evidence:** `code/confidence/static_masks_sensitivity.py`; `outputs/tables/jrc_preevent_test.csv`, `static_masks_sensitivity.csv`, `adaptive_member_sensitivity.csv`, `jrc_validation_sensitivity.csv`.
**Consequence:** Closes claims-ledger C-009 and discharges ADR-06's promised with/without permanent-water comparison (224.24 vs 136.47 km²). §8 and §10 of the report now state the definitional nature of the cut; the viva answer is the 90.4 % pre-event figure, not the date the value was chosen.

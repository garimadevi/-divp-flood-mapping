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

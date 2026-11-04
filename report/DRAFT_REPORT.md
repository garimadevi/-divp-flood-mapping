# Multi-Method Urban Flood Segmentation and Agreement-Based Confidence Estimation Using Sentinel-1 SAR Imagery

**Draft report — living document. Do not treat any section as final until it is marked `[locked]`.**

| Field | Value |
|---|---|
| Authors | Garima Devi (Roll No. 240101007), Pritom Sarma (Roll No. 240101013) |
| Department | Electronics and Communication Engineering, GUIST |
| Institution | Gauhati University |
| Supervisor | [To verify] |
| Course | Digital Image and Video Processing (DIVP) mini-project |
| Date | November 2026 |
| Status | Draft v0.3 — event pivoted to 31 May 2025; data refetched; signal gate passed |

> **Evidence rule:** this document may only state a result that exists in `outputs/` and has a row in `claims_ledger.md`. Anything not yet produced is tagged `[planned]` or `[to verify]`. No invented numbers.

---

## Abstract

[planned] Urban flooding in Guwahati is drainage-driven, and single-method SAR flood maps are unreliable in built-up terrain. This project compares multiple classical image-processing methods on the same Sentinel-1 pair for the 31 May 2025 Guwahati flood, combines their outputs into a per-pixel agreement-based confidence map, and tests whether higher agreement corresponds to higher classification accuracy. Expected contributions are stated as hypotheses, not results.

---

## 1. Introduction

[planned] Guwahati and the Bharalu basin; why binary flood maps fail in cities; role and limits of Sentinel-1 SAR; why agreement-based confidence is worth testing.

---

## 2. Problem Statement

[planned] P1–P5.

---

## 3. Aim, Objectives, Research Question, Hypothesis

**Aim.** [planned]

**Objectives.**
1. Acquire and preprocess the 21 May and 2 June 2025 Sentinel-1 RTC pair over Guwahati.
2. Implement at least three independent flood-segmentation methods.
3. Build an agreement-based confidence map (High / Medium / Low / Dry).
4. Validate per method and per confidence class against optical and manual references.
5. Test whether High-confidence pixels have higher precision than Low-confidence pixels.

**Research question.** Does multi-method agreement predict per-pixel flood-map accuracy in dense urban terrain?

**H1.** Precision in High-agreement pixels is significantly greater than precision in Low-agreement pixels. A negative result is a valid finding and will be reported.

---

## 4. Study Area and Event

Guwahati / Kamrup Metropolitan, Assam, with a focus on the Bharalu basin and the repeatedly flooded central wards. The selected event is the **31 May 2025** Guwahati flood, reported as record rainfall of about 111 mm in 24 hours, the highest in nearly 70 years `[To verify]`.

**Event selection.** The originally planned 19–20 April 2026 event failed the Day 3 signal gate: the 20 April 17:27 IST Sentinel-1 pass contained no coherent urban flood-like area (0.066 km^2 after cleaning; 0.02% urban dark pixels). Rather than force a weak result, the project pivoted to 31 May 2025, which has a same-orbit RTC pair (21 May and 2 June, descending relative orbit 77) and a usable Sentinel-2 scene on 9 June 2025 (21–31% cloud). The April analysis is retained as a documented negative result.

**Event context.** `[To verify]` Rainfall, affected localities, and impact figures must be cited to ASDMA and press sources before this section is `[locked]`.

---

## 5. Data

Verified against the live Planetary Computer STAC API on 2026-11-05 (event pivot). Source of truth: `data/manifest.json`.

| Dataset | Collection / item | Date (UTC) | Purpose |
|---|---|---|---|
| Sentinel-1 RTC pre | `sentinel-1-rtc` / `S1A_IW_GRDH_1SDV_20250521T234717_20250521T234742_059299_075C07_rtc` | 2025-05-21 23:47 | Pre-event VV/VH (DESC rel 77) |
| Sentinel-1 RTC post | `sentinel-1-rtc` / `S1A_IW_GRDH_1SDV_20250602T234717_20250602T234742_059474_rtc` | 2025-06-02 23:47 | Post-event VV/VH (DESC rel 77) |
| Sentinel-2 L2A post | `sentinel-2-l2a` / `T46RCQ` + `T46RCP` | 2025-06-09 04:27 | MNDWI reference (21–31% cloud) |
| Copernicus DEM 30 m | `cop-dem-glo-30` / `Copernicus_DSM_COG_10_N26_00_E091_00_DEM` | 2021 | Slope / elevation mask |
| JRC Global Surface Water | `jrc-gsw` / `90E_30Nv1_3_2020` (`occurrence`) | 2020 | Permanent water mask |
| ESA WorldCover 10 m | `esa-worldcover` / `ESA_WorldCover_10m_2021_v200_N24E090` | 2021 | Urban / vegetation mask |

**Acquisition status (Day 3).** All layers were read as windowed AOI subsets and reprojected to a common `EPSG:32646` grid at 10 m. The grid is 1713 x 1346 pixels (230.57 km^2) and every layer is 100% valid. SHA256 checksums are recorded in `data/manifest.json`; coverage statistics are in `outputs/tables/day2_coverage.csv`.

**Data caveats.** The AOI straddles two Sentinel-2 MGRS tiles, so both were mosaicked. The SAR pair is 21 May (10 days pre-event) and 2 June (2 days post-event), both descending nighttime passes. The Sentinel-2 reference is 9 June (9 days after the event) and 21–31% cloud, so validation must mask clouds and report clear-pixel coverage. Urban SAR remains weak because of double bounce, layover, and shadow; the confidence map will expose this rather than hide it. The originally planned 20 April 2026 event failed the signal gate and is retained as a documented negative result.

---

## 6. Methodology (partial — implemented parts)

**M1 preprocessing (implemented).** The RTC pair is read on the common 10 m grid. A 7x7 Lee filter is applied to linear power with 4 looks, then converted to dB (`10*log10`). Slope is derived from the Copernicus DEM. Permanent water is JRC occurrence >= 50%; urban is ESA WorldCover class 50; vegetation is classes 10–40. All products share the `EPSG:32646` grid.

**M2 flood-mask ensemble (implemented).** Four methods are applied:
1. Global Otsu on post-event VV (threshold -10.65 dB).
2. Global Otsu on post-event VH (threshold -17.98 dB).
3. VV change detection: post - pre < -3.0 dB.
4. Local adaptive threshold: post VV < local mean - 1.5 × local std (51 px window), median threshold -8.85 dB.

Each mask is cleaned with a 3×3 opening/closing, small components (<100 px) are removed, and permanent water and slopes >10° are masked.

**M3 agreement confidence (planned).** Count k of N methods calling a pixel flooded: k=N High, k=N-1 Medium, 2<=k<=N-2 Low, k<=1 Dry.

**M4 validation (planned).** Sentinel-2 MNDWI on clear pixels plus a stratified manual sample; precision, recall, F1, IoU, overall accuracy, kappa, and a reliability curve by confidence class.

---

## 7. Validation Design

[planned] Reference hierarchy: stratified manual sample > Sentinel-2 MNDWI clear pixels > official maps. Metrics: precision, recall, F1, IoU, overall accuracy, Cohen's kappa, and a reliability curve by confidence class. Report clear-pixel coverage and the S1/S2 time gap.

---

## 8. Results (provisional)

**Mask diagnostics — 31 May 2025.** These are provisional diagnostics, not validated accuracy results. Evidence: `outputs/tables/mask_stats.csv`, `outputs/tables/mask_kappa.csv`.

| Method | Threshold | Flood area (km^2) |
|---|---|---|
| Otsu VV | -10.65 dB | 9.492 |
| Otsu VH | -17.98 dB | 9.348 |
| Change VV | -3.0 dB | 4.141 |
| Adaptive VV | -8.85 dB (median local) | 0.424 |

Pairwise Cohen's kappa: Otsu VV vs VH 0.946 (near-duplicate); Otsu VV vs change 0.561; Otsu VH vs change 0.540; adaptive vs the others 0.04–0.07 (independent but conservative). The Otsu pair is redundant; this must be addressed in the confidence design and reported honestly. No validation against reference data has been run yet, so no accuracy claim is made.

---

## 9. Failure Analysis

[planned] Error map and failure taxonomy: urban double bounce, shadow/layover, slope, vegetation, temporal change, date gap. The 20 April 2026 event is included as a documented failure case: the 17:27 IST pass missed the flash flood, which demonstrates how sensitive SAR event mapping is to acquisition timing.

---

## 10. Limitations

[planned] No ground-truth survey; Sentinel-2 MNDWI is a reference, not truth, and the 9 June scene is 21–31% cloud and 9 days after the event; the SAR pre-event is 10 days before and the post-event 2 days after; both SAR passes are descending nighttime acquisitions; urban SAR is weak because of double bounce, shadow, and layover, so the urban flood extent is likely under-estimated; the 20 April 2026 event failed the signal gate and is retained only as a negative result; single event; no hydrological modelling.

---

## 11. Future Work

[planned] Pothole/street-level damage, OSM road-hazard prioritisation, health-facility access, multi-pass persistence, FwDET depth, extension to other Assam events.

---

## References

See `report/references/references.bib`. All citations in IEEE style via Pandoc `--citeproc`.

---

## Appendix

- `report/decisions.md` — engineering decision log (ADRs)
- `report/claims_ledger.md` — claim-to-evidence ledger
- `report/WORKLOG.md` — dated build log
- `data/manifest.json` — dataset provenance and checksums

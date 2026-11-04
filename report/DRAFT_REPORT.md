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
| Status | Draft v0.2 — Day 2 data acquisition complete; results pending |

> **Evidence rule:** this document may only state a result that exists in `outputs/` and has a row in `claims_ledger.md`. Anything not yet produced is tagged `[planned]` or `[to verify]`. No invented numbers.

---

## Abstract

[planned] Urban flooding in Guwahati is drainage-driven, and single-method SAR flood maps are unreliable in built-up terrain. This project compares multiple classical image-processing methods on the same Sentinel-1 pair and combines their outputs into a per-pixel agreement-based confidence map, then tests whether higher agreement corresponds to higher classification accuracy. Expected contributions are stated as hypotheses, not results.

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
1. Acquire and preprocess the 8 April and 20 April 2026 Sentinel-1 RTC pair over Guwahati.
2. Implement at least three independent flood-segmentation methods.
3. Build an agreement-based confidence map (High / Medium / Low / Dry).
4. Validate per method and per confidence class against optical and manual references.
5. Test whether High-confidence pixels have higher precision than Low-confidence pixels.

**Research question.** Does multi-method agreement predict per-pixel flood-map accuracy in dense urban terrain?

**H1.** Precision in High-agreement pixels is significantly greater than precision in Low-agreement pixels. A negative result is a valid finding and will be reported.

---

## 4. Study Area and Event

[planned] Guwahati / Kamrup Metropolitan, Bharalu basin. 19–20 April 2026 event. Rainfall and impact facts must be verified and cited before `[locked]`.

---

## 5. Data

Verified against the live Planetary Computer STAC API on 2026-11-04. Source of truth: `data/manifest.json`.

| Dataset | Collection / item | Date (UTC) | Purpose |
|---|---|---|---|
| Sentinel-1 RTC pre | `sentinel-1-rtc` / `S1A_IW_GRDH_1SDV_20260408T115658_20260408T115723_063988_080CD1_rtc` | 2026-04-08 11:57 | Pre-event VV/VH |
| Sentinel-1 RTC post | `sentinel-1-rtc` / `S1A_IW_GRDH_1SDV_20260420T115658_20260420T115723_064163_08135B_rtc` | 2026-04-20 11:57 | Post-event VV/VH |
| Sentinel-2 L2A post | `sentinel-2-l2a` / `T46RCQ` + `T46RCP` | 2026-04-20 04:26 | MNDWI reference |
| Copernicus DEM 30 m | `cop-dem-glo-30` / `Copernicus_DSM_COG_10_N26_00_E091_00_DEM` | 2021 | Slope / elevation mask |
| JRC Global Surface Water | `jrc-gsw` / `90E_30Nv1_3_2020` (`occurrence`) | 2020 | Permanent water mask |
| ESA WorldCover 10 m | `esa-worldcover` / `ESA_WorldCover_10m_2021_v200_N24E090` | 2021 | Urban / vegetation mask |

**Acquisition status (Day 2).** All layers were read as windowed AOI subsets and reprojected to a common `EPSG:32646` grid at 10 m. The grid is 1713 x 1346 pixels (230.57 km^2) and every layer is 100% valid. SHA256 checksums are recorded in `data/manifest.json`; coverage statistics are in `outputs/tables/day2_coverage.csv`.

**Data caveats.** The AOI straddles two Sentinel-2 MGRS tiles, so both were mosaicked. The pre-event SAR is 12 days before the event. The post-event pass is at 11:57 UTC (17:27 IST), so some flash water may already have drained; this must be checked at the Day 3 gate before any flood result is reported.

---

## 6. Methodology

[planned] M1 preprocessing, M2 flood-mask ensemble, M3 agreement confidence and masks, M4 validation. Equations and parameter choices must be written as implemented.

---

## 7. Validation Design

[planned] Reference hierarchy: stratified manual sample > Sentinel-2 MNDWI clear pixels > official maps. Metrics: precision, recall, F1, IoU, overall accuracy, Cohen's kappa, and a reliability curve by confidence class. Report clear-pixel coverage and the S1/S2 time gap.

---

## 8. Results

[planned] Only script-generated results. Tables and figures must reference the producing script and a `claims_ledger.md` row.

---

## 9. Failure Analysis

[planned] Error map and failure taxonomy: urban double bounce, shadow/layover, slope, vegetation, temporal change, date gap.

---

## 10. Limitations

[planned] No ground-truth survey; MNDWI is a reference, not truth; 12-day pre-event gap; post-event pass at 17:27 IST may postdate drainage; urban SAR limitations; single event.

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

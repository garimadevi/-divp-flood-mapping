# Multi-Method Flood Segmentation and Agreement-Based Confidence Estimation Using Sentinel-1 SAR Imagery

**Draft report — living document. Do not treat any section as final until it is marked `[locked]`.**

| Field | Value |
|---|---|
| Authors | Garima Devi (Roll No. 240101007), Pritom Sarma (Roll No. 240101013) |
| Department | Electronics and Communication Engineering, GUIST |
| Institution | Gauhati University |
| Supervisor | [To verify] |
| Course | Digital Image and Video Processing (DIVP) mini-project |
| Date | November 2026 |
| Status | Draft v0.4 — pivoted to the Brahmaputra riverine flood (23 June 2023); ensemble + confidence + validation complete |

> **Evidence rule:** this document may only state a result that exists in `outputs/` and has a row in `claims_ledger.md`. Anything not yet produced is tagged `[planned]` or `[to verify]`. No invented numbers.

---

## Abstract

Urban flash flooding in Guwahati proved undetectable in C-band Sentinel-1 SAR (small, transient, and not dark enough in built-up terrain; the operational Copernicus GFM product excludes urban areas). The project therefore targets the **Brahmaputra riverine flood of late June 2023** over a widened Guwahati floodplain AOI. Four classical image-processing methods (Otsu VV, Otsu VH, VV change detection, local adaptive VV) are combined into a per-pixel agreement-based confidence map and validated against Sentinel-2 MNDWI. The binary flood map (agreement ≥ 2/4) reaches precision 86.6%, recall 76.1%, F1 0.81, IoU 0.68. The central hypothesis — that higher inter-method agreement implies higher accuracy — is **rejected**: the reliability curve is non-monotonic (Medium 88.6% > Low 82.9% > High 77.1%), because the adaptive member degrades the High class. The urban events (20 Apr 2026, 31 May 2025, 18 May 2023) are retained as documented negative results.

---

## 1. Introduction

[planned] Guwahati and the Brahmaputra floodplain; why binary flood maps fail in cities but work on open water; role and limits of Sentinel-1 SAR; why agreement-based confidence is worth testing, and why it fails when an ensemble member is a poor detector.

---

## 2. Problem Statement

[planned] P1–P5.

---

## 3. Aim, Objectives, Research Question, Hypothesis

**Aim.** [planned]

**Objectives.**
1. Acquire and preprocess a same-orbit Sentinel-1 RTC pair (11 June and 23 June 2023, ascending rel 41) over the Guwahati Brahmaputra floodplain.
2. Implement four independent flood-segmentation methods.
3. Build an agreement-based confidence map (High / Medium / Low / Dry).
4. Validate per method and per confidence class against Sentinel-2 MNDWI.
5. Test whether High-confidence pixels have higher precision than Low-confidence pixels.

**Research question.** Does multi-method agreement predict per-pixel flood-map accuracy?

**H1.** Precision in High-agreement pixels is significantly greater than precision in Low-agreement pixels. A negative result is a valid finding and will be reported.

---

## 4. Study Area and Event

Guwahati / Kamrup (Assam), the south bank of the Brahmaputra and its floodplain (including Deepor Beel). The selected event is the **Brahmaputra riverine flood of late June 2023**, when the river and its tributaries rose above danger level; the NRSC/ISRO flood map of 29 June 2023 reports **Kamrup Rural 10,195 ha and Kamrup Metro 946 ha** inundated.

**Event selection.** The project's original urban-flash-flood target failed repeatedly: the 20 April 2026 pass showed no coherent flood signal; the 31 May 2025 ensemble detected no urban flood water (High class 0% urban); the 18 May 2023 candidate failed its pre-registered gate (no coherent urban flood, optical water decreased, two SAR orbits disagreed). Independently, the Copernicus Global Flood Monitoring (GFM) product returns all-nodata over urban Guwahati (its exclusion mask covers built-up areas), confirming that C-band SAR cannot delineate urban flood here. The riverine flood is large (90.84 km² of new dark water between 11 and 23 June), persistent, and dark — detectable and validatable. This is the documented, pre-registered pivot (ADR-20).

**Event context.** `[To verify]` Rainfall, affected localities, and impact figures must be cited to ASDMA/NRSC and press sources before this section is `[locked]`.

---

## 5. Data

Verified against the live Planetary Computer STAC API on 2026-11-07 (riverine pivot). Source of truth: `data/manifest.json`.

| Dataset | Collection / item | Date (UTC) | Purpose |
|---|---|---|---|
| Sentinel-1 RTC pre | `sentinel-1-rtc` / `S1A_IW_GRDH_1SDV_20230611T115714_20230611T115739_048938_05E286_rtc` | 2023-06-11 11:57 | Pre-event VV/VH (ASC rel 41) |
| Sentinel-1 RTC post | `sentinel-1-rtc` / `S1A_IW_GRDH_1SDV_20230623T115715_20230623T115740_049113_05E7DB_rtc` | 2023-06-23 11:57 | Post-event VV/VH (ASC rel 41) |
| Sentinel-2 L2A post | `sentinel-2-l2a` / `T46RCQ` + `T46RCP` | 2023-06-25 04:27 | MNDWI reference (33%/52% cloud) |
| Copernicus DEM 30 m | `cop-dem-glo-30` / `Copernicus_DSM_COG_10_N26_00_E091_00_DEM` | 2021 | Slope / elevation mask |
| JRC Global Surface Water | `jrc-gsw` / `90E_30Nv1_3_2020` (`occurrence`) | 2020 | Permanent water mask |
| ESA WorldCover 10 m | `esa-worldcover` / `ESA_WorldCover_10m_2021_v200_N24E090` | 2021 | Urban / vegetation mask |

**Acquisition status.** All layers were read as windowed AOI subsets and reprojected to a common `EPSG:32646` grid at 10 m. The widened AOI `[91.55, 26.00, 91.95, 26.30]` is 4032 x 3362 pixels (1,355.6 km²); the analysis domain (non-permanent, slope ≤ 10°) is 727.4 km². SHA256 checksums are recorded in `data/manifest.json`.

**Data caveats.** The AOI straddles two Sentinel-2 MGRS tiles, so both were mosaicked. The SAR pair is a same-orbit ascending rel-41 pair 12 days apart (11 and 23 June). The Sentinel-2 reference is 25 June (2 days after the S1 post), with a clear fraction of 0.771 over the analysis domain; validation therefore masks clouds and reports clear-pixel coverage. GFM's per-acquisition flood extent is all-nodata over this region (urban/forest exclusion), so GFM is used only for its static reference-water mask, and Sentinel-2 MNDWI is the primary reference.

---

## 6. Methodology (implemented)

**M1 preprocessing.** The RTC pair is read on the common 10 m grid. A 7x7 Lee filter is applied to linear power with 4 looks, then converted to dB (`10*log10`). Slope is derived from the Copernicus DEM. Permanent water is JRC occurrence ≥ 50%; urban is ESA WorldCover class 50; vegetation is classes 10–40. All products share the `EPSG:32646` grid.

**M2 flood-mask ensemble.** Four methods are applied:
1. Global Otsu on post-event VV (threshold −12.55 dB).
2. Global Otsu on post-event VH (threshold −17.31 dB).
3. VV change detection: post − pre < −3.0 dB.
4. Local adaptive threshold: post VV < local mean − 1.5 × local std (51 px window).

Each mask is cleaned with a 3×3 opening/closing, small components (<100 px) are removed, and permanent water and slopes >10° are masked. Pairwise Cohen's kappa: Otsu VV–VH 0.849; Otsu vs change 0.76–0.79; adaptive vs the others 0.06–0.08.

**M3 agreement confidence.** k of N=4 methods call a pixel flooded: k=4 High, k=3 Medium, k=2 Low, k≤1 Dry; flood-positive is k ≥ 2.

**M4 validation.** Sentinel-2 MNDWI > 0 on clear, non-permanent pixels within the analysis domain; precision, recall, F1, IoU, overall accuracy, and a reliability curve by confidence class.

---

## 7. Validation Design

Reference hierarchy: Sentinel-2 MNDWI on clear pixels (primary), NRSC/ISRO official flood map (context), GFM reference-water mask (permanent/seasonal water context). Metrics: precision, recall, F1, IoU, overall accuracy, and a reliability curve by confidence class. Clear-pixel coverage (0.771) and the S1/S2 time gap (2 days) are reported.

---

## 8. Results (verified)

**Mask diagnostics.** Evidence: `outputs/tables/mask_stats.csv`, `mask_kappa.csv`.

| Method | Threshold | Flood area (km²) | F1 vs S2 MNDWI |
|---|---|---|---|
| Otsu VV | −12.55 dB | 111.75 | 0.797 |
| Otsu VH | −17.31 dB | 143.02 | 0.817 |
| Change VV | −3.0 dB | 108.17 | 0.691 |
| Adaptive VV | −9.57 dB (median local) | 5.63 | 0.052 |

**Agreement confidence map.** Evidence: `outputs/tables/confidence_classes.csv`, `outputs/maps/confidence/agreement_classes.tif`.

| Class | k | Area (km²) | Observed precision |
|---|---|---|---|
| Dry | 0–1 | 604.76 | 4.9% |
| Low | 2 | 33.93 | 82.9% |
| Medium | 3 | 84.77 | 88.6% |
| High | 4 | 3.91 | 77.1% |

**Binary flood map (k ≥ 2, 122.59 km²).** Evidence: `outputs/tables/metrics_flood_binary.csv`. Precision 86.6%, recall 76.1%, F1 0.810, IoU 0.680, overall accuracy 93.8%.

**Key finding (H1 rejected, then refined).** The 4-method reliability curve is non-monotonic: Medium (3/4) precision 88.6% > Low 82.9% > High 77.1%. H1 ("High-class precision exceeds Low-class precision") is **rejected** for the 4-method ensemble. The adaptive method (κ ≈ 0.06–0.08 vs the others) is a poor ensemble member: it is extremely conservative (5.63 km², 2.7% recall) and its false positives concentrate in the darkest pixels that the other methods also flag, so requiring all four to agree removes true water without removing false positives. Dropping the adaptive member restores monotonicity: the 3-method ensemble gives **high 88.4% > medium 82.6% > low 43.2%** — High (3/3) is now the most precise class — while the binary flood map is unchanged (F1 0.8094 vs 0.8097). Conclusion: agreement predicts reliability only with a well-chosen ensemble (ADR-22). Evidence: `outputs/tables/metrics_by_class.csv`, `outputs/tables/sensitivity_drop_adaptive.csv`, `outputs/figures/reliability_curve.png`; ADR-21, ADR-22.

---

## 9. Failure Analysis

[planned] Error map and failure taxonomy. The urban events are documented failure cases: 20 Apr 2026 (pass at 17:27 IST missed the flash flood), 31 May 2025 (no urban flood water), 18 May 2023 (too small/transient; two orbits disagreed; optical water decreased). These show how sensitive C-band flood mapping is to event type, size, and acquisition timing.

---

## 10. Limitations

[planned] No ground-truth survey; Sentinel-2 MNDWI is a reference, not truth, and the 25 June scene is 33%/52% cloud (clear fraction 0.771) and 2 days after the S1 post; the SAR pair is 12 days apart; adaptive method is too conservative; single event; no hydrological modelling; urban-flood capability is a documented negative result.

---

## 11. Future Work

[planned] 3-method agreement re-design (drop adaptive), per-member re-weighting, stratified manual sample, multi-pass persistence, FwDET depth, extension to other Assam flood events.

---

## References

See `report/references/references.bib`. All citations in IEEE style via Pandoc `--citeproc`.

---

## Appendix

- `report/decisions.md` — engineering decision log (ADRs)
- `report/claims_ledger.md` — claim-to-evidence ledger
- `report/WORKLOG.md` — dated build log
- `data/manifest.json` — dataset provenance and checksums

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
| Status | Draft v0.5 — riverine flood (23 June 2023); ensemble + confidence + validation + ensemble-design analysis (Kittler/GMM) complete |

> **Evidence rule:** this document may only state a result that exists in `outputs/` and has a row in `claims_ledger.md`. Anything not yet produced is tagged `[planned]` or `[to verify]`. No invented numbers.

---

## Abstract

Urban flash flooding in Guwahati proved undetectable in C-band Sentinel-1 SAR (small, transient, and not dark enough in built-up terrain; the operational Copernicus GFM product excludes urban areas). The project therefore targets the **Brahmaputra riverine flood of late June 2023** over a widened Guwahati floodplain AOI. Multiple classical image-processing methods (Otsu VV, Otsu VH, VV change detection, local adaptive, plus two alternatives — Kittler–Illingworth and a Gaussian-mixture threshold) are combined into a per-pixel agreement-based confidence map and validated against Sentinel-2 MNDWI. The binary flood map (agreement ≥ 2) reaches precision 86.6%, recall 76.1%, F1 0.81, IoU 0.68. The hypothesis that higher inter-method agreement implies higher accuracy is **rejected for the original ensemble** — the reliability curve is non-monotonic (Medium 88.6% > High 77.1%) because the adaptive member is uncorrelated and low-recall — but **replacing adaptive with the GMM member restores monotonicity** (High 88.4% > Medium 83.7% > Low 45.6%). The conclusion: agreement predicts reliability only when ensemble members genuinely measure the same signal. The urban events (20 Apr 2026, 31 May 2025, 18 May 2023) are retained as documented negative results.

---

## 1. Introduction

Flooding is among the most frequent and damaging natural hazards in the Brahmaputra valley, and Kamrup district — which contains Guwahati, Assam's largest city — experiences near-annual inundation when the Brahmaputra and its tributaries exceed their banks during the South Asian monsoon. Rapid, wall-to-wall knowledge of where water stands is essential for response and damage assessment. Synthetic aperture radar (SAR) is the natural sensor for this task: it images through cloud and at night, which is precisely when monsoon floods occur and optical sensors are unavailable.

SAR flood mapping is conventionally framed as binary segmentation — a single algorithm produces a water/land map with no indication of how trustworthy each pixel is. This project asks a different question: when several independent image-processing methods are run on the same scene, does the degree to which they agree indicate how accurate the resulting map is? If so, a per-pixel agreement count can serve as a confidence layer, distinguishing pixels that are almost certainly water from those that are uncertain — information that matters for decisions made from the map.

The study area also motivated the work negatively: Guwahati's flash floods (short-lived waterlogging after intense rainfall) proved too small, transient, and shallow to appear as dark targets in C-band SAR, a limitation independently confirmed by the operational Copernicus Global Flood Monitoring product, which excludes built-up areas from flood delineation. The project therefore targets a large, persistent riverine flood, where the SAR signal is unambiguous, to test the confidence methodology under favourable conditions and to establish the conditions under which agreement-based confidence is trustworthy.

---

## 2. Problem Statement

The work decomposes into five sub-problems.

**P1 — Data.** Acquire a co-registered Sentinel-1 SAR pre/post pair and an independent Sentinel-2 scene for a real flood event, reprojected to a common grid, with permanent water and steep slopes masked.

**P2 — Segmentation.** Implement multiple classical flood-segmentation methods that make genuinely different assumptions about the data (global histogram thresholding, dual-polarisation thresholding, change detection, local adaptive thresholding, and minimum-error/Gaussian-mixture thresholding).

**P3 — Confidence.** Combine the methods into a per-pixel agreement count k of N and define a confidence map (High / Medium / Low / Dry) plus a binary flood map.

**P4 — Validation.** Validate the flood map and each confidence class against an independent Sentinel-2 MNDWI water reference, computing precision, recall, F1, IoU, and overall accuracy, and a reliability curve by class.

**P5 — Inference.** Determine whether agreement predicts accuracy (H1), and characterise what properties an ensemble member must have for the confidence map to be trustworthy.

---

## 3. Aim, Objectives, Research Question, Hypothesis

**Aim.** To determine whether per-pixel inter-method agreement in a multi-method Sentinel-1 flood segmentation provides a reliable measure of map confidence, and to characterise the conditions — in particular the quality and independence of the ensemble members — under which such an agreement-based confidence map is trustworthy, validated against Sentinel-2.

**Objectives.**
1. Acquire and preprocess a same-orbit Sentinel-1 RTC pair (11 June and 23 June 2023, ascending rel 41) over the Guwahati Brahmaputra floodplain.
2. Implement an ensemble of independent flood-segmentation methods (four core methods plus two alternative thresholding methods).
3. Build an agreement-based confidence map (High / Medium / Low / Dry).
4. Validate per method and per confidence class against Sentinel-2 MNDWI.
5. Test whether High-confidence pixels have higher precision than Low-confidence pixels.

**Research question.** Does multi-method agreement predict per-pixel flood-map accuracy?

**H1.** Precision in High-agreement pixels is significantly greater than precision in Low-agreement pixels. A negative result is a valid finding and will be reported.

---

## 4. Study Area and Event

Guwahati / Kamrup (Assam), the south bank of the Brahmaputra and its floodplain (including Deepor Beel). The selected event is the **Brahmaputra riverine flood of late June 2023**, when the river and its tributaries rose above danger level; the NRSC/ISRO flood map of 29 June 2023 reports **Kamrup Rural 10,195 ha and Kamrup Metro 946 ha** inundated.

**Event selection.** The project's original urban-flash-flood target failed repeatedly: the 20 April 2026 pass showed no coherent flood signal; the 31 May 2025 ensemble detected no urban flood water (High class 0% urban); the 18 May 2023 candidate failed its pre-registered gate (no coherent urban flood, optical water decreased, two SAR orbits disagreed). Independently, the Copernicus Global Flood Monitoring (GFM) product returns all-nodata over urban Guwahati (its exclusion mask covers built-up areas), confirming that C-band SAR cannot delineate urban flood here. The riverine flood is large (90.84 km² of new dark water between 11 and 23 June), persistent, and dark — detectable and validatable. This is the documented, pre-registered pivot (ADR-20).

**Event context.** The June 2023 floods began after a period of heavy monsoon rainfall around 14 June and spread across Assam through late June [@floodlist2023assam]. By 21 June, disaster authorities reported 119,830 people affected across 20 districts — principally Baksa (26,571), Lakhimpur (25,096), Nalbari (44,707) and Tamulpur (15,610) — with more than 30 relief camps housing 2,091 people; North Lakhimpur recorded 164 mm of rain in 24 h to 15 June [@floodlist2023assam]. The Central Water Commission reported rivers above the danger mark in at least six locations by 22 June [@cwc2023]. In Kamrup, the NRSC/ISRO satellite flood map of 29 June 2023 mapped major inundation of 10,195 ha in Kamrup Rural and 946 ha in Kamrup Metro [@asdma_nrsc2023]. This is the event captured by the Sentinel-1 pair (11 and 23 June) and the Sentinel-2 scene (25 June) used in this study.

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

**M2 flood-mask ensemble.** Four core methods are applied, plus two alternative thresholding methods evaluated for the ensemble:
1. Global Otsu on post-event VV (threshold −12.55 dB).
2. Global Otsu on post-event VH (threshold −17.31 dB).
3. VV change detection: post − pre < −3.0 dB.
4. Local adaptive threshold: post VV < local mean − 1.5 × local std (51 px window).
5. Kittler–Illingworth minimum-error threshold (post VV, −14.02 dB).
6. Two-component Gaussian-mixture threshold (post VV, −10.27 dB).

Each mask is cleaned with a 3×3 opening/closing, small components (<100 px) are removed, and permanent water and slopes >10° are masked. Pairwise Cohen's kappa: Otsu VV–VH 0.849; Otsu vs change 0.76–0.79; Kittler/GMM vs the three core methods 0.80–0.83; adaptive vs the others only 0.06–0.08.

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
| Kittler–Illingworth | −14.02 dB | 97.78 | 0.775 |
| GMM (2-component) | −10.27 dB | 145.87 | 0.801 |

**Agreement confidence map.** Evidence: `outputs/tables/confidence_classes.csv`, `outputs/maps/confidence/agreement_classes.tif`.

| Class | k | Area (km²) | Observed precision |
|---|---|---|---|
| Dry | 0–1 | 604.76 | 4.9% |
| Low | 2 | 33.93 | 82.9% |
| Medium | 3 | 84.77 | 88.6% |
| High | 4 | 3.91 | 77.1% |

> The table above is the *original* 4-method ensemble (with adaptive) and is the diagnostic that motivated the revision. The **adopted final** confidence rule uses GMM in place of adaptive (ADR-23); its reliability is monotonic (see "Key finding" below).

**Binary flood map (k ≥ 2, 122.59 km²).** Evidence: `outputs/tables/metrics_flood_binary.csv`. Precision 86.6%, recall 76.1%, F1 0.810, IoU 0.680, overall accuracy 93.8%. The adopted GMM-based ensemble yields a marginally better F1 of 0.8138 (recall 80.2%; see "Refined conclusion" below).

**Key finding (H1 rejected, then refined).** The 4-method reliability curve is non-monotonic: Medium (3/4) precision 88.6% > Low 82.9% > High 77.1%. H1 ("High-class precision exceeds Low-class precision") is **rejected** for the 4-method ensemble. The adaptive method (κ ≈ 0.06–0.08 vs the others) is a poor ensemble member: it is extremely conservative (5.63 km², 2.7% recall) and its false positives concentrate in the darkest pixels that the other methods also flag, so requiring all four to agree removes true water without removing false positives. Dropping the adaptive member restores monotonicity: the 3-method ensemble gives **high 88.4% > medium 82.6% > low 43.2%** — High (3/3) is now the most precise class — while the binary flood map is unchanged (F1 0.8094 vs 0.8097). Evidence: `outputs/tables/metrics_by_class.csv`, `outputs/tables/sensitivity_drop_adaptive.csv`, `outputs/figures/reliability_curve.png`; ADR-21, ADR-22.

**Refined conclusion (alternative 4th member).** Replacing the adaptive member with a stronger classical method keeps four votes *and* restores monotonicity. Kittler–Illingworth (precision 92.5%, κ 0.803) and GMM (recall 81.5%, κ 0.829) both correlate strongly with the three good methods. The resulting 4-method ensembles are monotonic — Kittler: High 91.1% > Medium 88.5% > Low 56.1%; GMM: High 88.4% > Medium 83.7% > Low 45.6% — and GMM yields the best binary flood map (F1 0.8138, recall 80.2%). A leave-one-out ablation confirms the finding: dropping any of the three good methods breaks monotonicity and lowers F1, while only dropping adaptive is benign. Conclusion: **agreement predicts reliability when ensemble members genuinely measure the same signal (κ ≈ 0.8); it fails when a member is uncorrelated and low-recall (adaptive, κ ≈ 0.06).** Evidence: `outputs/tables/candidate_members.csv`, `ensemble_4th_member.csv`, `leave_one_out.csv`, `outputs/figures/alternative_members_reliability.png`; ADR-23.

---

## 9. Failure Analysis

The project's most informative results are its failures, recorded here rather than hidden.

**1. Urban flash floods (20 Apr 2026, 31 May 2025, 18 May 2023).** All three failed the pre-registered gate: the flood signal in built-up terrain is too small, transient, and shallow to appear as a coherent dark/change target in C-band SAR. The 18 May 2023 case is the cleanest diagnostic — two same-orbit SAR pairs disagreed on the changed pixels (urban-change Jaccard 0.06), and optical water *decreased* between 16 and 21 May. The operational Copernicus GFM product independently confirms this: its flood layers are all-nodata over urban Guwahati because its exclusion mask covers built-up areas.

**2. The adaptive ensemble member.** Its pairwise kappa against the other methods is ≈ 0.06 (effectively random agreement) and its recall is 2.7%. It contributed a vote uncorrelated with the true water signal, which is why requiring all four methods to agree produced a High-confidence class that was *less* precise than Medium.

**3. Leave-one-out sensitivity.** Dropping any one of the three "good" methods (Otsu VV, Otsu VH, change) breaks monotonicity *and* lowers F1 (to 0.69 / 0.68 / 0.80), whereas dropping only adaptive is benign. This confirms the ensemble's accuracy rests on the three correlated methods, and that a single weak member is the source of the failure.

These cases demonstrate the central sensitivity of C-band flood mapping to event type, size, acquisition timing, and ensemble composition.

---

## 10. Limitations

1. **Reference, not truth.** Sentinel-2 MNDWI is a proxy; turbid water, wet soil, and cloud shadow can be misclassified. No field survey was conducted.
2. **Temporal offset.** The Sentinel-2 reference (25 June) is 2 days after the Sentinel-1 post (23 June); the flood is dynamic, so some pixels changed between acquisitions.
3. **Cloud cover.** The Sentinel-2 scene is 33%/52% cloud per tile (clear fraction 0.771 over the domain), so validation covers only clear pixels.
4. **Single event and AOI.** All results come from one riverine event in one location; generalisation to other floods and seasons is untested.
5. **Pre/post spacing.** The SAR pair is 12 days apart (11 and 23 June); the change-detection method therefore reflects net change over a long window, not the event alone.
6. **Classical methods only.** No deep-learning or polarimetric methods were used; the adaptive method's weakness is a documented limitation of simple local statistics in heterogeneous terrain.
7. **No depth or hydrology.** The maps are extents, not depths, and no hydraulic model was applied.

---

## 11. Future Work

1. **Bootstrap confidence intervals** on all metrics (the pipeline config already specifies block bootstrap, n = 1000).
2. **Stratified manual sample** (~300 points across confidence classes and terrain) as a second, independent reference alongside MNDWI.
3. **Generalise the ensemble-design principle** — formalise "member quality" (kappa against the others, recall) and select or re-weight members accordingly.
4. **Multi-pass persistence** — require water to persist across consecutive acquisitions to reduce speckle false positives.
5. **Depth estimation** (e.g., FwDET) from the flood extent and DEM.
6. **Extend to other Assam flood events and seasons** to test whether the monotonic reliability result generalises.
7. **Revisit urban flood** with higher-resolution or polarimetric SAR, now that the C-band limitation is characterised.

---

## References

See `report/references/references.bib`. All citations in IEEE style via Pandoc `--citeproc`.

---

## Appendix

- `report/decisions.md` — engineering decision log (ADRs)
- `report/claims_ledger.md` — claim-to-evidence ledger
- `report/WORKLOG.md` — dated build log
- `data/manifest.json` — dataset provenance and checksums

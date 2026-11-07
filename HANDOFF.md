# DIVP Project — Complete Handoff / Working Context

**Last updated:** 4 November 2026
**Working directory:** `D:\DIVP PROJECT`
**Status:** Execution started 4 Nov 2026. Event pivoted to 31 May 2025 on 5 Nov 2026 after the 20 Apr 2026 pass failed the flood-signal gate (ADR-16). 2-week frozen core scope; living draft in `report/`.

---

## 0. How to use this file

Feed this file back to the assistant at the start of the next session.
It contains every decision, verified data point, scope boundary, report outline, and open item discussed so far.

**Execution view (read first):** `report/PROGRESS.md` is the living save point. It lists the step-by-step tracker, the current step, the next actions, and the session log. `HANDOFF.md` is the context behind it.

**Step-by-step notebooks:** `notebooks/` contains cell-split views of the long pipeline scripts (`00_data_acquisition`, `01_event_signal_gate`, `02_build_stack`, `03_flood_masks`). The `.py` scripts in `code/` remain the canonical CLI.

**Next action after reading:** follow `report/PROGRESS.md` §1 — Step 9, the agreement confidence map. Do not fabricate results.

---

## 1. Project snapshot

| Item | Value |
|---|---|
| Course context | Digital Image Processing / DIVP project, ECE |
| Students | Garima Devi (240101007), Pritom Sarma (240101013) — project partners |
| Institution | Electronics and Communication Engineering, GUIST, Gauhati University |
| Project type | Proposal/synopsis first, then implementation, then final report |
| Chosen scope | Flood confidence mini-project (pothole/hazard deferred to future work) |
| Chosen toolchain | Python + ESA SNAP |
| Study area | Guwahati / Kamrup Metropolitan, Assam; Bharalu basin focus |
| Study event | 31 May 2025 Guwahati flood (pivoted from 19–20 Apr 2026 after gate failure) |
| Report format | Markdown first, then PDF via Pandoc + XeLaTeX, also DOCX if needed |
| Citation style | IEEE |
| Target length | 20–30 pages |
| Results policy | No invented numbers. Expected results are framed as hypotheses and validation design. |

---

## 2. Source material already reviewed

### 2.1 The PDF

`E:\Good DIP project ideas.pdf` — 29 pages.

It is a chronological design conversation, not a fixed specification. It contains three successive versions:

| Version | Scope | Status |
|---|---|---|
| V1 | Assam district flood map with per-pixel confidence from multi-method agreement | Foundation |
| V2 | Guwahati / Bharalu urban version with risk flags and ward health ranking | Refined |
| V3 | Combined post-flood road condition intelligence: flood confidence + optical enhancement + pothole detection + hazard ranking | Final direction |

### 2.2 The seven papers

Location: `E:\DIVP project_\DIVP project\`

| File | Topic |
|---|---|
| `Paper1.pdf` | Stark, adaptive image contrast enhancement using generalizations of histogram equalization |
| `Paper2.pdf` | Kim et al., spatially adaptive histogram equalization with temporal filtering |
| `Paper3 (post flood).pdf` | Comparison of image enhancement techniques for rapid processing of post-flood images |
| `Paper4.pdf` | Image enhancement methods for remote sensing: a survey |
| `Paper5(Image dehazing).pdf` | Review of remote sensing image dehazing |
| `Paper6(Histogram equal tech for contrast enhancement).pdf` | Histogram equalization techniques for contrast enhancement |
| `Paper7(flood inundation mapping).pdf` | Flood inundation mapping |

### 2.3 Important caveats inherited from the PDF

- The research gaps were found from abstracts and search results, not from reading every paper in full. They must be verified against 5–8 full papers.
- The health-risk index used proxies, not real Assam disease-case data. It is a prioritisation aid, not a disease prediction.
- Any numbers marked "example" in the earlier PDF are placeholders and must not be reused.
- The reference list needs checking and reformatting in IEEE style.
- Satellites cannot see potholes. Sentinel-1 pixels are about 10 m; potholes are 0.3–1 m. Pothole detection must use street-level imagery.
- Image enhancement does not add information and cannot measure flood depth. Enhancement is only for optical display/analysis, never before SAR thresholding.
- SAR is unreliable in urban, vegetated, and sloping terrain because of double bounce, layover, and shadow.
- Mapillary coverage in Guwahati is unverified. The pothole module needs a fallback to RDD2022-only.
- Urban Xray drain data was simulated. Treat any overlay as a demonstration only unless real drain data is supplied.

---

## 3. Locked decisions

| Decision | Choice | Reason |
|---|---|---|
| Scope | Core + hazard | Strong portfolio, still feasible in 12–14 weeks |
| Toolchain | Python + ESA SNAP | Classical DIP pipeline; SNAP is standard for SAR preprocessing |
| Event | 19–20 April 2026 | Best confirmed data package, recent, severe, not the May 2025 event already in the PDF |
| Report type | Proposal/synopsis | Experiments are not done yet |
| Report format | Markdown first | Easy to edit, then convert with Pandoc |
| Length | 20–30 pages | Full project report standard |
| Health-risk ranking | Future-work subsection only | PDF recommends cutting it if time is short |
| Enhancement and depth | Optional add-on chapters | Core project works without them |
| Pothole module | RDD2022 → Mapillary Guwahati test | Satellite cannot see potholes |
| SAR products | SNAP-processed GRD as main, RTC as cross-check | RTC is already calibrated and terrain-corrected |
| SAR processing order | RTC primary; SNAP/GRD cross-check | RTC already calibrated/terrain-corrected; avoids SNAP install as a week-1 blocker |
| Execution mode | Report track + data/code track in parallel | Report consumes verified facts without waiting for results |
| Completion target | 2-week core scope; pothole/hazard/health deferred to future work | Revised 4 Nov 2026 |

---

## 4. Study area and event

### 4.1 Area

Guwahati / Kamrup Metropolitan, Assam. Focus on the Bharalu basin and the urban wards that flood repeatedly.

Approximate bounding box used for data checks:

```
W = 91.68, S = 26.10, E = 91.85, N = 26.22
```

Bharalu basin context:
- Bharalu is the main storm-water conduit for central Guwahati.
- It originates as the Basistha in the Khasi Hills, enters the city as the Bahini, merges with the Bharalu, and drains into the Brahmaputra at Bharalumukh.
- The riverbed averages about 48.8 m and the banks about 49.5 m, leaving little elevation difference and limiting discharge.
- Sluice gates at Bharalumukh must close when the Brahmaputra rises above about 45 m, forcing reliance on pumps.
- About 90% of dry-season flow is sewage.
- A 50 mm/hour downpour can generate about 550,000 m³ of runoff; the existing Bharalu capacity would need over 30 hours to drain it.
- Guwahati's urban flooding is mainly a drainage failure, not a Brahmaputra overflow.

### 4.2 Event: 19–20 April 2026 (superseded)

> **Pivot note (5 Nov 2026):** The 20 Apr 2026 pass failed the flood-signal gate: no coherent urban flood-like area (0.066 km^2 after cleaning; 0.02% urban dark). The active event is now **31 May 2025** (S1 RTC 21 May / 2 June 2025, DESC rel 77; S2 9 June 2025). See ADR-16 and `report/DRAFT_REPORT.md` §4. The April material below is retained as a documented negative result.

Official and reported facts to verify before final submission:

| Fact | Value | Source |
|---|---|---|
| Rainfall at Guwahati A/P | 117.4 mm | ASDMA press release, 20 April 2026 |
| Rainfall at Guwahati City ARG | 126.5 mm | ASDMA press release, 20 April 2026 |
| Rainfall at Gauhati University | 134 mm | ASDMA press release, 20 April 2026 |
| Rainfall at SIRD Complex, Khanapara | 215.9 mm | ASDMA press release, 20 April 2026 |
| Rainfall at AAU-HRS | 119.5 mm | ASDMA press release, 20 April 2026 |
| People affected | about 16,000 (8,500 male, 4,700 female, 2,700 children) | Sentinel Assam, 21 April 2026 |
| Fatalities | ASDMA reported one during the immediate period; later press reports cite five | Verify before final report |
| Record context | 117.4 mm broke the April record after 22 years | Assam Tribune, 20 April 2026 |
| Affected localities | Anil Nagar, Nabin Nagar, Lachit Nagar, Rajgarh, Hatigaon, Sijubari, Teteliya, Jalukbari, Rukminigaon, Kamakhya Nagar | Press reports |

Event description:
- Intense pre-monsoon rainfall on the night of 19–20 April 2026.
- Several parts of Kamrup Metro recorded over 100 mm within two to three hours.
- Widespread urban flash flooding, road submergence, power cuts, and rescue operations.
- This was a drainage-driven urban flood, not a Brahmaputra flood.

### 4.3 Confirmed data availability for April 2026

Checked against the public Planetary Computer STAC catalog.

| Dataset | Item / result | Notes |
|---|---|---|
| Sentinel-1 GRD pre-event | `S1A_IW_GRDH_1SDV_20260408T115658_20260408T115723_063988_080CD1` | Ascending, relative orbit 41, 11:57 UTC |
| Sentinel-1 GRD post-event | `S1A_IW_GRDH_1SDV_20260420T115658_20260420T115723_064163_08135B` | Ascending, relative orbit 41, 11:57 UTC |
| Sentinel-1 RTC pre-event | `..._20260408T115658_..._063988_080CD1_rtc` | Calibrated and terrain-corrected |
| Sentinel-1 RTC post-event | `..._20260420T115658_..._064163_08135B_rtc` | Calibrated and terrain-corrected |
| Sentinel-2 post-event | `S2B_MSIL2A_20260420T042659_R133_T46RCP_20260420T062527` | 40.2% cloud, tile 46RCP, 04:26 UTC |
| Sentinel-2 pre-event | 2026-04-07 scene | 27.3% cloud |
| Copernicus DEM 30 m | `Copernicus_DSM_COG_10_N26_00_E091_00_DEM` | Elevation and slope |
| JRC Global Surface Water | `90E_30Nv1_3_2020` | Permanent water mask |
| ESA WorldCover 10 m | `ESA_WorldCover_10m_2021_v200_N24E090` | Urban and vegetation masks |
| IO LULC 9-class | `46R-2022` | Alternative land-cover mask |

Why April 2026 is the best choice:
- Same-orbit Sentinel-1 pair, 12 days apart, so change detection is clean.
- RTC products exist for both dates, reducing SNAP preprocessing risk.
- Sentinel-2 post-event scene is usable with cloud masking at 40.2% cloud.
- Pre-monsoon optical conditions are better than the May or September monsoon events.
- Official ASDMA rainfall and impact data exist.
- It is not the May 2025 event already used in the PDF.

Caveats to state in the report:
- The pre-event image is 12 days earlier, not the previous day.
- The post-event pass is at 17:27 IST on 20 April, so some flash water may already have drained.
- The 27 April descending pass can provide a recession/persistence check, but it is a different orbit.
- Sentinel-2 is 40.2% cloud; validation must mask clouds and report clear-pixel coverage.
- The death toll differs between immediate ASDMA reporting and later press reports; verify and cite carefully.

### 4.4 Fallback event: 31 May 2025

Use only if April 2026 proves unusable.

| Item | Value |
|---|---|
| Event | 31 May 2025, record 111 mm in 24 hours, highest in nearly 70 years |
| Sentinel-1 ASC pair | 19 May 2025 and 31 May 2025 |
| Sentinel-1 DESC pair | 26 May 2025 and 2 June 2025 |
| Sentinel-2 | 9 June 2025, about 21–31% cloud |
| Official reference | NER-DRR/NESAC flood inundation map for Guwahati, 19–20 May 2025, about 720.06 ha inundated |
| Caveat | The NER-DRR map is itself Sentinel-1-derived, so using it as ground truth is partly circular |

---

## 5. Project definition

### 5.1 Title

**Confidence-Aware Urban Flood Mapping and Post-Flood Road Hazard Prioritisation for Guwahati Using Sentinel-1 SAR and Street-Level Imagery**

### 5.2 Aim

Design and evaluate a Sentinel-1 SAR image-processing pipeline that outputs, for Guwahati, a flood map with per-pixel confidence and a road-hazard priority layer, and test whether the confidence layer actually predicts map accuracy.

### 5.3 Objectives

1. Build at least four independent flood masks from the same Sentinel-1 pair using different methods and speckle filters.
2. Combine the masks into a per-pixel confidence map with High, Medium, Low, and Dry classes.
3. Add risk flags for urban, vegetated, sloping, and layover/shadow zones.
4. Validate the flood map and confidence classes against Sentinel-2 and official references, reporting precision, recall, F1, IoU, and overall accuracy per class.
5. Train a pothole detector on RDD2022 India and test its domain gap on Guwahati street-level images.
6. Rank road segments by flood confidence, pre-flood damage density, drain proximity, and health-facility access.

### 5.4 Research questions

- RQ1: Does multi-method agreement produce a confidence layer that predicts per-pixel flood-map accuracy in Guwahati?
- RQ2: Which SAR flood-mapping method is most reliable in dense urban terrain?
- RQ3: How much does a pothole detector trained on RDD2022 degrade on Guwahati street imagery?
- RQ4: How sensitive is the road-hazard ranking to the choice of weights?

### 5.5 Core hypothesis

**H1:** High-confidence pixels have significantly higher precision than low-confidence pixels. If this is not observed, the negative result is still a valid finding and must be reported honestly.

### 5.6 Scope and non-goals

In scope:
- Sentinel-1 flood extent and confidence
- Urban/vegetation/slope risk flags
- Sentinel-2-based validation
- RDD2022 → Mapillary pothole domain-gap test
- OSM-based road hazard ranking
- Optional enhancement comparison and FwDET depth

Out of scope:
- Real-time flood early warning
- Pothole detection from satellite
- Flood depth from histogram equalization or HSV
- Disease prediction
- Hydrological or hydraulic modelling
- Replacing ground surveys
- Claiming vehicle-safe depth thresholds

### 5.7 Contributions

1. A per-pixel confidence layer for Guwahati flood maps, built from multi-method and multi-filter agreement.
2. An empirical test of whether that confidence layer predicts accuracy.
3. A street-level pothole domain-gap study: RDD2022 plains data versus wet, hilly Guwahati imagery.
4. A transparent road-hazard prioritisation layer that combines flood confidence, road damage, drains, and health access.

---

## 6. System architecture

| Module | Function | Output |
|---|---|---|
| M0 Feasibility | Verify event, data, reference maps, Mapillary coverage | Go/no-go memo |
| M1 Data and preprocessing | S1 GRD/RTC, S2, DEM, JRC water, land cover, OSM | Analysis-ready stack on a common 10 m grid |
| M2 Flood mask ensemble | Otsu, local adaptive, change detection, optional classifier; Lee/median/Gaussian variants | 4+ independent flood masks |
| M3 Confidence and risk flags | Agreement count, confidence classes, urban/vegetation/slope/layover masks | Confidence GeoTIFF |
| M4 Validation | Compare with Sentinel-2 MNDWI and official references; metrics by class; calibration | Tables, calibration curve, error map |
| M5 Street-level damage | Train YOLO on RDD2022 India; test/fine-tune on Mapillary Guwahati images | Pothole detector and domain-gap results |
| M6 Hazard prioritisation | OSM road segments × confidence × damage × drains × health access | Ranked road map and table |
| M7 Optional | Enhancement study, FwDET depth, persistence, health index | Add-on report chapter |

Data flow:

```
S1 pre/post + S2 + DEM + land cover + OSM
        |
        v
M1 preprocessing and co-registration
        |
        v
M2 flood mask ensemble
        |
        v
M3 confidence + risk flags --------> M4 validation
        |                                   |
        v                                   v
M5 pothole detector -------------> M6 hazard prioritisation
                                            |
                                            v
                                  ranked road map + priority table
```

---

## 7. Methodology detail

### 7.1 Preprocessing

Sentinel-1 GRD with SNAP:
- Apply orbit file.
- Radiometric calibration to sigma0.
- Speckle filtering: Lee, Refined Lee, median, Gaussian.
- Terrain correction using Range-Doppler.
- Convert to dB.
- Subset to the Guwahati/Bharalu AOI.
- Co-register pre and post images to the same grid.

Sentinel-1 RTC:
- Use as a cross-check for the GRD pipeline.
- Already calibrated and terrain-corrected.
- Apply the same speckle filters for fair comparison.

Sentinel-2:
- Cloud and cloud-shadow masking using the SCL band.
- Resample to 10 m.
- Compute MNDWI and NDWI.
- Optional: convert to CIELAB and enhance only the lightness channel for display/analysis, never before SAR thresholding.

DEM:
- Elevation and slope.
- Optional HAND (Height Above Nearest Drainage).

### 7.2 Flood mask ensemble

1. Global Otsu threshold on VV dB.
2. Local adaptive threshold using a moving window (window Otsu or Sauvola).
3. Change detection: post-minus-pre difference and post/pre ratio on VV and VH.
4. Optional supervised classifier: Random Forest or SVM with VV, VH, VV−VH, GLCM texture, DEM, and slope.
5. Repeat under Lee, median, and Gaussian filters to measure mask stability.

Post-processing:
- Morphological opening and closing.
- Remove small connected components.
- Mask permanent water using JRC Global Surface Water.
- Mask steep slopes and high elevations using the DEM.
- Mask layover and shadow zones where possible.

### 7.3 Confidence map

- For each pixel, count how many independent methods call it flooded: k out of N.
- Proposed classes:
  - High: k = N
  - Medium: k = N − 1
  - Low: k ≤ N − 2 and k ≥ 2
  - Dry: k ≤ 1
- Optional weighted confidence: weight methods by their validation performance.
- Report class definitions and sensitivity to the threshold choices.

### 7.4 Risk flags

- Urban mask from ESA WorldCover or IO LULC.
- Vegetation mask from ESA WorldCover.
- Slope mask from Copernicus DEM, for example slope > 10°.
- Layover and shadow mask from SNAP or approximate using local incidence angle.
- Permanent water mask from JRC.
- Optional: distance to drains, roads, and health facilities.

### 7.5 Validation

Reference data:
- Sentinel-2 MNDWI from 20 April 2026, cloud-masked, clear patches only.
- ASDMA and NER-DRR reports and maps where available.
- Manual visual interpretation of high-resolution optical imagery.
- May 2025 NER-DRR map only as a methodological benchmark, not as the same-event truth.

Metrics:
- Precision, recall, F1, IoU, overall accuracy per confidence class.
- Calibration curve: confidence class versus observed precision.
- Monotonicity test: precision should increase with confidence.
- Bootstrap confidence intervals.
- Error map showing where the map fails.
- Explicit date-gap analysis.

Baselines:
- Fixed threshold only.
- Global Otsu only.
- Change detection only.
- Majority-vote ensemble without confidence classes.

### 7.6 Pothole module

Training:
- RDD2022 India subset, pothole class D40.
- YOLOv8 or YOLOv11, small/nano model.
- Train on Google Colab if no local GPU.

Test:
- Mapillary images for Guwahati, downloaded via API.
- Bounding-box queries must be smaller than 0.01 degrees square, so tile the AOI.
- Download metadata first, then 50–100 sharp road-surface images.
- Label potholes in CVAT or Roboflow using the RDD2022 pothole class.
- Report F1 on RDD2022 validation versus Guwahati test set. That drop is the domain-gap result.
- Optional: fine-tune on a small Guwahati training split and compare.

Integration:
- Snap detections to the nearest OSM road segment.
- Feed detection density into the pre-flood damage layer.

Fallback:
- If Mapillary coverage is poor, use RDD2022 India only and state the limitation clearly.

### 7.7 Hazard prioritisation

Road segments:
- Download OSM road network for Guwahati.
- Segment roads into manageable lengths.

Features per segment:
- Mean and maximum flood confidence.
- Flooded fraction of the segment.
- Pre-flood pothole density from Mapillary-based detection.
- Distance to nearest open drain or manhole, if data exists.
- Distance to nearest health facility from OSM.
- Optional population exposure from GHSL or WorldPop.

Score:
- Normalise each feature to 0–1.
- Weighted sum: flood confidence, damage density, drain proximity, health access.
- Classes: Avoid, Caution, Likely passable.
- Sensitivity analysis: equal weights, expert weights, and PCA-derived weights.
- State clearly that this is a prioritisation aid, not a measured hazard map.

### 7.8 Optional modules

Enhancement comparison:
- HE, local HE, CLAHE, and gamma in CIELAB, enhancing only the lightness channel.
- Metrics: BRISQUE, entropy, runtime.
- Use FloodNet for flooded-road segmentation and report IoU with and without enhancement.
- Never apply enhancement to SAR before thresholding.

FwDET depth:
- Use the best available DEM, preferably better than 30 m.
- Report depth as bands with uncertainty, not exact values.
- Note that Guwahati's fragmented urban flooding increases uncertainty.

Persistence:
- Use multiple Sentinel-1 passes around the event.
- Report a coarse persistence indicator only, because Guwahati waterlogging is short and passes are days apart.

Health-risk index:
- Future work subsection only.
- Would combine flood duration, confidence, population, and health-facility access.
- No disease-case data; must be labelled a proxy prioritisation aid.

---

## 8. Report v1 outline

Target: 20–30 pages, proposal/synopsis, no fabricated results.

| Section | Content |
|---|---|
| Front matter | Title, synopsis label, author, department, institution, date, placeholders for roll number and supervisor |
| Abstract | Problem, gap, proposed pipeline, expected contribution, about 250 words |
| 1. Introduction | Guwahati flooding, Bharalu basin, why binary maps fail, SAR role and limits |
| 2. Problem statement | P1–P5 and a formal problem statement box |
| 3. Aim and objectives | Aim, O1–O6, RQ1–RQ4, H1 |
| 4. Literature review and gap | SAR flood mapping in Assam, uncertainty, urban SAR limits, road damage, enhancement; G1–G4 tagged verified/to-verify |
| 5. Study area and event | Bharalu basin, 19–20 April 2026 rainfall and impacts, why this event |
| 6. Data | Table with exact STAC IDs, resolution, date, purpose, licence |
| 7. Methodology | M1–M6 and optional modules, with equations for Otsu, change detection, agreement confidence, and hazard score |
| 8. Implementation plan | SNAP graphs, Python modules, repo layout, parameters, reproducibility |
| 9. Validation design | Baselines, ablations, metrics, statistical tests, domain-gap design, sensitivity analysis |
| 10. Expected results and deliverables | Qualitative expectations, figure/table list, deliverables |
| 11. Timeline | 12–14 week Gantt-style table and milestones |
| 12. Risks and mitigation | Data, cloud, urban SAR, Mapillary coverage, compute, scope, reference mismatch, licensing |
| 13. Limitations and ethics | Proxy hazard, no ground truth, Mapillary privacy, licensing, Urban Xray simulated-data caveat |
| 14. Conclusion and future work | Summary, health index, time series, deep learning, field validation |
| 15. References | 25–35 verified sources, IEEE style |
| Appendix | SNAP graph outline, module list, data manifest, glossary |

Suggested figures:
1. Study area map with Bharalu basin and wards.
2. Event timeline with rainfall and Sentinel-1/2 acquisition times.
3. System architecture M1–M6.
4. Flood mask ensemble and confidence classes.
5. Validation calibration curve schematic.
6. Hazard scoring workflow.
7. Gantt chart.

Suggested tables:
1. Problem statement P1–P5.
2. Literature gap G1–G4 with verification status.
3. Data manifest with STAC IDs.
4. Method and filter combinations.
5. Validation metrics by confidence class.
6. Domain-gap results.
7. Hazard weights and sensitivity.
8. Timeline.
9. Risks and mitigation.

---

## 9. Execution plan and timeline

| Phase | Duration | Work | Gate |
|---|---|---|---|
| 0 | 1 week | Install SNAP and Python environment; verify data; read 5–8 full papers; confirm gap | Go/no-go memo and dataset manifest |
| 1 | 2 weeks | Download and preprocess S1/S2/DEM; baseline Otsu flood map | Baseline map |
| 2 | 2 weeks | Add methods and filters; build confidence map and risk flags | Confidence GeoTIFF |
| 3 | 1–2 weeks | Validate against Sentinel-2 and references; calibration analysis | Metrics by class |
| 4 | 2 weeks | Train RDD2022 pothole detector; build Mapillary Guwahati test set | Domain-gap F1 |
| 5 | 2 weeks | Build OSM road hazard layer and priority ranking | Priority map and table |
| 6 | 1–2 weeks | Optional enhancement, FwDET, persistence experiments | Add-on results |
| 7 | 2 weeks | Final report, slides, demo, viva preparation | Submission package |

Total: 12–14 weeks.

Report writing sequence:
1. Front matter, abstract, introduction, problem statement, aims.
2. Literature and gap with verified references.
3. Study area, event, and data manifest.
4. Methodology, implementation, validation design.
5. Timeline, risks, limitations, conclusion.
6. Figures and tables.
7. Convert to PDF/DOCX.
8. Check page count, citations, and that no results are invented.

---

## 10. Environment status

Checked on 29 October 2026.

| Item | Status |
|---|---|
| Working directory | `D:\DIVP PROJECT` exists and is empty |
| Source PDF | `E:\Good DIP project ideas.pdf` |
| Papers | `E:\DIVP project_\DIVP project\` |
| Python | Anaconda Python at `E:\Anaconda\anaconda3\python.exe` |
| Python packages present | numpy, scikit-image, OpenCV, scipy, matplotlib, pandas, streamlit |
| Python packages missing | rasterio, geopandas, shapely, ultralytics, snapista, folium, osgeo/gdal, earthengine-api |
| SNAP | Not installed |
| SNAP install target | `D:` recommended, 83.1 GB free |
| `C:` drive | Only 0.2 GB free — do not install there |
| GPU | No NVIDIA GPU detected |
| CPU / RAM | Intel Core i5-12500H, 16 GB RAM |
| Pandoc | Installed at `E:\Anaconda\anaconda3\Scripts\pandoc.exe` |
| LaTeX | MiKTeX installed: pdflatex, xelatex, lualatex |
| Report conversion path | Markdown → Pandoc → XeLaTeX → PDF; also DOCX |

Implications:
- Install ESA SNAP on `D:` and add `snap`, `gpt` to PATH.
- Create a Python virtual environment on `D:` and install the missing geospatial and YOLO packages.
- Train YOLO on Google Colab because there is no local NVIDIA GPU.
- Keep SNAP processing to a subset AOI to stay within 16 GB RAM.

---

## 11. Proposed repo and file structure

```
D:\DIVP PROJECT\
  HANDOFF.md
  report\
    PROGRESS.md          # step-by-step save point (read first)
    WORKLOG.md
    DRAFT_REPORT.md
    decisions.md
    claims_ledger.md
    Report_v1.md
    Report_v1.pdf
    Report_v1.docx
    figures\
    references\
      references.md
      references.bib
  data\
    raw\
      sentinel1\
      sentinel2\
      dem\
      landcover\
      reference\
    processed\
    labels\
      mapillary_guwahati\
  code\
    config\
      config.yaml
    preprocessing\
      s1_snap_graph.xml
      run_snap.py
      preprocess_s2.py
    flood_masks\
      otsu.py
      local_threshold.py
      change_detection.py
      ensemble.py
    confidence\
      agreement.py
      risk_flags.py
    validation\
      metrics.py
      calibration.py
    pothole\
      train_yolo.py
      mapillary_download.py
      evaluate_domain_gap.py
    hazard\
      road_segments.py
      score.py
      sensitivity.py
    visualization\
      maps.py
  notebooks\
    00_data_acquisition.ipynb
    01_event_signal_gate.ipynb
    02_build_stack.ipynb
    03_flood_masks.ipynb
    04_confidence_agreement.ipynb   # next step
  outputs\
    maps\
    tables\
    figures\
  requirements.txt
  README.md
```

---

## 12. Data and software stack

### 12.1 Data

| Dataset | Source | Purpose |
|---|---|---|
| Sentinel-1 GRD VV/VH | Copernicus Data Space / Planetary Computer / GEE | Main SAR input |
| Sentinel-1 RTC | Planetary Computer | Preprocessed cross-check |
| Sentinel-2 L2A | Copernicus Data Space / Planetary Computer | Optical validation, MNDWI |
| Copernicus DEM 30 m | Planetary Computer / Copernicus | Slope and elevation masks |
| JRC Global Surface Water | Planetary Computer / GEE | Permanent water mask |
| ESA WorldCover 10 m | Planetary Computer | Urban and vegetation masks |
| IO LULC 9-class | Planetary Computer | Alternative land cover |
| NRSC / Bhuvan flood layers | NRSC / Bhuvan | Reference comparison |
| ASDMA / NER-DRR reports | ASDMA, NER-DRR | Event and impact reference |
| OSM roads and health facilities | OpenStreetMap / Geofabrik | Road network and access |
| Mapillary | Mapillary API | Guwahati street-level images |
| RDD2022 | Kaggle / figshare / Roboflow | Pothole detector training |
| FloodNet / RescueNet | Public datasets | Flooded-road segmentation benchmark |

### 12.2 Software

- ESA SNAP and `gpt` / `snapista` for SAR preprocessing.
- Python 3.10+ with numpy, scipy, scikit-image, OpenCV, rasterio, geopandas, shapely, pyproj, rioxarray, xarray, matplotlib, pandas, folium, streamlit, ultralytics, jupyter.
- Google Earth Engine optional for quick data access.
- QGIS optional for map checking.
- CVAT or Roboflow for labeling.
- Google Colab for YOLO training.
- Pandoc + MiKTeX for report conversion.

---

## 13. Risks and limitations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Sentinel-2 cloudy on validation date | High | Medium | Use cloud masking, clear patches, ASDMA/NER-DRR references, report coverage |
| SAR urban double bounce and mixed pixels | High | High | Confidence layer and risk flags are the core response; report honestly |
| Flash flood water recedes before SAR pass | Medium | High | Use multiple passes; report timing limitation; focus on map reliability |
| Mapillary coverage poor in Guwahati | Medium | Medium | Fallback to RDD2022 India only; state limitation |
| Reference map date mismatch | High | Medium | Quantify date gap; use multiple references; avoid overclaiming |
| Scope creep across four modules | High | High | Tiered scope; core first; optional modules last |
| No local GPU | Certain | Medium | Train YOLO on Colab; use nano/small model |
| SNAP installation or Java issues | Medium | Medium | Use Sentinel-1 RTC from Planetary Computer as fallback |
| Licensing and attribution | Medium | Medium | Credit Copernicus, Mapillary, RDD2022, OSM; check terms |
| Death-toll and impact figures vary | Medium | Low | Cite sources and dates; avoid definitive claims |

Limitations to state explicitly:
- The hazard score is a prioritisation aid, not a measured hazard map.
- There is no ground-truth post-flood road survey.
- Sentinel-1 resolution is too coarse for potholes.
- Enhancement does not add information and cannot measure depth.
- The health-risk idea uses proxies, not disease cases.
- Urban Xray drain data is simulated unless real data is supplied.
- Results may show weak or negative confidence calibration; that is still a valid finding.

---

## 14. Defaults and open items

Defaults that will be used unless changed:
- Author line: Garima Devi (240101007) and Pritom Sarma (240101013), Electronics and Communication Engineering, GUIST, Gauhati University.
- Citation style: IEEE.
- Health-risk ranking: brief future-work subsection.
- Pothole module: RDD2022 → Mapillary, with RDD2022-only fallback.
- Sentinel-1: SNAP GRD main, RTC cross-check.
- Report language: academic English, third person, no fabricated numbers.

Open items to confirm:
1. Supervisor name for the title page (roll numbers resolved).
2. Exact institution and department line.
3. Any college report template, font, margin, certificate, or declaration page.
4. Whether the health-risk section should be a full subsection or only future work.
5. Mapillary API token and whether Guwahati coverage is sufficient.
6. Permission and location for installing ESA SNAP on `D:`.
7. Whether real Urban Xray drain data is available or only simulated data.
8. Final decision on including the enhancement and FwDET optional chapters.

---

## 15. Reference shortlist to verify and cite

Core project and event:
1. NER-DRR / NESAC, Flood Inundation Mapping of Guwahati Metropolitan Area, May 2025.
2. ASDMA press release, heavy rainfall over Guwahati, 20 April 2026.
3. Assam Tribune, "117.4 mm rain breaks April record in Guwahati after 22 years, paralyses city", 20 April 2026.
4. Sentinel Assam, "Urban flooding hits nearly 16,000 in Guwahati: ASDMA", 21 April 2026.
5. Assam Tribune, "Urban flooding in Guwahati: a disaster engineered by neglect", 6 May 2026.
6. ASDMA, Review of Studies on Urban Floods in Guwahati, 2016.
7. NRSC, Flood Hazard Zonation Atlas of Assam using multi-sensor satellite data, 1998–2023.

SAR and flood mapping:
8. UN-SPIDER, recommended practice for flood mapping with Sentinel-1.
9. ESA SNAP flood mapping tutorial.
10. Sentinel-1 flood mapping studies for Assam and the Brahmaputra.
11. Urban flood SAR review noting uncertainty analysis as future work.
12. Sen1Floods11 dataset and paper.
13. DeepSARFlood paper.
14. FwDET and FwDET v2.0 papers.
15. JRC Global Surface Water paper.
16. Copernicus DEM documentation.
17. ESA WorldCover product paper.

Image enhancement:
18. Stark, Adaptive Image Contrast Enhancement Using Generalizations of Histogram Equalization, 2000.
19. Kim et al., Contrast Enhancement System Using Spatially Adaptive Histogram Equalization with Temporal Filtering, 1998.
20. Harichandana et al., Comparison of Image Enhancement Techniques for Rapid Processing of Post Flood Images.
21. Kaplan et al., Image Enhancement Methods for Remote Sensing: A Survey.
22. Liu et al., A Review of Remote Sensing Image Dehazing, 2021.

Road damage and datasets:
23. RDD2022 dataset and CRDDC 2022 paper.
24. FloodNet dataset paper.
25. RescueNet dataset paper.
26. Mapillary API documentation and attribution terms.
27. OpenStreetMap and OSMnx documentation.

Health context, only if used:
28. Assam University 2026 flood report.
29. ICMR post-flood disease warning for Assam.
30. Study of healthcare access in flood-prone Assam villages.
31. GHSL or WorldPop population data documentation.

Verification rule:
- Cite only sources that have been opened and checked.
- Mark any unverified claim as "to verify" in the draft.
- Reformat all references in IEEE style.

---

## 16. Tomorrow's first actions

1. Toggle off plan mode so file writing is allowed.
2. Create `D:\DIVP PROJECT\report\` and `report\references\`.
3. Write `Report_v1.md` with front matter, abstract, introduction, problem statement, and aims.
4. Write the literature and gap section with verified references and explicit to-verify tags.
5. Write the study area, event, and data manifest with the confirmed STAC IDs.
6. Write methodology, implementation, and validation design.
7. Write timeline, risks, limitations, conclusion.
8. Add figures and tables.
9. Convert to PDF with Pandoc + XeLaTeX and to DOCX if needed.
10. Check page count, citation format, and that no results are fabricated.

Definition of done for Report v1:
- 20–30 pages.
- All sections present.
- 25–35 verified references in IEEE style.
- 5–7 figures or tables.
- No invented numbers.
- Explicit assumptions, limitations, and data caveats.

---

## 17. Copy-paste prompt for the next session

```
Read D:\DIVP PROJECT\HANDOFF.md carefully.

We are building the project described there:
"Confidence-Aware Urban Flood Mapping and Post-Flood Road Hazard Prioritisation for Guwahati Using Sentinel-1 SAR and Street-Level Imagery."

Locked decisions:
- Scope: flood confidence + road hazard prioritisation.
- Toolchain: Python + ESA SNAP.
- Event: 19-20 April 2026, Guwahati / Bharalu basin.
- Deliverable now: Report v1, a 20-30 page proposal/synopsis in Markdown, then PDF/DOCX.
- Citation style: IEEE.
- No fabricated results. Expected results must be framed as hypotheses and validation design.
- Health-risk ranking is future work only.
- Potholes come from street-level imagery, never from satellite.
- Enhancement must never be applied to SAR before thresholding.

First task:
Create D:\DIVP PROJECT\report\Report_v1.md with the full outline in Section 8 of the handoff.
Start with front matter, abstract, introduction, problem statement, aim and objectives.
Then continue section by section.
Use the confirmed Sentinel-1/2 item IDs and event facts from the handoff.
Mark unverified claims as [To verify].
Do not invent accuracy numbers or results.

After the Markdown is complete, convert it to PDF with Pandoc + XeLaTeX and also produce a DOCX.
```

---

## 18. Session log — 4 November 2026

### 18.1 Newly locked decisions

- **RTC-first.** Use Planetary Computer Sentinel-1 RTC as the primary input. Install SNAP/GRD only as a cross-check and for layover/shadow if time allows.
- **Parallel tracks.** Write `Report_v1.md` and build the data/code pipeline at the same time. The report uses only verified facts; results are framed as hypotheses or `[To verify]`.
- **Complete the full scope.** Do not cut modules for speed. Cut only if a hard external deadline forces it, and record the reason.
- **Environment on `D:`.** C: has 0.2 GB free; all envs, caches, TEMP, TMP, pip, matplotlib, and torch caches must live on D:.

### 18.2 Verified on 4 Nov 2026

Data (all confirmed against the Planetary Computer STAC API):

| Item | Result |
|---|---|
| S1 GRD pre `...20260408T115658...063988_080CD1` | 200 OK |
| S1 GRD post `...20260420T115658...064163_08135B` | 200 OK |
| S1 RTC items (suffix `_rtc`) | 200 OK; assets are only `vv`, `vh`, plus `tilejson`, `rendered_preview` |
| S1 RTC layover/shadow mask asset | **Does not exist**; must be computed or approximated from DEM |
| S2 post `S2B_MSIL2A_20260420T042659_R133_T46RCP...` | 200 OK; cloud 40.23% |
| Copernicus DEM `...N26_00_E091_00_DEM` | 200 OK |
| ESA WorldCover `...N24E090` | 200 OK, 10 m, uint8 |

Environment:

| Item | Status |
|---|---|
| Python packages present | numpy, scipy, scikit-image, OpenCV, sklearn, torch (CPU), xarray, matplotlib, pandas, streamlit, yaml |
| Python packages missing | rasterio, geopandas, shapely, pyproj, rioxarray, osmnx, rasterstats, ultralytics, pystac-client, planetary-computer, stackstac, folium, osgeo |
| GPU | None; `torch.cuda.is_available() = False` |
| Disk | C: 0.2 GB free, D: 83.2 GB free, E: 54.8 GB free |
| Java | Present (`D:\bin\java.exe`) |
| SNAP / `gpt` | Not installed |
| Pandoc / MiKTeX | Present |
| AOI size | ~0.17° × 0.12° ≈ 226 km² ≈ 2.3 M pixels at 10 m |

Key implication: the AOI is small enough to process in a single Python process. Compute and tiling are not the bottleneck; data plumbing, validation design, and honest reporting are.

### 18.3 Revised two-track execution plan

Track A — Report (starts day 1):

| Step | Output | Gate |
|---|---|---|
| A1 | Repo + report skeleton + `references.bib` + IEEE CSL | Day 1 |
| A2 | Front matter, abstract, intro, P1–P5, aim/objectives/RQs/H1 | Day 2 |
| A3 | Literature matrix (7 papers + 25–35 refs) → review + gaps G1–G4 | Day 4 |
| A4 | Study area, event, data manifest with confirmed STAC IDs | Day 5 |
| A5 | Methodology M1–M7 with equations | Week 2 |
| A6 | Validation design, expected results as hypotheses, figure/table list | Week 3 |
| A7 | Timeline, risks, limitations, ethics, conclusion, appendix | Week 3 |
| A8 | Pandoc → PDF + DOCX; page count, citations, no-fabrication audit | Week 4 |

Track B — Data and code (RTC-first):

| Phase | Work | Output |
|---|---|---|
| B0 (days 1–2) | `uv` venv on D:, redirect caches/TEMP, git init, `config.yaml`, STAC manifest with SHA256 | Env + `manifest.json` |
| B0 gate | Visual check of 20 Apr RTC for a real Bharalu water signal | Go / pivot to 31 May 2025 |
| B1 (week 1) | 10 m EPSG:32646 grid, pre/post co-registration, dB, one Otsu mask, first metric | Baseline map |
| B2 (weeks 2–4) | Ensemble (Otsu, Sauvola, VV change, VH ratio, optional RF) × speckle variants; κ analysis; confidence classes; risk flags | Confidence GeoTIFF |
| B3 (weeks 5–6) | S2 MNDWI + stratified manual sample; per-class metrics; reliability/ECE/Brier/AUROC; block bootstrap; logistic covariates | Validation tables + calibration curve |
| B4 (weeks 7–8) | YOLO11n on RDD2022 India (Colab); Mapillary metadata → 50–100 labeled images; domain-gap F1 | Domain-gap result |
| B5 (weeks 9–10) | OSMnx edges; 10 m point-sampled zonal stats; Monte Carlo weight sensitivity | Ranked road map + table |
| B6 (weeks 11–12) | Optional: enhancement (CIELAB lightness only), FwDET, persistence | Add-on chapter |
| B7 (weeks 13–14) | Final report, slides, Streamlit demo, viva prep | Submission package |

### 18.4 Engineering decisions

| Area | Decision | Reason |
|---|---|---|
| Environment | `uv` venv on `D:` + pinned lockfile | Fast, avoids C: space, GDAL wheels work on Windows |
| SAR input | RTC primary; GRD/SNAP cross-check | Removes SNAP install from the critical path |
| Data access | pystac-client + planetary-computer + rioxarray windowed COG reads | No full-scene downloads; reproducible manifest |
| Compute | Single process, numpy/xarray; no Dask/tiling | AOI is only ~2.3 M pixels |
| Validation | Calibration metrics + spatial block bootstrap | Makes RQ1 statistically defensible |
| Pothole | YOLO11n, Colab, model pre-annotation then human correction | No local GPU; fast labeling |
| Hazard | Point-sampled zonal stats + Monte Carlo weight draws | Fast and more rigorous than polygon overlays |
| Repro | `config.yaml`, manifest SHA256, fixed seeds, pytest on metrics | Regenerable figures and auditable results |
| Report | Markdown + `references.bib` + `--citeproc` + IEEE CSL + claims ledger | Enforces no fabricated numbers |

### 18.5 High-leverage techniques

- Report pairwise Cohen's κ among masks; drop near-duplicate methods before building agreement confidence.
- Treat RQ1 as a calibration problem: reliability diagram, ECE, Brier, AUROC, Spearman monotonicity.
- Test `correct ~ confidence_class + urban + slope + vegetation` with logistic regression to show confidence adds information beyond terrain.
- Use 500 m spatial block bootstrap for confidence intervals, not i.i.d. bootstrap.
- Build validation labels from a stratified manual sample allocated by confidence class and terrain; report clear-pixel coverage separately.
- Use Monte Carlo Dirichlet weight draws (10k) for hazard-rank stability instead of three arbitrary weight sets.
- Generate every report figure and table from scripts, never by hand.

### 18.6 Go/no-go gate

Before committing the report's event/data section: visually inspect the 20 Apr 2026 RTC over the Bharalu basin. If the flash water had already drained before the 17:27 IST pass and no usable signal exists, pivot to the 31 May 2025 fallback event.

### 18.7 Fallbacks

- SNAP fails → RTC-only, document the limitation.
- Mapillary coverage poor → RDD2022-only domain-gap study.
- S2 too cloudy → clear-patch validation + official references, report coverage.
- No local GPU → train YOLO on Colab.
- Post-event water absent → pivot to 31 May 2025.

### 18.8 Definition of done

- Report 20–30 pages, 25–35 verified IEEE references, 7 figures / 9 tables, no placeholders except explicit `[To verify]`.
- Core flood-confidence pipeline reproduces the map and calibration metrics from the manifest.
- Pothole domain-gap and road-hazard ranking completed, with limitations stated.
- PDF + DOCX + slides + Streamlit demo.
- Repo reproducible from the lockfile and `data/manifest.json`.

### 18.9 Open items still needed

1. Roll number, supervisor name, exact institution/department line.
2. College report template (fonts, margins, certificate/declaration pages).
3. Mapillary developer token.
4. Permission/location to install SNAP on `D:` for the GRD cross-check.
5. Whether real Urban Xray drain data exists or only simulated data.

### 18.10 Tomorrow's first actions (supersedes §16)

1. Toggle off plan mode.
2. Apply this handoff update.
3. Create the `uv` environment and repo skeleton on `D:`.
4. Write the STAC manifest script and fetch windowed RTC subsets.
5. Run the 20 Apr water-signal go/no-go check.
6. Open `report/Report_v1.md` and start front matter, abstract, and introduction in parallel.

### 18.11 Copy-paste prompt for the next session (supersedes §17)

```
Read D:\DIVP PROJECT\HANDOFF.md carefully, especially Section 18.

We are executing the two-track plan:
- Track A: write report/Report_v1.md (20-30 pages, IEEE, no fabricated results).
- Track B: build the RTC-first flood-confidence pipeline on D:.

Locked:
- RTC primary; SNAP/GRD only as cross-check.
- Report and code work in parallel.
- Full scope; no cuts unless a hard external deadline forces it.
- All envs/caches on D:, never C:.

Start with:
1. Create the uv environment and repo skeleton on D:.
2. Write the STAC manifest and fetch windowed RTC subsets.
3. Run the 20 Apr water-signal go/no-go check.
4. In parallel, open Report_v1.md and draft front matter, abstract, introduction.
```

---

## 19. Session log — 5 November 2026 (supersedes §18.10)

### 19.1 What changed today

- **Day 1:** repo skeleton, `D:` venv, pinned environment, governance files (`DRAFT_REPORT.md`, `WORKLOG.md`, `decisions.md`, `claims_ledger.md`, `references.bib`), `config.yaml`.
- **Day 2:** STAC manifest + windowed AOI subsets (RTC/S2/DEM/JRC/WorldCover); common `EPSG:32646` 10 m grid (1713 x 1346 px = 230.57 km^2, 100% valid); SHA256 manifest.
- **Day 3:** the 20 Apr 2026 event **failed** the flood-signal gate: cleaned flood-like area 0.066 km^2; urban dark 0.02%. Pivoted to the fallback.
- **Fallback check:** 19–20 May 2025 had 1.151 km^2 and S2 on 20 May is ~100% cloud; 31 May 2025 had 2.357 km^2 and S2 on 9 Jun is 21–31% cloud. **31 May 2025 selected.**
- **Pivot executed:** main data refetched for 31 May 2025:
  - S1 RTC pre: 21 May 2025 23:47 UTC, DESC rel orbit 77.
  - S1 RTC post: 2 June 2025 23:47 UTC, DESC rel orbit 77.
  - S2 reference: 9 June 2025, T46RCQ + T46RCP.
  - Gate passes: 2.357 km^2 cleaned flood-like; non-permanent SAR–S2 separation 0.753.
- **Analysis-ready stack built:** Lee 7×7 on linear power (4 looks) → dB; slope; permanent-water, urban, vegetation masks.
- **Four flood masks built:** Otsu VV, Otsu VH, change VV, adaptive VV (local mean − 1.5σ, 51 px).
- **Provisional mask results:**
  - Otsu VV: 9.492 km^2, threshold −10.65 dB.
  - Otsu VH: 9.348 km^2, threshold −17.98 dB.
  - Change VV: 4.141 km^2, threshold −3.0 dB.
  - Adaptive VV: 0.424 km^2, median local threshold −8.85 dB.
  - Kappa: Otsu VV–VH 0.946 (redundant); change vs Otsu 0.54–0.56; adaptive vs others 0.04–0.07.

### 19.2 Current state

- **Code:** `code/preprocessing/` (manifest, fetch, build stack, gate, candidate checks); `code/flood_masks/run_masks.py`.
- **Outputs:** `outputs/maps/masks/*.tif`, `outputs/tables/mask_stats.csv`, `mask_kappa.csv`, `outputs/figures/masks_overview.png`, `day3_gate_zoom.png`, `negative_april2026_gate.*`.
- **Report:** `report/DRAFT_REPORT.md` now describes the 31 May event, implemented methodology, and provisional mask diagnostics. `WORKLOG.md`, `decisions.md` (ADR-16/17/18), `claims_ledger.md` updated.
- **Git:** commits up to `e86bd23`; the Day 3 stack/masks/docs update is the next commit.

### 19.3 Tomorrow's first actions

1. Build the agreement confidence map (`code/confidence/agreement.py`): k/N classes (High 4/4, Medium 3/4, Low 2/4, Dry 0–1/4), save GeoTIFF + class stats + figure.
2. Decide whether to keep both Otsu variants or replace Otsu VH with VH change detection, given kappa 0.946. Record the decision in `decisions.md`.
3. Start validation: Sentinel-2 MNDWI (9 Jun) on clear pixels + a stratified manual sample; compute precision/recall/F1/IoU/overall accuracy/kappa per method and per confidence class; reliability curve.
4. Update the draft report's Results with confidence/validation numbers, each with a claims-ledger row.
5. Commit and push the Day 3 work; keep the April gate as a documented negative result.

### 19.4 Open issues

- Urban SAR signal is weak (0.09% urban dark on 31 May); report as a finding, not a bug.
- Adaptive mask is conservative (0.424 km^2); consider k=1.2 or another local method if it is too sparse.
- Sentinel-2 is 9 days after the event; the manual sample is the primary event-water reference.
- Supervisor name and report template are still `[To verify]`.

---

## 20. Session log — 6 November 2026 (workflow restructuring)

### 20.1 What changed

- Added `report/PROGRESS.md` as the **living save point**: step tracker, current step, next actions, session log. Read this first in future sessions; `HANDOFF.md` stays the full context.
- Added `notebooks/` with cell-by-cell views of the long pipeline scripts:
  - `00_data_acquisition.ipynb` (stac_manifest + fetch_subsets + check_coverage)
  - `01_event_signal_gate.ipynb` (day3_gate + candidate_events + candidate_s2)
  - `02_build_stack.ipynb` (build_stack)
  - `03_flood_masks.ipynb` (run_masks)
- The `.py` scripts were **not changed and not removed**; they remain the canonical CLI.
- Added `notebooks/README.md` (conventions + how to run).

### 20.2 Why

- Make the work visible step by step instead of one opaque internal run.
- Persist the working state in files because opencode session persistence is not available yet.
- Keep the notebooks and scripts in sync: two views, one source of truth.

### 20.3 Current state after this session

- No data, mask, or result files were changed.
- Notebooks validate as JSON and parse as Python.
- Jupyter/ipykernel are **not installed** in `.venv`; see `report/PROGRESS.md` §4 for the install command.
- Current step is still **Step 9 — agreement confidence map**.

### 20.4 Next actions (supersedes §19.3)

1. Create `code/confidence/agreement.py` and mirror it in `notebooks/04_confidence_agreement.ipynb`.
2. Build the k/N confidence classes and save GeoTIFF + class stats + figure.
3. Record the Otsu VV/VH redundancy decision (κ = 0.946) in `decisions.md`.
4. Move to validation (Step 11), then update `DRAFT_REPORT.md` and `claims_ledger.md`.
5. Commit Day 3–4 work; update `report/PROGRESS.md` after each step.

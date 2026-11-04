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

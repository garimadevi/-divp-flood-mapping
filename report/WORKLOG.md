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

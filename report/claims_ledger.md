# Claims Ledger

Every quantitative claim in the report must have a row here. A claim without evidence does not go into the report.
Status values: `planned`, `verified`, `rejected`.

| ID | Claim (short) | Evidence (script / figure / table / citation) | Status |
|---|---|---|---|
| C-001 | Sentinel-1 RTC pre/post pair acquired for the AOI | `data/manifest.json` (items + SHA256) | verified |
| C-002 | Study AOI is 1713 x 1346 px at 10 m = 230.57 km^2 | `outputs/tables/day2_coverage.csv`; `code/preprocessing/check_coverage.py` | verified |
| C-003 | Number of flood masks built and their parameters | `outputs/tables/method_parameters.csv` | planned |
| C-004 | Pairwise Cohen's kappa between masks | `outputs/tables/kappa_matrix.csv` | planned |
| C-005 | High-class precision exceeds Low-class precision (H1) | `outputs/tables/calibration.csv` + CI table | planned |
| C-006 | Per-method precision/recall/F1/IoU/OA | `outputs/tables/metrics_by_method.csv` | planned |
| C-007 | Per-confidence-class precision | `outputs/tables/metrics_by_class.csv` | planned |
| C-008 | Clear-pixel coverage of Sentinel-2 reference | `outputs/tables/s2_coverage.csv` | planned |
| C-009 | Flood extent with and without permanent-water masking | `outputs/tables/flood_extent.csv` | planned |
| C-010 | Runtime and peak memory of the pipeline | `outputs/tables/runtime.csv` | planned |
| C-011 | All input layers share EPSG:32646 at 10 m and are 100% valid | `outputs/tables/day2_coverage.csv` | verified |
| D-001 | 20 Apr 2026 has no coherent urban flood signal (8.1% change but scattered; 0.066 km^2 cleaned flood-like; 0.02% urban dark) | `outputs/tables/day3_gate_stats.csv`; `outputs/figures/day3_gate_zoom.png` | verified (diagnostic) |
| D-002 | 31 May 2025 candidate has 2.357 km^2 cleaned flood-like area vs 1.151 km^2 for 19-20 May 2025 | `outputs/tables/candidate_gate.csv`; `outputs/figures/candidate_may19.png`, `candidate_may31.png` | verified (diagnostic) |
| D-003 | 31 May S2 (9 Jun 2025) has 21-31% cloud; SAR dark16 overlaps S2 water 77.9% vs 1.2% non-water | `outputs/tables/candidate_may31_s2.csv`; `outputs/figures/candidate_may31_s2.png` | verified (diagnostic) |

**Rule:** if a row cannot be filled with a real path or citation, the claim is removed or tagged `[To verify]`.

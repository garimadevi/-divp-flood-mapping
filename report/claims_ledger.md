# Claims Ledger

Every quantitative claim in the report must have a row here. A claim without evidence does not go into the report.
Status values: `planned`, `verified`, `rejected`.

| ID | Claim (short) | Evidence (script / figure / table / citation) | Status |
|---|---|---|---|
| C-001 | Sentinel-1 RTC pre/post pair acquired for the AOI | `data/manifest.json` | planned |
| C-002 | Study AOI area in km^2 and pixel count at 10 m | `code/preprocessing/aoi_stats.py` output | planned |
| C-003 | Number of flood masks built and their parameters | `outputs/tables/method_parameters.csv` | planned |
| C-004 | Pairwise Cohen's kappa between masks | `outputs/tables/kappa_matrix.csv` | planned |
| C-005 | High-class precision exceeds Low-class precision (H1) | `outputs/tables/calibration.csv` + CI table | planned |
| C-006 | Per-method precision/recall/F1/IoU/OA | `outputs/tables/metrics_by_method.csv` | planned |
| C-007 | Per-confidence-class precision | `outputs/tables/metrics_by_class.csv` | planned |
| C-008 | Clear-pixel coverage of Sentinel-2 reference | `outputs/tables/s2_coverage.csv` | planned |
| C-009 | Flood extent with and without permanent-water masking | `outputs/tables/flood_extent.csv` | planned |
| C-010 | Runtime and peak memory of the pipeline | `outputs/tables/runtime.csv` | planned |

**Rule:** if a row cannot be filled with a real path or citation, the claim is removed or tagged `[To verify]`.

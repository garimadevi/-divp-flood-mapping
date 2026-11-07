# DIVP Mini-Project — Guwahati Flood Confidence Mapping

**Title:** Multi-Method Urban Flood Segmentation and Agreement-Based Confidence Estimation Using Sentinel-1 SAR Imagery

**Authors:** Garima Devi (240101007), Pritom Sarma (240101013) — ECE, GUIST, Gauhati University

## What this project does

Processes a Sentinel-1 RTC pair (21 May 2025 pre-event, 2 June 2025 post-event) over Guwahati / the Bharalu basin with several independent flood-segmentation methods, combines them into an agreement-based confidence map (High / Medium / Low / Dry), and tests whether higher agreement corresponds to higher classification accuracy.

## Status

Step 9 of the execution plan: the 31 May 2025 event passes the signal gate, the analysis-ready stack is built, and four flood masks + kappa diagnostics are done. The 20 Apr 2026 event is retained as a documented negative result. Agreement confidence and validation are next.

**Read `report/PROGRESS.md` first** — it is the step-by-step save point.

## Layout

```
report/       PROGRESS.md (save point), living draft, work log, ADRs, claims ledger, references
data/         raw and processed data (large files not committed)
code/         config, preprocessing, flood masks, confidence, validation
notebooks/    cell-by-cell views of the long pipeline scripts
outputs/      generated maps, tables, figures
app/          Streamlit demo
```

## Environment

- Python venv at `.venv/` on `D:` (never install on `C:`)
- Parameters live in `code/config/config.yaml`
- Caches and TEMP/TMP on `D:` under `.cache/`

## Reproduce

```powershell
.\.venv\Scripts\Activate.ps1
python code\preprocessing\stac_manifest.py
python code\preprocessing\fetch_subsets.py
python code\preprocessing\check_coverage.py
python code\preprocessing\build_stack.py
python code\flood_masks\run_masks.py
```

Or run the matching notebooks in `notebooks/` cell by cell (see `notebooks/README.md`).

## Rules

- No fabricated results: every number maps to a script output and a `report/claims_ledger.md` row.
- Unverified facts are tagged `[To verify]`.
- Engineering decisions are recorded in `report/decisions.md`.

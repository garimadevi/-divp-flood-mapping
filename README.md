# DIVP Mini-Project — Guwahati Flood Confidence Mapping

**Title:** Multi-Method Urban Flood Segmentation and Agreement-Based Confidence Estimation Using Sentinel-1 SAR Imagery

**Authors:** Garima Devi (240101007), Pritom Sarma (240101013) — ECE, GUIST, Gauhati University

## What this project does

Processes a Sentinel-1 RTC pair (8 April 2026 pre-event, 20 April 2026 post-event) over Guwahati / the Bharalu basin with several independent flood-segmentation methods, combines them into an agreement-based confidence map (High / Medium / Low / Dry), and tests whether higher agreement corresponds to higher classification accuracy.

## Status

Day 3 gate failed for 20 Apr 2026. Candidate check recommends the 31 May 2025 event (2.36 km^2 coherent signal, usable S2; 19-20 May has less signal and ~100% cloud). Awaiting confirmation to reconfigure. No flood results yet.

## Layout

```
report/       living draft, work log, ADRs, claims ledger, references
data/         raw and processed data (large files not committed)
code/         config, preprocessing, flood masks, confidence, validation
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
python code\preprocessing\fetch_manifest.py
python code\preprocessing\preprocess.py
```

## Rules

- No fabricated results: every number maps to a script output and a `report/claims_ledger.md` row.
- Unverified facts are tagged `[To verify]`.
- Engineering decisions are recorded in `report/decisions.md`.

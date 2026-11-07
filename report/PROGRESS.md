# Step-by-Step Progress & Save File

**Last updated:** 7 November 2026 (Day 5)
**Project:** Confidence-Aware Flood Mapping — Guwahati / Brahmaputra (riverine pivot, ADR-20)
**Purpose:** This is the living save point. Open this file first. It shows exactly which step we are on, what is done, what is next, and where every artefact lives.

> `HANDOFF.md` holds the full project context; this file holds the **execution path**.
> Notebooks live in `notebooks/`; the original scripts stay in `code/` as the canonical CLI.

---

## 1. Current save point

| Item | Value |
|---|---|
| Current step | **Step 12 — Report results + claims rows** |
| Status | In progress |
| Last completed step | Step 11 — Validation (S2 MNDWI metrics + reliability curve) |
| Event | Brahmaputra riverine flood, 23 June 2023 (pivot from urban, ADR-20) |
| Data | `data/raw/`, `data/processed/`, `data/manifest.json` (wider AOI) |
| Last commit | `c4796be` (stack + four masks, pre-pivot) |
| Uncommitted work | Riverine pivot (config/data/masks/confidence/validation) + ADR-20/21 |

**Next 3 actions**

1. Create `notebooks/04_confidence_agreement.ipynb` and `notebooks/05_validation.ipynb` mirroring `code/confidence/*.py`, and refresh notebooks 00-03 for the new event/AOI.
2. Update `report/DRAFT_REPORT.md` Results/Conclusion with the validated riverine findings (binary flood F1 0.81; H1 rejected — reliability non-monotonic).
3. Fix the notebook-03 base-domain discrepancy (use `base & slope_ok` = 727.4 km²), then commit the pivot.

---

## 2. Step tracker

Status: `[x]` done · `[~]` in progress · `[ ]` pending · `[!]` blocked · `[-]` deliberately skipped

| # | Step | Notebook | Script | Key output | Status |
|---|---|---|---|---|---|
| 0 | Environment, repo skeleton, governance files | — | — | `.venv/`, `report/`, `config.yaml` | [x] |
| 1 | Resolve STAC items, write manifest | `00_data_acquisition` | `preprocessing/stac_manifest.py` | `data/manifest.json` (metadata) | [x] |
| 2 | Fetch windowed AOI subsets (S1/S2/DEM/JRC/WorldCover) | `00_data_acquisition` | `preprocessing/fetch_subsets.py` | `data/raw/`, SHA256 manifest | [x] |
| 3 | Verify common grid and coverage | `00_data_acquisition` | `preprocessing/check_coverage.py` | `outputs/tables/day2_coverage.csv` | [x] |
| 4 | Event gate v1 — 20 Apr 2026 | `01_event_signal_gate` | `preprocessing/day3_gate.py` | `day3_gate_stats.csv`, `day3_gate_zoom.png` | [x] failed → negative result |
| 5 | Candidate gate — 19 May vs 31 May 2025 | `01_event_signal_gate` | `preprocessing/candidate_events.py`, `candidate_s2.py` | `candidate_gate.csv`, `candidate_may31_s2.csv` | [x] |
| 6 | Pivot to 31 May 2025, refetch data | `00_data_acquisition` | `fetch_subsets.py` | new manifest + `data/raw/` | [x] |
| 7 | Analysis-ready stack (Lee → dB, slope, masks) | `02_build_stack` | `preprocessing/build_stack.py` | `data/processed/`, `stack_meta.json` | [x] |
| 8 | Four flood masks + pairwise kappa | `03_flood_masks` | `flood_masks/run_masks.py` | `outputs/maps/masks/`, `mask_stats.csv`, `mask_kappa.csv` | [x] |
| 9 | Agreement confidence map (k/N classes) | `04_confidence_agreement` | `confidence/agreement.py` | confidence GeoTIFF + class stats + figure | [x] |
| 10 | Mask redundancy decision (adaptive κ≈0.06 degrades High) | — | — | ADR-21 in `decisions.md` | [x] |
| 11 | Validation: S2 MNDWI + reliability curve | `05_validation` | `confidence/validate.py` | metrics by method/class, reliability curve | [x] |
| 12 | Report Results update with claims rows | — | — | `DRAFT_REPORT.md`, `claims_ledger.md` | [ ] |
| 13 | Commit + push Day 3–4 work | — | — | clean git state | [ ] |
| 14 | Pothole module (RDD2022 → Mapillary) | `06_pothole` | `pothole/*.py` | domain-gap F1 | [ ] |
| 15 | OSM road-hazard ranking | `07_hazard` | `hazard/*.py` | ranked road map + table | [ ] |
| 16 | Optional: enhancement / FwDET / persistence | `08_optional` | — | add-on chapter | [ ] |
| 17 | Final report + PDF/DOCX + slides + demo | — | — | submission package | [ ] |

> Notebook files are named `notebooks/00_data_acquisition.ipynb`, `notebooks/01_event_signal_gate.ipynb`, etc.
> Steps 4, 5, and 6 are already executed; their notebooks are for reproducing and inspecting the evidence, not for new results.

---

## 3. How to resume a session

1. Read this file (`report/PROGRESS.md`) — it is the save point.
2. Read `report/WORKLOG.md` (last entry) and `report/decisions.md` (latest ADRs).
3. Read `HANDOFF.md` only for the full context and caveats.
4. Open the notebook for the current step and run cells top to bottom.
5. After each step: update this tracker, append to `WORKLOG.md`, add any claim to `claims_ledger.md`, and commit.

**Rules**

- No fabricated numbers. Every number maps to a script/notebook output and a `claims_ledger.md` row.
- Unverified facts stay tagged `[To verify]`.
- The `.py` scripts remain the canonical, reproducible CLI. Notebooks must mirror them, not diverge.
- Do not delete the `.py` file when a notebook exists. Two views, one source of truth.
- Update this file at the end of every working session — this is our temporary substitute for opencode sessions.

---

## 4. Environment note for notebooks

Jupyter + ipykernel are installed in `.venv` and the `divp` kernel is registered (the user ran all notebooks on Day 4). To run the notebooks:

```powershell
.\.venv\Scripts\Activate.ps1
jupyter lab   # or run cells in VS Code with the "Python (DIVP)" kernel
```

---

## 5. Session log (append-only)

### 2026-11-06 — Day 4 — Workflow restructuring (no scientific results)

**Did:** Read `HANDOFF.md` in full. Added a step-by-step execution tracker (`report/PROGRESS.md`), created `notebooks/` with cell-split copies of the long pipeline scripts, and kept every `.py` file unchanged. Added `notebooks/README.md`.
**Why:** Make progress visible step by step, and save the working state in files because opencode session persistence is not available yet.
**Evidence:** `report/PROGRESS.md`, `notebooks/README.md`, `notebooks/*.ipynb`; no data or result files were changed.
**Blockers:** None. Notebook execution needs `jupyter` + `ipykernel` (see §4).
**Next:** Step 9 — agreement confidence map, plus the Otsu redundancy decision.

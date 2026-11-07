# Notebooks — step-by-step view of the pipeline

Each notebook is a **cell-by-cell view** of an existing script in `code/`.
The scripts remain the canonical CLI and are not replaced. Notebooks exist so the
work is visible and runnable step by step.

> **Event (ADR-20):** the pipeline targets the Brahmaputra riverine flood of 23 June 2023
> over the widened AOI `[91.55, 26.00, 91.95, 26.30]`. Notebook `01` is a historical
> record of the (superseded) urban gate; the other notebooks read the current event from
> `code/config/config.yaml`.

| Notebook | Mirrors | What it shows |
|---|---|---|
| `00_data_acquisition.ipynb` | `code/preprocessing/stac_manifest.py`, `fetch_subsets.py`, `check_coverage.py` | Resolve STAC items, build the common grid, fetch AOI subsets, verify coverage |
| `01_event_signal_gate.ipynb` | `code/preprocessing/day3_gate.py`, `candidate_events.py`, `candidate_s2.py` | Historical urban go/no-go gate and candidate comparison (documented negative results) |
| `02_build_stack.ipynb` | `code/preprocessing/build_stack.py` | Lee filter on linear power → dB, slope, permanent-water/urban/vegetation masks |
| `03_flood_masks.ipynb` | `code/flood_masks/run_masks.py` | Four independent flood masks, cleaning, areas, pairwise kappa |
| `04_confidence_agreement.ipynb` | `code/confidence/agreement.py` | Agreement k/N confidence map (High/Medium/Low/Dry) |
| `05_validation.ipynb` | `code/confidence/validate.py` | S2 MNDWI validation: per-method and per-class metrics + reliability curve |
| `06_alternative_members.ipynb` | `code/confidence/alternative_members.py` | Kittler & GMM as 4th member + leave-one-out ablation (ADR-23) |
| `07_validation_visualization.ipynb` | `code/confidence/validation_viz.py` | Cloud removal, MNDWI reference, and the SAR-vs-S2 TP/FP/FN agreement map |
| `08_cross_terrain.ipynb` | `code/confidence/cross_terrain.py` | Cross-terrain threshold generalization (farm vs urban) |
| `09_bootstrap_ci.ipynb` | `code/confidence/bootstrap_ci.py` | Block-bootstrap 95% CIs for metrics + reliability curve |

## Conventions

- The first cell sets the project root and adds `code/preprocessing` to `sys.path`.
- Step cells start with a markdown heading (`## Step N — ...`) so the progress is readable.
- Outputs go to the same paths as the scripts (`outputs/`, `data/processed/`).
- Do not edit a number by hand; rerun the cell that generates it.
- The notebooks are not a second implementation. If logic changes, change the `.py` first, then mirror it.

## Running

```powershell
.\.venv\Scripts\Activate.ps1
# Jupyter + ipykernel are already installed; the "Python (DIVP)" kernel is registered.
# If the kernel is missing, run:
#   pip install jupyter ipykernel
#   python -m ipykernel install --user --name divp --display-name "Python (DIVP)"
```

Open the notebook in VS Code and select the `Python (DIVP)` kernel. Run cells top to bottom.
Data acquisition and gate notebooks need network access to the Planetary Computer.

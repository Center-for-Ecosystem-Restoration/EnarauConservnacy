# Enarau Conservancy — Wildlife Corridor Remote-Sensing Assessment

Remote-sensing analysis repo for the CER-K Enarau Conservancy wildlife-corridor consultancy
(Greater Maasai Mara, Kenya), delivered under the Weeden Foundation "Restoring wildlife corridors
via community-led habitat recovery" grant. Produces an audit-ready evidence package — land-cover
classification, historical land-cover change, vegetation condition/degradation trends, landscape
fragmentation metrics, and circuit-theory connectivity/corridor analysis — across four sites:
Enarau Conservancy, Mbokishi Conservancy (used throughout as the intact reference site),
Corridor Phase 1, and Corridor Phase 2.

Every map, statistic, and conclusion is meant to be traceable to a submitted dataset and a
documented method. This README is the setup guide and at-a-glance map of the repo.

## Stack

- **Python** (`uv`) — Earth Engine analysis via [`eetools`](https://github.com/harrellgis/gee_utils),
  a shared GEE utility library this repo depends on but does not vendor.
- **R** (`renv`) — landscape-fragmentation metrics (`landscapemetrics`) and connectivity modeling.
- **Julia** — a system dependency of the connectivity step (Circuitscape.jl/Omniscape.jl), invoked
  as a subprocess from R rather than through an R package.

## Setup

### 1. Python environment

```bash
uv sync                              # installs dependencies, incl. config.py as an editable package
cp .env.example .env                 # then edit .env -- see "Earth Engine access" below
uv run earthengine authenticate      # once per machine
uv run jupyter lab                   # launch notebooks
```

`uv.lock` pins `eetools` to a specific tagged release of the public
[`gee_utils`](https://github.com/harrellgis/gee_utils) repo (see `[tool.uv.sources]` in
`pyproject.toml`) — `uv sync` fetches it directly from GitHub, so no local checkout of `gee_utils`
is needed on a new machine. `config.py` itself is installed as an editable package by the same
`uv sync` (see `[tool.hatch.build.targets.wheel]` in `pyproject.toml`), so every notebook can do a
plain `import config` regardless of its own location or the Jupyter kernel's working directory.

### 2. Earth Engine access

`.env` is gitignored; `.env.example` is the versioned template. Copy it, then set:

```
EE_PROJECT=<your-gcp-project-id>
```

to a Google Cloud project you control with the Earth Engine API enabled. `eetools.initialize()`
(called at the top of every EE notebook) reads this automatically via `python-dotenv`. Run
`uv run earthengine authenticate` once per machine before any EE call will work.

### 3. R environment

```bash
cd scripts/r
Rscript -e "renv::restore()"
```

`renv.lock` pins exact package versions (R 4.5.1, `terra`, `sf`, `landscapemetrics`, `igraph`,
etc.). **`renv` only activates when the R process's working directory is `scripts/r/` itself**
(via `scripts/r/.Rprofile`) — always run scripts as `cd scripts/r && Rscript 0N_script_name.R`,
never from the repo root, or the renv environment silently won't load.

The connectivity scripts (`09_run_omniscape.R`, `10_run_circuitscape.R`) additionally require a
local Julia install with Circuitscape.jl/Omniscape.jl set up via `JuliaCall` — Julia's install
path is machine-specific and **not** managed by `renv`. Update `JULIA_BIN` at the top of
`scripts/r/00_config.R` to point at your own machine's `julia.exe` before running those two
scripts.

### 4. Raw data not in this repo

Two raw inputs are too large to check in and must be supplied separately: the 4-band 1 m Airbus
aerial mosaic, its hand-digitized training-polygon GeoPackage, and a cultivated-area override
GeoPackage, all used only by `hab_class.ipynb`. Update `config.HAB_CLASS_RAW_DIR` in `config.py`
to point at these files' location on your own machine before running that notebook — same
machine-specific convention as `JULIA_BIN` above.

Everything else `scripts/r/` needs for the connectivity analysis is either a small committed
vector already in `data/` (site boundaries, roads/streams/settlements) or a raster generated
in-repo and landing in gitignored `outputs/rasters/connectivity_inputs/` — elevation/slope
(`connectivity_terrain_settlement_inputs.ipynb`, via GEE SRTM), the settlement heatmap (same
notebook, a local KDE with no Earth Engine dependency), and the vegetation-condition composite
(`connectivity_condition_composite.ipynb`). Run those notebooks (and download their Drive exports,
where applicable — see each notebook's own "manual step" cells) before `06_prepare_connectivity_inputs.R`.

## config.py — key variables

`config.py` is the single source of truth for paths, constants, and thresholds; `scripts/r/00_config.R`
mirrors the R-relevant subset by hand (R cannot import a `.py` file — there is no automated drift
check between the two). Notable variables:

| Variable | Purpose |
|---|---|
| `PROJECT_CRS` | `EPSG:32736` (WGS 84 / UTM 36S) — used by every notebook/script in this repo |
| `SITES` / `AOI_PATHS` | The four site boundary GeoJSONs in `data/` and their display names |
| `STUDY_AREA_BUFFER_M` | 150 m buffer applied to the union of all sites for every project-wide export |
| `REFERENCE_SITE_ID` | `"mbokishi"` — the intact site every anomaly/cross-check comparison is relative to |
| `DW_EXPORT_FOLDER`, `EXPORT_FOLDER`, `CONNECTIVITY_CONDITION_EXPORT_FOLDER` | **Google Drive folder names.** Earth Engine batch exports land in these folders inside the Drive account used to authenticate (`earthengine authenticate`) — not GCS, not local disk. Rasters/tables must be manually downloaded from Drive into the matching `outputs/rasters/...` / `outputs/tables/` subfolder before any R script or plotting notebook can read them |
| `DW_HABITAT_THRESHOLDS`, `DW_HABITAT_CLASS_LABELS` | Dynamic World habitat-classification scheme and thresholds (calibrated against the RF classifier) |
| `RF_CLASS_LABELS`, `RF_FINAL_CLASS_LABELS`, `RF_CLASS_REMAP` | The Airbus RF classifier's training vs. delivered class schemas |
| `CONNECTIVITY_INPUT_PATHS` | Raw GIS inputs for the connectivity analysis — vectors (roads/streams/settlements) in `data/`, rasters (elevation/slope/settlement heatmap/condition composite) in `CONNECTIVITY_INPUT_RASTER_DIR` |
| `CONNECTIVITY_INPUT_RASTER_DIR` | `outputs/rasters/connectivity_inputs/` — landing folder for the connectivity analysis's generated raw rasters (too large to commit) |
| `OUTPUT_DIRS` | Local landing directories under `outputs/` (gitignored — regenerated locally, not shipped in the repo) |
| `HAB_CLASS_RAW_DIR` | Machine-specific directory for `hab_class.ipynb`'s raw inputs (Airbus mosaic, training polygons, cultivated-area overrides) — not in `data/`, must be set per machine |

## Notebooks & scripts, at a glance

### Python notebooks — `scripts/python/notebooks/`

| Notebook | Purpose |
|---|---|
| `hab_class.ipynb` | Trains a Random Forest classifier on 4-band, 1 m Airbus imagery and outputs a 1 m (and 10 m-aggregated) land-cover classification map of the study area — the highest-resolution land-cover input in this repo, and the ground-truth layer used to calibrate Dynamic World's thresholds below. |
| `historical_change_detection.ipynb` | Tracks natural-habitat land cover from 2016–2025 using Dynamic World: builds annual/seasonal probability composites, classifies an 8-class habitat scheme, and computes baseline→pre→current transitions. Also exports the connectivity-ready evidence masks Objective 4 consumes. |
| `calibrate_habitat_thresholds.ipynb` | Local (non-Earth-Engine) numpy tool that re-runs `historical_change_detection.ipynb`'s classification logic against the RF classifier's output as ground truth, to iterate on `config.DW_HABITAT_THRESHOLDS` quickly. |
| `productivity_degradation_landtrendr.ipynb` | Builds Landsat (1984–present), HLS (2015–present), and Sentinel-2 (2017–present) vegetation-index time series, plus two independent LandTrendr disturbance/recovery segmentations (dry-season NBR and wet-season MSAVI2), to track vegetation condition and degradation over time. |
| `connectivity_condition_composite.ipynb` | Builds a single recent (2022–2025) vegetation-condition composite (productivity + moisture + inverse bare-soil) feeding the connectivity analysis's condition-adjusted resistance surface. |
| `connectivity_terrain_settlement_inputs.ipynb` | Generates the connectivity analysis's elevation/slope (SRTM via GEE) and settlement-heatmap (local KDE, no Earth Engine) raw inputs in-repo, replacing the originally hand-produced/QGIS versions. |

### Python plotting notebooks — `scripts/python/plotting/`

Pure pandas/matplotlib/seaborn post-processing — no Earth Engine calls. Each reads the CSVs its
corresponding analysis notebook exported to Drive (once manually downloaded into `outputs/tables/`)
and produces the charts in `outputs/plots/`.

| Notebook | Purpose |
|---|---|
| `historical_change_plots.ipynb` | Habitat/pressure composition by period, natural-habitat probability trend, and baseline→current transition-matrix heatmaps, for the Dynamic World analysis. The pressure-composition chart uses uncalibrated thresholds (`config.DW_PRESSURE_THRESHOLDS`, never ground-truth-checked, unlike `DW_HABITAT_THRESHOLDS`) — treat it as preliminary; see `landscape_metrics.ipynb`'s Plots 7-8 and `connectivity_plots.ipynb`'s Plots 1-2 for stronger complementary pressure/threat evidence. |
| `productivity_degradation_plots.ipynb` | Index trend lines, a reference-normalized (site-minus-Mbokishi) anomaly chart, pre-vs-current condition boxplots, LandTrendr disturbance/recovery area comparisons, and CHIRPS rainfall context, for the LandTrendr analysis. |
| `landscape_metrics.ipynb` | Fragmentation-metric trend lines and the metric-correlation heatmap, for the R landscape-metrics analysis below, plus fragmentation-pressure context maps (Objective 3 local edge/patch-density change). |
| `connectivity_plots.ipynb` | Settlement/road pressure maps, barrier/bottleneck candidate areas, graduated habitat-patch importance, and protection/restoration priority areas, for the R connectivity (Objective 4) analysis below. |

### R scripts — `scripts/r/` (run in order, from that directory)

| Script | Purpose |
|---|---|
| `00_config.R` | Shared constants (mirrors `config.py`) — sourced by every script below, never run directly. |
| `01_prepare_inputs.R` | Loads and validates the Dynamic World rasters downloaded from Drive. |
| `02_area_transition_summaries.R` | Tidies Objective 1's own GEE-computed area/transition CSVs into long format plus a net-natural-change-by-site summary. |
| `03_landscape_metrics.R` | Site-level (mask-first) landscape-fragmentation metrics via `landscapemetrics` — PLAND, patch density, largest patch index, edge density, cohesion, and more, on both the full habitat classes and a binary natural-vs-converted raster. |
| `04_moving_window_connectivity.R` | Project-wide (mask-after) moving-window local-connectivity change maps at three radii (250/500/1000 m), flagging pinch-points/improvements between baseline and current. |
| `05_figures_and_exports.R` | Cross-checks Objective 3's net habitat change against Objective 2's LandTrendr disturbance/recovery area, flagging likely regional/rainfall-driven change vs. site-specific change. |
| `06_prepare_connectivity_inputs.R` | Builds the 30 m connectivity master grid and aligns every raw input (land cover, settlements, roads, streams, terrain, vegetation condition) onto it. |
| `07_build_resistance_source_surfaces.R` | Builds land-cover permeability/confidence, human/road pressure, and terrain/riparian layers into three resistance surfaces (Models A/B/C) plus source-strength rasters. |
| `08_habitat_patches_focal_nodes.R` | Delineates core-habitat patches from the RF land-cover map and selects focal nodes per site for the Circuitscape runs below. |
| `09_run_omniscape.R` | Runs Omniscape (moving-window, node-free current flow) across six resistance-model/scale/source-threshold scenarios via a Julia subprocess. |
| `10_run_circuitscape.R` | Runs Circuitscape (pairwise and all-to-one current flow between focal nodes) via a Julia subprocess. |
| `11_consensus_priority_mapping.R` | Combines the Omniscape/Circuitscape outputs into consensus, bottleneck, barrier, protection-priority, and restoration-priority rasters/vectors — the final connectivity deliverables. |
| `R/*.R` | Shared helper functions sourced by the numbered scripts above (I/O, grid alignment, resistance formulas, patch metrics, scoring, etc.) — not run directly. |

## Outputs

`outputs/` is gitignored and generated locally: `outputs/rasters/` (including
`connectivity_inputs/`, the connectivity analysis's raw-raster landing folder), `outputs/tables/`,
`outputs/vectors/`, `outputs/plots/`, and `outputs/connectivity/` (the many-file-per-run
Omniscape/Circuitscape outputs). Most Python notebooks export rasters/tables to Google Drive (see
the export-folder variables above) rather than writing here directly — download those manually
before running any script that reads from `outputs/`; the exception is the settlement heatmap,
which `connectivity_terrain_settlement_inputs.ipynb` writes directly to `outputs/` with no Drive
round-trip.

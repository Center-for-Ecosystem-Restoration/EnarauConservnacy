# Mirrors EnarauConservnacy/config.py -- config.py is the Python source of truth for this repo.
# R cannot `import config.py` (no reticulate in use, by design), so this file must be updated by
# hand whenever config.py's shared constants (PROJECT_CRS, DW_PERIODS, SITES, etc.) change --
# there is no automated drift check.
#
# renv note: this project's renv (scripts/r/renv.lock) only activates when the R process's
# working directory is scripts/r/ itself. Always run scripts as:
#   cd scripts/r && Rscript 01_prepare_inputs.R
# NOT `Rscript scripts/r/01_prepare_inputs.R` from the repo root -- the latter leaves the working
# directory at the repo root (no .Rprofile there), so renv never activates and whatever is on the
# machine's global R library silently runs instead.

find_repo_root <- function() {
  candidates <- c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", ".."))
  for (d in candidates) {
    if (file.exists(file.path(d, "config.py"))) return(normalizePath(d))
  }
  stop(
    "Could not locate EnarauConservancy repo root (config.py not found) from ", getwd(),
    ". Run this script with working directory = scripts/r/ (see renv note above)."
  )
}

REPO_ROOT <- find_repo_root()

#################### FILE PATH HANDLING ####################
DATA_DIR             <- file.path(REPO_ROOT, "data")
OUTPUTS_DIR           <- file.path(REPO_ROOT, "outputs")
RASTER_DIR            <- file.path(OUTPUTS_DIR, "rasters")
PLOTS_DIR             <- file.path(OUTPUTS_DIR, "plots")
TABLES_DIR            <- file.path(OUTPUTS_DIR, "tables")
LANDSCAPE_RASTER_DIR  <- file.path(RASTER_DIR, "landscape_metrics")
DW_INPUT_RASTER_DIR   <- file.path(RASTER_DIR, "dynamic_world")      # manually-downloaded Dynamic World inputs
VECTORS_DIR           <- file.path(OUTPUTS_DIR, "vectors")
RF_CLASSIFIER_DIR     <- file.path(OUTPUTS_DIR, "rf_hab_classifier")  # written by hab_class.ipynb, read-only here

for (d in c(LANDSCAPE_RASTER_DIR, VECTORS_DIR, TABLES_DIR, PLOTS_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

#################### PROJECT-WIDE SETTINGS ####################
PROJECT_CRS <- "EPSG:32736"  # WGS 84 / UTM zone 36S
STUDY_AREA_BUFFER_M <- 150

#################### AOI BOUNDARIES / SITE METADATA ####################
AOI_PATHS <- list(
  enarau      = file.path(DATA_DIR, "enarau_conservancy.geojson"),
  mbokishi    = file.path(DATA_DIR, "mbokishi_conservancy.geojson"),
  corridor_p1 = file.path(DATA_DIR, "phase_1_corridor.geojson"),
  corridor_p2 = file.path(DATA_DIR, "phase_2_corridor.geojson")
)

SITES <- data.frame(
  site_id   = c("enarau", "mbokishi", "corridor_p1", "corridor_p2"),
  site_name = c("Enarau Conservancy", "Mbokishi Conservancy", "Corridor Phase 1", "Corridor Phase 2"),
  path      = unlist(AOI_PATHS, use.names = FALSE),
  stringsAsFactors = FALSE
)

#################### CONNECTIVITY RAW INPUTS ####################
# Mirrors config.py's CONNECTIVITY_INPUT_PATHS. roads/streams/settlements are committed vector
# deliverables in data/; everything else is a generated raster too large to commit, landing in
# CONNECTIVITY_INPUT_RASTER_DIR instead (see connectivity_terrain_settlement_inputs.ipynb and
# connectivity_condition_composite.ipynb). CRS note: roads/streams/settlements needed a UTM-zone
# fix before use (see git history); re-check CRS on any future re-export of these three files.
CONNECTIVITY_INPUT_RASTER_DIR <- file.path(RASTER_DIR, "connectivity_inputs")
CONNECTIVITY_INPUT_PATHS <- list(
  roads                   = file.path(DATA_DIR, "roads.gpkg"),
  streams                 = file.path(DATA_DIR, "streams.gpkg"),
  settlements             = file.path(DATA_DIR, "settlements.gpkg"),
  elevation               = file.path(CONNECTIVITY_INPUT_RASTER_DIR, "elevation.tif"),
  slope                   = file.path(CONNECTIVITY_INPUT_RASTER_DIR, "slope.tif"),
  settlement_heatmap      = file.path(CONNECTIVITY_INPUT_RASTER_DIR, "settlement_heatmap.tif"),
  condition_score_wet     = file.path(CONNECTIVITY_INPUT_RASTER_DIR, "condition_score_wet_2022_2025_project.tif"),
  condition_score_dry     = file.path(CONNECTIVITY_INPUT_RASTER_DIR, "condition_score_dry_2022_2025_project.tif"),
  condition_score_current = file.path(CONNECTIVITY_INPUT_RASTER_DIR, "condition_score_current_2022_2025_project.tif")
)

#################### CONNECTIVITY MASTER GRID ####################
# 30m primary landscape-wide grid, built from project geometry alone (R/grid.R's
# build_master_grid()) -- every connectivity input is aligned onto it via align_to_grid(),
# independent of that input's own native grid/resolution.
CONNECTIVITY_GRID_RESOLUTION_M <- 30
CONNECTIVITY_LANDCOVER_SOURCE_RESOLUTION_M <- 10  # outputs/rf_hab_classifier/*_10m_clipped.tif

CONNECTIVITY_RASTER_DIR <- file.path(RASTER_DIR, "connectivity")
CONNECTIVITY_OUTPUT_DIR <- file.path(OUTPUTS_DIR, "connectivity")
OMNISCAPE_OUTPUT_DIR    <- file.path(CONNECTIVITY_OUTPUT_DIR, "omniscape")
CIRCUITSCAPE_OUTPUT_DIR <- file.path(CONNECTIVITY_OUTPUT_DIR, "circuitscape")
for (d in c(CONNECTIVITY_RASTER_DIR, OMNISCAPE_OUTPUT_DIR, CIRCUITSCAPE_OUTPUT_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

#################### LAND-COVER CLASS SCHEME (Airbus RF classifier) ####################
# Delivered 7-class scheme (Airbus classifier). NOT the same scheme as DW_HABITAT_CLASS_LABELS
# below (different classifier) -- do not mix the two class-ID spaces.
RF_FINAL_CLASS_LABELS <- c(
  `1` = "dense_forest", `2` = "bareground", `3` = "grassland", `4` = "cultivated",
  `5` = "shrubland", `6` = "water", `7` = "built"
)
# Species-agnostic: grassland/shrubland are NOT lower-quality than forest -- all three are "natural".
NATURAL_LC_CLASSES     <- c(1, 3, 5)  # dense_forest, grassland, shrubland
CULTIVATED_LC_CLASSES  <- c(4)
BUILT_LC_CLASSES        <- c(7)
WATER_LC_CLASSES        <- c(6)
BAREGROUND_LC_CLASSES   <- c(2)

# class_id -> class_name mapping BEFORE the cultivated_a/cultivated_b collapse -- used to remap
# accuracy_metrics_pixels.csv (8-class training scheme) onto the 7-class delivered raster.
RF_CLASS_REMAP <- c(`1` = 1, `2` = 2, `3` = 3, `4` = 4, `5` = 4, `6` = 5, `7` = 6, `8` = 7)
RF_ACCURACY_PIXELS_PATH <- file.path(RF_CLASSIFIER_DIR, "accuracy_metrics_pixels.csv")

# Land-cover permeability crosswalk, one value per RF_FINAL_CLASS_LABELS class -- starting values.
LANDCOVER_PERMEABILITY <- c(
  dense_forest = 0.95,
  grassland    = 0.90,
  shrubland    = 0.90,
  cultivated   = 0.35,  # this classifier has no intensive/low-intensity cultivation split
  bareground   = 0.50,
  water        = 0.40,
  built        = 0.02
)

#################### RESISTANCE MODELS A/B/C + SOURCE STRENGTH ####################
RESISTANCE_RMAX <- c(A = 100, B = 150, C = 150)
RESISTANCE_B_WEIGHTS <- c(landcover = 0.60, human = 0.25, road = 0.15)
RESISTANCE_C_WEIGHTS <- c(
  landcover = 0.45, human = 0.20, road = 0.15, condition = 0.10, terrain = 0.05, riparian = 0.05
)
BUILT_FRACTION_RESISTANCE_FLOOR <- list(threshold = 0.50, floor = 150)

# Neutral vs. riparian-facilitation scenario values for the Resistance-C riparian term (step 06 inputs).
RIPARIAN_FACTOR_NEUTRAL <- 0.50
RIPARIAN_FACTOR_FACILITATION <- 0.85  # starting value

SOURCE_THRESHOLD_PRIMARY <- 0.30
SOURCE_CONSERVATIVE_CRITERIA <- list(
  natural_fraction_min = 0.70, settlement_pressure_max = 0.25,
  road_pressure_max = 0.35, condition_score_min = 0.40
)

#################### HABITAT PATCHES + FOCAL NODES ####################
# Deliberately the SAME thresholds as SOURCE_CONSERVATIVE_CRITERIA (0.70/0.25); kept as its own
# constant since the two serve different purposes and could diverge later.
CORE_HABITAT_CRITERIA <- list(
  natural_fraction_min = 0.70, landcover_permeability_min = 0.70, settlement_pressure_max = 0.25
)

# Patch-size tiers -- planning thresholds, not species home-range requirements.
PATCH_TIER_THRESHOLDS_HA <- c(tier1_min = 50, tier2_min = 20, tier3_min = 5)

# Focal-node candidate filter + per-site target counts (starting caps, not exact requirements).
# "external_buffer" has no cap, to avoid artificially bounding the network at the analysis boundary.
FOCAL_NODE_MIN_AREA_HA <- 20
FOCAL_NODE_TARGET_COUNTS <- c(enarau = 3, mbokishi = 3, corridor_p1 = 5, corridor_p2 = 5)

#################### JULIA / CIRCUITSCAPE.JL / OMNISCAPE.JL ####################
# `circuitscaper` (the R package this analysis would normally use) is installed in this renv
# library but NOT USABLE here: R 4.5+ hides a C symbol RCall.jl depends on for its R<->Julia
# embedding (RCall.jl issue #566, open/unresolved as of 2026-07-29, affects R 4.5.0+ on every
# platform). Workaround: Circuitscape.jl/Omniscape.jl are called directly as a Julia SUBPROCESS
# via the CLI entry points in scripts/julia/ (run_omniscape.jl, run_circuitscape.jl); R
# (R/connectivity_run.R) only writes the resistance/source rasters + an INI config, invokes
# `julia.exe`, and reads the resulting GeoTIFFs back -- no analysis logic is reimplemented in R.
#
# Julia was installed by JuliaCall's own installer to a fixed, non-project path -- not managed by
# renv. Confirm this path still exists before running 09_run_omniscape.R/10_run_circuitscape.R on
# a new machine; it will differ per machine.
JULIA_BIN <- "C:/Users/harre/AppData/Roaming/R/data/R/JuliaCall/julia/1.9.4/julia-1.9.4/bin/julia.exe"
JULIA_SCRIPTS_DIR <- file.path(REPO_ROOT, "scripts", "julia")
JULIA_THREADS <- 4L

# Omniscape.jl resolved to a very old default with no GeoTIFF support; pinned to the newest
# version this Julia install allows. Circuitscape.jl needed no such pin.
OMNISCAPE_JL_VERSION <- "0.6.1"
CIRCUITSCAPE_JL_VERSION <- "5.14.0"

# Omniscape neighbourhood scales in CELLS at CONNECTIVITY_GRID_RESOLUTION_M (30m) -- "analysis
# neighbourhood scales", not species movement radii: 50 cells = ~1.5km (local/fine bottlenecks),
# 100 cells = ~3.0km (primary landscape scenario), 200 cells = ~6.0km (broad connectivity).
OMNISCAPE_RADII_CELLS <- c(local = 50, primary = 100, broad = 200)
OMNISCAPE_BLOCK_SIZE <- 3L

# Omniscape run set: model x radius x source-threshold combinations.
OMNISCAPE_CONSERVATIVE_SOURCE_THRESHOLD <- 0.50
OMNISCAPE_RUN_SET <- list(
  list(model = "A", radius = "primary", source = "primary"),
  list(model = "B", radius = "primary", source = "primary"),
  list(model = "C", radius = "local", source = "primary"),
  list(model = "C", radius = "primary", source = "primary"),
  list(model = "C", radius = "broad", source = "primary"),
  list(model = "C", radius = "primary", source = "conservative")
)

#################### RASTER ALIGNMENT / PRESSURE INPUTS ####################
# Road-class resistance-tendency crosswalk, keyed on the ACTUAL OSM `fclass` values found in
# data/roads.gpkg (track=132, path=23, footway=10, unclassified=8, residential=1 -- no
# paved/major roads exist in this AOI).
ROAD_CLASS_SCORES <- c(
  residential  = 0.70,  # maintained, house-serving road
  unclassified = 0.40,  # OSM's own "unknown classification" semantics
  track        = 0.15,
  path         = 0.10,  # foot-only, no vehicle access
  footway      = 0.10
)
ROAD_INFLUENCE_DISTANCE_M <- 100  # minor roads only in this AOI

RIPARIAN_BUFFER_M <- 30  # a universal buffer against high-resolution imagery for this AOI

# Settlement-pressure blend -- heatmap already encodes distance-decay, so built_fraction is a
# secondary local-detail term only (avoids double-counting the heatmap's own decay).
SETTLEMENT_PRESSURE_WEIGHTS <- c(heatmap = 0.70, built_fraction = 0.30)

# Robust-percentile clamp-normalize bounds, reused for every continuous raw-input scaling step
# (slope_scaled, settlement-heatmap normalization).
CONNECTIVITY_PERCENTILE_BOUNDS <- c(5, 95)

#################### DYNAMIC WORLD CLASS SCHEME ####################
# There is no class 0. NoData is the raster's own -9999 sentinel (see NODATA_SENTINEL below).
DW_HABITAT_CLASS_LABELS <- c(
  `1` = "Woody", `2` = "Grassland", `3` = "Mixed natural", `4` = "Cropland",
  `5` = "Built", `6` = "Bare/degraded", `7` = "Water/flooded veg", `8` = "Uncertain"
)
NATURAL_CLASSES    <- c(1, 2, 3)
CONVERSION_CLASSES <- c(4, 5, 6)
EXCLUDED_CLASSES   <- c(7, 8)  # + raster NA

#################### PERIODS ####################
# Matches config.py's DW_PERIODS; NOT the same dict as the productivity/degradation PERIODS
# (different year ranges).
DW_PERIODS <- list(
  baseline = c(2016, 2018),
  pre      = c(2019, 2021),
  current  = c(2022, 2025)
)
# Literal filename tokens used by the Dynamic World raster exports (see scripts/r/R/io.R)
DW_PERIOD_TOKENS <- c(
  "baseline_2016_2018", "pre_2019_2021", "current_2022_2025",
  "current_wet_2022_2025", "current_dry_2022_2025"
)

#################### RASTER / QA CONSTANTS ####################
NODATA_SENTINEL <- -9999  # terra reads this as NA on load, not literal data.
VALID_PIXEL_COVERAGE_MIN <- 0.80  # below this, artificial patch breaks inflate NP/PD/ED

#################### LANDSCAPE METRICS PARAMETERS ####################
EDGE_DEPTH_CELLS <- 1  # package default (1 cell = 10m at this resolution)

MOVING_WINDOW_RADII_M <- c(250, 500, 1000)
MIN_PATCH_AREA_HA <- 1
CORRIDOR_PROXIMITY_DECAY_M <- 2000    # linear decay-to-zero distance from corridor_p1 U corridor_p2

#################### CORRELATION / METRIC SETS ####################
SELECTED_CLASS_METRICS <- c(
  "lsm_c_ca", "lsm_c_pland", "lsm_c_pd", "lsm_c_lpi", "lsm_c_ed",
  "lsm_c_ai", "lsm_c_clumpy", "lsm_c_cohesion", "lsm_c_enn_mn", "lsm_c_mesh"
)
SELECTED_BINARY_METRICS <- setdiff(SELECTED_CLASS_METRICS, "lsm_c_ca")  # CA not meaningful for a 1-class binary landscape
CORRELATION_FLAG_THRESHOLD <- 0.85

#################### CONNECTIVITY VEGETATION CONDITION (RESISTANCE MODEL C INPUT) ####################
# Mirrors config.py's CONNECTIVITY_CONDITION_* block -- built by
# connectivity_condition_composite.ipynb, downloaded from Drive.
CONNECTIVITY_CONDITION_EXPORT_FOLDER <- "CERK_Enarau_Objective4_ConditionComposite"
CONNECTIVITY_CONDITION_PERIOD <- c(2022, 2025)
CONNECTIVITY_CONDITION_SCORE_WEIGHTS <- c(
  productivity      = 0.40,
  moisture          = 0.35,
  inverse_bare_soil = 0.25
)

#################### CONSENSUS + PRIORITY MAPPING ####################
# Percentile thresholds -- landscape-wide percentiles computed per-scenario (robust quantiles
# rather than one fixed absolute value).
HIGH_CURRENT_PERCENTILE <- 90
BOTTLENECK_CURRENT_PERCENTILE <- 90
BOTTLENECK_RESISTANCE_PERCENTILE <- 50  # "resistance >= landscape median"
BOTTLENECK_HC_CURRENT_PERCENTILE <- 95  # higher-confidence bottleneck rule
BOTTLENECK_HC_RESISTANCE_PERCENTILE <- 75
BOTTLENECK_HC_MIN_SCENARIOS <- 2        # must be selected by at least this many Omniscape scenarios

BARRIER_RESISTANCE_PERCENTILE <- 75
BARRIER_FLOW_POTENTIAL_PERCENTILE <- 75
BARRIER_SOURCE_PERCENTILE <- 25  # "low source strength" -- bottom quartile

# Reference scenario for single-surface rasters -- consensus_score still pools all 6 scenarios.
PRIORITY_REFERENCE_SCENARIO <- "C_r100"

PROTECTION_SOURCE_PERCENTILE <- 75
PROTECTION_CURRENT_PERCENTILE <- 75
PROTECTION_RESISTANCE_PERCENTILE <- 50   # below median
RESTORATION_CURRENT_PERCENTILE <- 75
RESTORATION_RESISTANCE_PERCENTILE <- 50  # at/above median

# Patch-level protection/restoration importance weights. Two inputs (patch_gap_reduction_potential,
# implementation_feasibility) have no defined formula and are omitted rather than guessed.
PROTECTION_IMPORTANCE_WEIGHTS <- c(
  connectivity_contribution = 0.35,
  source_strength           = 0.25,
  core_area                 = 0.20,
  stepping_stone_position   = 0.10,
  inverse_human_pressure    = 0.10
)
RESTORATION_IMPORTANCE_WEIGHTS <- c(
  current_or_flow_potential = 0.35,
  resistance_or_degradation = 0.25,
  proximity_to_focal_linkage = 0.20
  # NOT renormalized to sum to 1 -- compare to protection_importance by rank only, not magnitude.
)

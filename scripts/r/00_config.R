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
LANDSCAPE_RASTER_DIR  <- file.path(RASTER_DIR, "landscape_metrics")  # landscape-metrics raster outputs
DW_INPUT_RASTER_DIR   <- file.path(RASTER_DIR, "dynamic_world")      # manually-downloaded Dynamic World inputs
VECTORS_DIR           <- file.path(OUTPUTS_DIR, "vectors")

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
# Mirrors config.py's CONNECTIVITY_INPUT_PATHS. CRS note: roads/streams/settlements/
# settlement_heatmap needed a UTM-zone fix before use (see config.py's own comment); re-check CRS
# on any future re-export of these four files.
CONNECTIVITY_INPUT_PATHS <- list(
  roads                   = file.path(DATA_DIR, "roads.gpkg"),
  streams                 = file.path(DATA_DIR, "streams.gpkg"),
  settlements             = file.path(DATA_DIR, "settlements.gpkg"),
  elevation               = file.path(DATA_DIR, "elevation.tif"),
  slope                   = file.path(DATA_DIR, "slope.tif"),
  settlement_heatmap      = file.path(DATA_DIR, "settlement_heatmap.tif"),
  condition_score_wet     = file.path(DATA_DIR, "condition_score_wet_2022_2025_project.tif"),
  condition_score_dry     = file.path(DATA_DIR, "condition_score_dry_2022_2025_project.tif"),
  condition_score_current = file.path(DATA_DIR, "condition_score_current_2022_2025_project.tif")
)

#################### CONNECTIVITY MASTER GRID ####################
# 30m primary landscape-wide grid. build_master_grid() (R/grid.R) rounds project_geom_vect()'s
# extent outward to a clean 30m origin -- confirmed to reproduce data/elevation.tif's own grid
# exactly, so elevation.tif/slope.tif need no further CRS/extent correction.
CONNECTIVITY_GRID_RESOLUTION_M <- 30
CONNECTIVITY_LANDCOVER_SOURCE_RESOLUTION_M <- 10  # outputs/rf_hab_classifier/*_10m_clipped.tif

CONNECTIVITY_RASTER_DIR <- file.path(RASTER_DIR, "connectivity")
CONNECTIVITY_OUTPUT_DIR <- file.path(OUTPUTS_DIR, "connectivity")  # omniscape/circuitscape run dirs
for (d in c(CONNECTIVITY_RASTER_DIR, CONNECTIVITY_OUTPUT_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

#################### LAND-COVER CLASS SCHEME (Airbus RF classifier) ####################
# Mirrors config.py's RF_FINAL_CLASS_LABELS -- the delivered 7-class scheme from
# outputs/rf_hab_classifier/airbus_landcover_classification_10m_clipped.tif. NOT the same scheme
# as DW_HABITAT_CLASS_LABELS below (different classifier, different source imagery) -- do not mix
# the two class-ID spaces.
RF_FINAL_CLASS_LABELS <- c(
  `1` = "dense_forest", `2` = "bareground", `3` = "grassland", `4` = "cultivated",
  `5` = "shrubland", `6` = "water", `7` = "built"
)
# Species-agnostic groupings for the natural/cultivated/built/water fraction bands: grassland and
# shrubland are NOT treated as lower-quality than forest -- all three are "natural" here.
NATURAL_LC_CLASSES     <- c(1, 3, 5)  # dense_forest, grassland, shrubland
CULTIVATED_LC_CLASSES  <- c(4)
BUILT_LC_CLASSES        <- c(7)
WATER_LC_CLASSES        <- c(6)
BAREGROUND_LC_CLASSES   <- c(2)

# class_id -> class_name mapping BEFORE the cultivated_a/cultivated_b collapse (mirrors config.py's
# RF_CLASS_LABELS), needed only to remap accuracy_metrics_pixels.csv (computed against this
# 8-class training scheme) onto the 7-class RF_FINAL_CLASS_LABELS delivered raster.
RF_CLASS_REMAP <- c(`1` = 1, `2` = 2, `3` = 3, `4` = 4, `5` = 4, `6` = 5, `7` = 6, `8` = 7)
RF_ACCURACY_PIXELS_PATH <- file.path(REPO_ROOT, "outputs", "rf_hab_classifier", "accuracy_metrics_pixels.csv")

# Land-cover permeability crosswalk, one value per RF_FINAL_CLASS_LABELS class -- starting values,
# not yet literature/expert justified. Species-agnostic: grassland/shrubland score the same as
# dense_forest, not lower. Water given a neutral 0.40 rather than a dedicated water-resistance
# scenario in this first pass -- revisit if Circuitscape results look water-body-sensitive.
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

# Neutral vs. riparian-facilitation scenario values feeding the Resistance-C riparian term --
# built from riparian_buffer_30m.tif/riparian_natural_cover_30m.tif (step 06).
RIPARIAN_FACTOR_NEUTRAL <- 0.50
RIPARIAN_FACTOR_FACILITATION <- 0.85  # starting value, within a 0.75-1.00 facilitation range

SOURCE_THRESHOLD_PRIMARY <- 0.30
SOURCE_CONSERVATIVE_CRITERIA <- list(
  natural_fraction_min = 0.70, settlement_pressure_max = 0.25,
  road_pressure_max = 0.35, condition_score_min = 0.40
)

#################### HABITAT PATCHES + FOCAL NODES ####################
# Core-habitat pixel rule -- deliberately the SAME thresholds as SOURCE_CONSERVATIVE_CRITERIA's
# natural_fraction_min/settlement_pressure_max (0.70/0.25); kept as its own named constant since
# the two serve conceptually different purposes (source strength vs. patch delineation) and could
# diverge later.
CORE_HABITAT_CRITERIA <- list(
  natural_fraction_min = 0.70, landcover_permeability_min = 0.70, settlement_pressure_max = 0.25
)

# Patch-size tiers -- planning thresholds, not species home-range requirements.
PATCH_TIER_THRESHOLDS_HA <- c(tier1_min = 50, tier2_min = 20, tier3_min = 5)

# Focal-node candidate filter + per-site target counts. Target counts are the upper end of each
# site's suggested range -- a starting cap on an initial selection, not an exact requirement.
# "external_buffer" (patches outside all 4 named sites but within the buffer) has no cap, to avoid
# artificially bounding the network at the analysis boundary.
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

# Omniscape.jl resolved to a very old default version with no GeoTIFF support; explicitly upgraded
# to the newest version this Julia install allows. Circuitscape.jl needed no such pin.
OMNISCAPE_JL_VERSION <- "0.6.1"
CIRCUITSCAPE_JL_VERSION <- "5.14.0"

# Omniscape neighbourhood scales in CELLS at CONNECTIVITY_GRID_RESOLUTION_M (30m) -- "analysis
# neighbourhood scales", not species movement radii: 50 cells = ~1.5km (local/fine bottlenecks),
# 100 cells = ~3.0km (primary landscape scenario), 200 cells = ~6.0km (broad connectivity).
OMNISCAPE_RADII_CELLS <- c(local = 50, primary = 100, broad = 200)
OMNISCAPE_BLOCK_SIZE <- 3L

# Omniscape run set: model x radius x source-threshold combinations -- see notes.md for what each
# scenario represents.
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
# paved/major roads exist in this AOI at all). Starting values, not yet literature/expert
# justified.
ROAD_CLASS_SCORES <- c(
  residential  = 0.70,  # maintained, house-serving road
  unclassified = 0.40,  # OSM's own "unknown classification" semantics
  track        = 0.15,
  path         = 0.10,  # foot-only, no vehicle access
  footway      = 0.10
)
ROAD_INFLUENCE_DISTANCE_M <- 100  # appropriate here since every road present is minor

RIPARIAN_BUFFER_M <- 30  # a universal buffer against high-resolution imagery for this AOI

# Settlement-pressure blend -- heatmap already encodes distance-decay from built structures, so
# built_fraction is a secondary, local-detail term only (30% weight), not a second independent
# distance term (would double-count the heatmap's own decay).
SETTLEMENT_PRESSURE_WEIGHTS <- c(heatmap = 0.70, built_fraction = 0.30)

# Robust-percentile clamp-normalize bounds, reused for every continuous raw-input scaling step in
# this pipeline (slope_scaled, settlement-heatmap normalization) -- same treatment as
# CONNECTIVITY_CONDITION_PERCENTILE_BOUNDS below (the Python-side notebook's equivalent constant).
CONNECTIVITY_PERCENTILE_BOUNDS <- c(5, 95)

#################### DYNAMIC WORLD CLASS SCHEME ####################
# There is no class 0 -- classify_habitat() never emits it. NoData is the raster's own -9999
# sentinel (see NODATA_SENTINEL below), not a literal class value.
DW_HABITAT_CLASS_LABELS <- c(
  `1` = "Woody", `2` = "Grassland", `3` = "Mixed natural", `4` = "Cropland",
  `5` = "Built", `6` = "Bare/degraded", `7` = "Water/flooded veg", `8` = "Uncertain"
)
NATURAL_CLASSES    <- c(1, 2, 3)
CONVERSION_CLASSES <- c(4, 5, 6)
EXCLUDED_CLASSES   <- c(7, 8)  # + raster NA

DW_PRESSURE_CLASS_LABELS <- c(`0` = "Low", `1` = "Moderate", `2` = "High")

#################### PERIODS ####################
# Matches config.py's DW_PERIODS; the productivity/degradation PERIODS uses different year ranges
# (Landsat baseline 1984-2000) and is NOT the same dict.
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
VALID_PIXEL_COVERAGE_MIN <- 0.80  # site-years below this show artificial
                                  # patch breaks that inflate NP/PD/ED -- exclude from Level 2/3.

#################### LANDSCAPE METRICS PARAMETERS ####################
EDGE_DEPTH_CELLS <- 1  # package default (1 cell = 10m at this resolution)

MOVING_WINDOW_RADII_M <- c(250, 500, 1000)
MIN_PATCH_AREA_HA <- 1
CORRIDOR_PROXIMITY_DECAY_M <- 2000    # linear decay-to-zero distance from corridor_p1 U corridor_p2;
                                       # also reused by the connectivity patch scoring below

#################### CORRELATION / METRIC SETS ####################
SELECTED_CLASS_METRICS <- c(
  "lsm_c_ca", "lsm_c_pland", "lsm_c_pd", "lsm_c_lpi", "lsm_c_ed",
  "lsm_c_ai", "lsm_c_clumpy", "lsm_c_cohesion", "lsm_c_enn_mn", "lsm_c_mesh"
)
SELECTED_BINARY_METRICS <- setdiff(SELECTED_CLASS_METRICS, "lsm_c_ca")  # CA not meaningful for a 1-class binary landscape
CORRELATION_FLAG_THRESHOLD <- 0.85

#################### CONNECTIVITY VEGETATION CONDITION (RESISTANCE MODEL C INPUT) ####################
# Mirrors config.py's CONNECTIVITY_CONDITION_* block -- built by
# scripts/python/notebooks/connectivity_condition_composite.ipynb, downloaded from Drive into
# RASTER_DIR/connectivity as condition_score_{wet,dry,current}_2022_2025_project.tif.
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

# Reference scenario for single-surface bottleneck/barrier/priority rasters -- consensus_score
# itself still pools across all 6 Omniscape scenarios.
PRIORITY_REFERENCE_SCENARIO <- "C_r100"

PROTECTION_SOURCE_PERCENTILE <- 75
PROTECTION_CURRENT_PERCENTILE <- 75
PROTECTION_RESISTANCE_PERCENTILE <- 50   # below median
RESTORATION_CURRENT_PERCENTILE <- 75
RESTORATION_RESISTANCE_PERCENTILE <- 50  # at/above median

# Patch-level protection/restoration importance weights. Two inputs (patch_gap_reduction_potential,
# implementation_feasibility) have no defined formula and are omitted rather than guessed -- see
# notes.md's Connectivity section for how to interpret the resulting scores.
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
  # Weights above are NOT renormalized to sum to 1 -- this score is intentionally on a smaller
  # scale than protection_importance; compare the two only in rank order, not by magnitude.
)

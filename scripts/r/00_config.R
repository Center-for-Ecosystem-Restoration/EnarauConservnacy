# Mirrors EnarauConservnacy/config.py -- config.py is the Python
# source of truth for this repo. R cannot `import config.py` (no reticulate in use anywhere in
# this repo, by design -- see CLAUDE.md's "mixed-language stack, not pure Python"). If config.py's
# PROJECT_CRS, DW_PERIODS, DW_HABITAT_CLASS_LABELS, SITES, or STUDY_AREA_BUFFER_M change, this
# file must be updated to match by hand -- there is no automated drift check.
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
LANDSCAPE_RASTER_DIR  <- file.path(RASTER_DIR, "landscape_metrics")  # Objective 3's OWN raster outputs
DW_INPUT_RASTER_DIR   <- file.path(RASTER_DIR, "dynamic_world")      # manually-downloaded Objective 1 inputs
VECTORS_DIR           <- file.path(OUTPUTS_DIR, "vectors")

for (d in c(LANDSCAPE_RASTER_DIR, VECTORS_DIR, TABLES_DIR, PLOTS_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

#################### PROJECT-WIDE SETTINGS ####################
# WGS 84 / UTM zone 36S
PROJECT_CRS <- "EPSG:32736"
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

#################### CONNECTIVITY RAW INPUTS (Objective 4) ####################
# Mirrors config.py's CONNECTIVITY_INPUT_PATHS. CRS FIX (2026-07-29): roads/streams/settlements/
# settlement_heatmap all arrived tagged EPSG:32737 (wrong UTM zone -- 37S instead of this AOI's
# real 36S); all four were reprojected in place to PROJECT_CRS before this repo used them. See
# config.py's own comment for the full diagnosis. Re-check CRS on any future re-export of these
# four files before trusting it.
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

#################### CONNECTIVITY MASTER GRID (Objective 4) ####################
# 30m primary landscape-wide grid per the plan's Sec.4 rationale (slope native res, manageable
# circuit-theory compute, appropriate for landscape- not pixel-scale pathways). build_master_grid()
# (R/grid.R) rounds project_geom_vect()'s extent outward to a clean 30m origin -- confirmed
# 2026-07-29 this reproduces data/elevation.tif's own grid exactly (xmin=750900, xmax=764400,
# ymin=9877890, ymax=9890130, 408 rows x 450 cols), so elevation.tif/slope.tif need no CRS/extent
# correction, just the standard align_to_grid() pass everything else also goes through.
CONNECTIVITY_GRID_RESOLUTION_M <- 30
CONNECTIVITY_LANDCOVER_SOURCE_RESOLUTION_M <- 10  # outputs/rf_hab_classifier/*_10m_clipped.tif

CONNECTIVITY_RASTER_DIR <- file.path(RASTER_DIR, "connectivity")
CONNECTIVITY_OUTPUT_DIR <- file.path(OUTPUTS_DIR, "connectivity")  # omniscape/circuitscape run dirs (09-11)
for (d in c(CONNECTIVITY_RASTER_DIR, CONNECTIVITY_OUTPUT_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

#################### LAND-COVER CLASS SCHEME (Objective 4 -- Airbus RF classifier) ####################
# Mirrors config.py's RF_FINAL_CLASS_LABELS -- the delivered 7-class scheme from
# outputs/rf_hab_classifier/airbus_landcover_classification_10m_clipped.tif (see the write-back
# note 2026-07-28-enarau-objective4-landcover-provenance-resolved.md for how this was confirmed as
# Objective 4's primary land-cover input). NOT the same scheme as DW_HABITAT_CLASS_LABELS above
# (different classifier, different source imagery) -- do not mix the two class-ID spaces.
RF_FINAL_CLASS_LABELS <- c(
  `1` = "dense_forest", `2` = "bareground", `3` = "grassland", `4` = "cultivated",
  `5` = "shrubland", `6` = "water", `7` = "built"
)
# Groupings for the natural/cultivated/built/water fraction bands (plan Sec.3.3/6.1). Species-
# agnostic framing (plan Sec.6.1): grassland and shrubland are NOT treated as lower-quality than
# forest -- all three are "natural" here.
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

# Land-cover permeability crosswalk (plan Sec.6.1 table), one value per RF_FINAL_CLASS_LABELS
# class -- starting values within the plan's own suggested ranges, not yet literature/expert
# justified (same caveat [[circuit-theory-connectivity]] flags as the real analytical work this
# package doesn't do for you). Species-agnostic (plan Sec.6.1): grassland/shrubland score the same
# as dense_forest, not lower. Water given a neutral 0.40 (plan frames water as "scenario
# dependent", not a single value) rather than a dedicated water resistance scenario in this first
# pass -- revisit if Circuitscape results look water-body-sensitive.
LANDCOVER_PERMEABILITY <- c(
  dense_forest = 0.95,
  grassland    = 0.90,
  shrubland    = 0.90,
  cultivated   = 0.35,  # "low-intensity cultivation" (plan range 0.20-0.50) -- this classifier
                         # has no intensive/low-intensity split
  bareground   = 0.50,  # "moderate and uncertain" (plan range 0.35-0.70)
  water        = 0.40,  # neutral scenario value, see note above
  built        = 0.02
)

#################### RESISTANCE MODELS A/B/C + SOURCE STRENGTH (plan Sec.7-8) ####################
RESISTANCE_RMAX <- c(A = 100, B = 150, C = 150)
RESISTANCE_B_WEIGHTS <- c(landcover = 0.60, human = 0.25, road = 0.15)
RESISTANCE_C_WEIGHTS <- c(
  landcover = 0.45, human = 0.20, road = 0.15, condition = 0.10, terrain = 0.05, riparian = 0.05
)
BUILT_FRACTION_RESISTANCE_FLOOR <- list(threshold = 0.50, floor = 150)  # plan Sec.7.2/7.3

# Neutral vs. riparian-facilitation scenario values feeding the Resistance-C riparian term (plan
# Sec.7.3) -- built from riparian_buffer_30m.tif/riparian_natural_cover_30m.tif (step 06).
RIPARIAN_FACTOR_NEUTRAL <- 0.50
RIPARIAN_FACTOR_FACILITATION <- 0.85  # plan's 0.75-1.00 range, midpoint-ish starting value

SOURCE_THRESHOLD_PRIMARY <- 0.30
SOURCE_CONSERVATIVE_CRITERIA <- list(
  natural_fraction_min = 0.70, settlement_pressure_max = 0.25,
  road_pressure_max = 0.35, condition_score_min = 0.40
)

#################### HABITAT PATCHES + FOCAL NODES (plan Sec.10) ####################
# Core-habitat pixel rule (plan Sec.10.1) -- deliberately the SAME thresholds as
# SOURCE_CONSERVATIVE_CRITERIA's natural_fraction_min/settlement_pressure_max (0.70/0.25), since
# the plan specifies both with identical values; kept as its own named constant rather than
# reusing SOURCE_CONSERVATIVE_CRITERIA directly since the two serve conceptually different
# purposes (source strength vs. patch delineation) and could diverge later.
CORE_HABITAT_CRITERIA <- list(
  natural_fraction_min = 0.70, landcover_permeability_min = 0.70, settlement_pressure_max = 0.25
)

# Patch-size tiers (plan Sec.10.3) -- planning thresholds, not species home-range requirements.
PATCH_TIER_THRESHOLDS_HA <- c(tier1_min = 50, tier2_min = 20, tier3_min = 5)

# Focal-node candidate filter + per-site target counts (plan Sec.10.4/13.8) -- area_ha >= 20 is
# the plan's OWN R implementation outline filter (Sec.13.8), reused directly. Target counts are
# the upper end of each site's suggested range ("1-3 Enarau", "2-5 Corridor Phase 1", etc.) --
# a starting cap on an initial selection, not an exact requirement. "external_buffer" (patches
# outside all 4 named sites but within the buffer) has no cap, per the plan's own guidance to
# avoid artificially bounding the network at the analysis boundary.
FOCAL_NODE_MIN_AREA_HA <- 20
FOCAL_NODE_TARGET_COUNTS <- c(enarau = 3, mbokishi = 3, corridor_p1 = 5, corridor_p2 = 5)

#################### JULIA / CIRCUITSCAPE.JL / OMNISCAPE.JL (Objective 4, plan Sec.9-13) ####################
# `circuitscaper` (the R package the plan's own R implementation outline, Sec.13, is written
# against) is installed in this renv library but NOT USABLE here: R 4.5+ hides the `SET_SYMVALUE`
# C symbol that RCall.jl depends on for its R<->Julia embedding (RCall.jl issue #566, open,
# unresolved as of 2026-07-29, confirmed to affect R 4.5.0+ on every platform, not just Windows)
# -- JuliaCall's setup.jl unconditionally does `using RCall`, and neither `rebuild=TRUE` nor
# `useRCall=FALSE` avoid it (the latter is a vestigial, unused parameter in JuliaCall 0.17.6).
# See the write-back note 2026-07-29-enarau-objective4-circuitscaper-rcall-incompatibility.md.
#
# Workaround: Circuitscape.jl and Omniscape.jl are called directly as a Julia SUBPROCESS (no
# in-process R<->Julia embedding, so RCall's brokenness never comes into play) via the trivial CLI
# entry points in scripts/julia/ (run_omniscape.jl, run_circuitscape.jl -- each just forwards a
# single INI config-file path to the package's own `run_omniscape()`/`compute()` function). R's
# job (R/connectivity_run.R) is limited to: writing the resistance/source rasters this repo
# already produces, writing an INI config file, invoking `julia.exe` via system2(), and reading
# the resulting GeoTIFFs back with terra::rast() -- no analysis logic is reimplemented in R.
#
# Julia was installed by JuliaCall's own installer (still usable for this, since only ITS RCall
# bridge is broken) to a fixed, non-project path -- not managed by renv (Julia/Julia packages are
# a separate ecosystem from R's library system). Confirm this path still exists before running
# 09_run_omniscape.R/10_run_circuitscape.R on a new machine; it will differ per machine.
JULIA_BIN <- "C:/Users/harre/AppData/Roaming/R/data/R/JuliaCall/julia/1.9.4/julia-1.9.4/bin/julia.exe"
JULIA_SCRIPTS_DIR <- file.path(REPO_ROOT, "scripts", "julia")
JULIA_THREADS <- 4L

# Omniscape.jl was resolved by Julia's package manager to a very old v0.1.4 by default (no
# GeoTIFF support -- confirmed empirically, it unconditionally tries to parse any resistance_file
# as ESRI ASCII grid regardless of extension) due to compatibility constraints from other packages
# already in this Julia environment; explicitly upgraded to v0.6.1 (the newest version Julia 1.9.4
# itself allows -- v0.6.2+ requires a newer Julia) via
# `Pkg.add(Pkg.PackageSpec(name="Omniscape", version="0.6.1"))`, which does support GeoTIFF I/O
# (confirmed via a smoke test, 2026-07-29). Circuitscape.jl resolved directly to v5.14.0, which
# already supports GeoTIFF I/O (write_as_tif) with no version pinning needed.
OMNISCAPE_JL_VERSION <- "0.6.1"
CIRCUITSCAPE_JL_VERSION <- "5.14.0"

# Omniscape neighbourhood scales in CELLS at CONNECTIVITY_GRID_RESOLUTION_M (30m) -- plan Sec.9.2's
# "analysis neighbourhood scales" (deliberately not called species movement radii): 50 cells =
# ~1.5km (local/fine bottlenecks), 100 cells = ~3.0km (primary landscape scenario), 200 cells =
# ~6.0km (broad landscape connectivity).
OMNISCAPE_RADII_CELLS <- c(local = 50, primary = 100, broad = 200)
OMNISCAPE_BLOCK_SIZE <- 3L  # plan Sec.13.7's own example value

# Minimum Omniscape run set (plan Sec.9.3): model x radius x source-threshold combinations.
# threshold values reference SOURCE_THRESHOLD_PRIMARY / an explicit alternate value (plan Sec.8.3
# "test source threshold = 0.30 versus 0.50").
OMNISCAPE_CONSERVATIVE_SOURCE_THRESHOLD <- 0.50
OMNISCAPE_RUN_SET <- list(
  list(model = "A", radius = "primary", source = "primary"),
  list(model = "B", radius = "primary", source = "primary"),
  list(model = "C", radius = "local", source = "primary"),
  list(model = "C", radius = "primary", source = "primary"),
  list(model = "C", radius = "broad", source = "primary"),
  list(model = "C", radius = "primary", source = "conservative")
)

#################### RASTER ALIGNMENT / PRESSURE INPUTS (Objective 4, plan Sec.5) ####################
# Road-class resistance-tendency crosswalk (plan Sec.5.4 table), keyed on the ACTUAL OSM `fclass`
# values found in data/roads.gpkg (confirmed 2026-07-29: track=132, path=23, footway=10,
# unclassified=8, residential=1 -- no paved/major roads exist in this AOI at all). "unclassified"
# maps to the plan's own "Unknown" row (0.40) since that's OSM's literal semantics for "road of
# unknown class", not a missing-data placeholder. These are starting values per the plan's own
# framing -- not yet literature/expert justified, same caveat as DW_HABITAT_THRESHOLDS.
ROAD_CLASS_SCORES <- c(
  residential  = 0.70,  # closest to the plan's "Secondary road" tier -- maintained, house-serving
  unclassified = 0.40,  # plan's "Unknown" row -- OSM's own "unknown classification" semantics
  track        = 0.15,  # plan's "Minor track"
  path         = 0.10,  # foot-only, no vehicle access -- below "Minor track"
  footway      = 0.10
)
ROAD_INFLUENCE_DISTANCE_M <- 100  # plan Sec.5.4 "narrow road influence: 50-100m" -- appropriate
                                   # here since every road present is minor (no major/paved roads)

RIPARIAN_BUFFER_M <- 30  # plan Sec.3.1.D -- "30m is an appropriate universal buffer" against
                          # high-resolution imagery for this AOI

# Settlement-pressure blend (plan Sec.5.3) -- heatmap already encodes distance-decay from built
# structures, so built_fraction is a secondary, local-detail term only (30% weight), not a second
# independent distance term (would double-count the heatmap's own decay).
SETTLEMENT_PRESSURE_WEIGHTS <- c(heatmap = 0.70, built_fraction = 0.30)

# Robust-percentile clamp-normalize bounds, reused for every continuous raw-input scaling step in
# this pipeline (slope_scaled per plan Sec.5.6, settlement-heatmap normalization per Sec.5.3) --
# same treatment as CONNECTIVITY_CONDITION_PERCENTILE_BOUNDS above (the Python-side notebook's
# equivalent constant for the vegetation-condition composite).
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
# Matches config.py's DW_PERIODS; Objective 2 PERIODS uses different year
# ranges (Landsat baseline 1984-2000) and is NOT the same dict.
DW_PERIODS <- list(
  baseline = c(2016, 2018),
  pre      = c(2019, 2021),
  current  = c(2022, 2025)
)
# Literal filename tokens used by Objective 1's raster exports (see scripts/r/R/io.R)
DW_PERIOD_TOKENS <- c(
  "baseline_2016_2018", "pre_2019_2021", "current_2022_2025",
  "current_wet_2022_2025", "current_dry_2022_2025"
)

#################### RASTER / QA CONSTANTS ####################
NODATA_SENTINEL <- -9999  # terra reads this as NA on load, not literal data.
VALID_PIXEL_COVERAGE_MIN <- 0.80  # site-years below this show artificial
                                  # patch breaks that inflate NP/PD/ED -- exclude from Level 2/3.

#################### LANDSCAPE METRICS PARAMETERS ####################
# Package default (1 cell = 10 m at this resolution). Provisional, same treatment as config.py's
# DW_HABITAT_THRESHOLDS -- not yet literature-justified, must stay fixed across the whole project
# once chosen so CORE/patch-importance numbers remain comparable across periods and sites.
EDGE_DEPTH_CELLS <- 1

MOVING_WINDOW_RADII_M <- c(250, 500, 1000)
MIN_PATCH_AREA_HA <- 1
CORRIDOR_PROXIMITY_DECAY_M <- 2000    # linear decay-to-zero distance from corridor_p1 U corridor_p2;
                                       # also reused by Objective 4's patch protection/restoration scoring

#################### CORRELATION / METRIC SETS ####################
SELECTED_CLASS_METRICS <- c(
  "lsm_c_ca", "lsm_c_pland", "lsm_c_pd", "lsm_c_lpi", "lsm_c_ed",
  "lsm_c_ai", "lsm_c_clumpy", "lsm_c_cohesion", "lsm_c_enn_mn", "lsm_c_mesh"
)
SELECTED_BINARY_METRICS <- setdiff(SELECTED_CLASS_METRICS, "lsm_c_ca")  # CA not meaningful for a 1-class binary landscape
CORRELATION_FLAG_THRESHOLD <- 0.85

# PATCH_GRAPH_DISTANCE_THRESHOLDS_M, PATCH_PRESSURE_BUFFER_M, LINKAGE_SCORE_WEIGHTS, and
# PATCH_IMPORTANCE_WEIGHTS (Objective 3's Euclidean patch-graph scoring) were removed 2026-07-29
# along with the rest of that workflow -- see R/patch_graph.R's header comment for why.

#################### CONNECTIVITY VEGETATION CONDITION (Objective 4, Resistance Model C) ####################
# Mirrors config.py's CONNECTIVITY_CONDITION_* block -- built by
# scripts/python/notebooks/connectivity_condition_composite.ipynb, downloaded from Drive folder
# CONNECTIVITY_CONDITION_EXPORT_FOLDER into RASTER_DIR/connectivity (Objective 4's own R scripts,
# not yet written, will read condition_score_{wet,dry,current}_2022_2025_project.tif from there).
CONNECTIVITY_CONDITION_EXPORT_FOLDER <- "CERK_Enarau_Objective4_ConditionComposite"
CONNECTIVITY_CONDITION_PERIOD <- c(2022, 2025)
CONNECTIVITY_CONDITION_SCORE_WEIGHTS <- c(
  productivity      = 0.40,
  moisture          = 0.35,
  inverse_bare_soil = 0.25
)

#################### CONSENSUS + PRIORITY MAPPING (Objective 4, plan Sec.11-12) ####################
# Percentile thresholds (plan Sec.12.1/12.2) -- landscape-wide percentiles computed per-scenario
# (not one fixed absolute value), per the plan's own "use quantiles or robust statistical classes
# rather than assuming one universal numeric threshold" guidance.
HIGH_CURRENT_PERCENTILE <- 90          # plan Sec.12.2 high_current_mask threshold, per scenario
BOTTLENECK_CURRENT_PERCENTILE <- 90    # plan Sec.12.1 moderate-confidence bottleneck rule
BOTTLENECK_RESISTANCE_PERCENTILE <- 50 # "resistance >= landscape median"
BOTTLENECK_HC_CURRENT_PERCENTILE <- 95   # plan's higher-confidence bottleneck rule
BOTTLENECK_HC_RESISTANCE_PERCENTILE <- 75
BOTTLENECK_HC_MIN_SCENARIOS <- 2        # "selected by at least two model scenarios"

BARRIER_RESISTANCE_PERCENTILE <- 75    # plan Sec.12.3 "high resistance"
BARRIER_FLOW_POTENTIAL_PERCENTILE <- 75  # "high flow potential or high surrounding current"
BARRIER_SOURCE_PERCENTILE <- 25        # "low source strength" -- bottom quartile

# Reference scenario for single-surface bottleneck/barrier/priority rasters (plan's own
# production choice, Sec.7.6) -- consensus_score itself still pools across all 6 scenarios.
PRIORITY_REFERENCE_SCENARIO <- "C_r100"

# Protection/restoration priority thresholds (plan Sec.12.6/12.7) -- percentile-based, consistent
# with the rest of this pipeline's "robust percentile, not fixed value" treatment.
PROTECTION_SOURCE_PERCENTILE <- 75
PROTECTION_CURRENT_PERCENTILE <- 75
PROTECTION_RESISTANCE_PERCENTILE <- 50   # "low current resistance" -- below median
RESTORATION_CURRENT_PERCENTILE <- 75     # "high current or high flow potential"
RESTORATION_RESISTANCE_PERCENTILE <- 50  # "moderate or high resistance" -- at/above median

# Patch-level protection/restoration importance weights (plan Sec.11.3/11.4). Two inputs the plan
# lists (patch_gap_reduction_potential, implementation_feasibility for restoration;
# stepping_stone_position already gets an Objective-4-native proxy below) have no defined formula
# in the plan itself -- omitted here rather than guessed, with weight redistributed proportionally
# across the remaining components; document this redistribution wherever these scores are reported.
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
  # patch_gap_reduction_potential (0.10) and implementation_feasibility (0.10) omitted -- no
  # defined formula in the plan; weights above are NOT renormalized to sum to 1, so this score is
  # intentionally on a smaller [0, 0.80]-ish scale than protection_importance -- compare the two
  # only in rank order, not by absolute magnitude.
)

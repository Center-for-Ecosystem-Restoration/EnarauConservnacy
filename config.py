from pathlib import Path

#################### FILE PATH HANDLING #######################

REPO_ROOT = Path(__file__).resolve().parents[0]
DATA_DIR = REPO_ROOT / "data"
OUTPUTS_DIR = REPO_ROOT / "outputs"
RASTER_DIR = OUTPUTS_DIR / "rasters"
PLOTS_DIR = OUTPUTS_DIR / "plots"
TABLES_DIR = OUTPUTS_DIR / "tables"
LANDSCAPE_RASTER_DIR = RASTER_DIR / "landscape_metrics"
VECTORS_DIR = OUTPUTS_DIR / "vectors"
RF_CLASSIFIER_DIR = OUTPUTS_DIR / "rf_hab_classifier"
# Manually-downloaded Dynamic World raster exports from Drive (DW_EXPORT_FOLDER is the source of
# truth) -- R reads from this local landing folder. Not R-importable as a path object, so
# scripts/r/00_config.R mirrors this path literally (R cannot `import config.py`).
DW_RASTER_INPUT_DIR = RASTER_DIR / "dynamic_world"
# Objective 4 (Circuitscape/Omniscape connectivity) raster outputs -- written by
# scripts/r/06_prepare_connectivity_inputs.R through 11_consensus_priority_mapping.R. Not
# R-importable as a path object, so scripts/r/00_config.R mirrors this path literally.
CONNECTIVITY_RASTER_DIR = RASTER_DIR / "connectivity"

OUTPUT_DIRS = {
    "plots": PLOTS_DIR,
    "landscape_metrics": LANDSCAPE_RASTER_DIR,
    "tables": TABLES_DIR,
    "rasters": RASTER_DIR,
    "vectors": VECTORS_DIR,
    "rf_hab_classifier": RF_CLASSIFIER_DIR,
    "connectivity": CONNECTIVITY_RASTER_DIR,
}

#################### AOI BOUNDARIES ##########################
AOI_PATHS = {
    "enarau": DATA_DIR / "enarau_conservancy.geojson",
    "mbokishi": DATA_DIR / "mbokishi_conservancy.geojson",
    "phase_1_corridor": DATA_DIR / "phase_1_corridor.geojson",
    "phase_2_corridor": DATA_DIR / "phase_2_corridor.geojson",
}

#################### CONNECTIVITY RAW INPUTS ##########################
# Authoritative copies of the connectivity analysis's raw GIS inputs -- hand-produced/QGIS
# deliverables, not regenerable pipeline outputs, so they live in data/ rather than outputs/.
# CRS note: roads/streams/settlements/settlement_heatmap should use PROJECT_CRS;
# re-check CRS if any of these four are ever re-exported from their source QGIS project
# (see git history for the fix if needed).
CONNECTIVITY_INPUT_PATHS = {
    "roads": DATA_DIR / "roads.gpkg",
    "streams": DATA_DIR / "streams.gpkg",
    "settlements": DATA_DIR / "settlements.gpkg",
    "elevation": DATA_DIR / "elevation.tif",
    "slope": DATA_DIR / "slope.tif",
    "settlement_heatmap": DATA_DIR / "settlement_heatmap.tif",
    "condition_score_wet": DATA_DIR
    / "condition_score_wet_2022_2025_project.tif",
    "condition_score_dry": DATA_DIR
    / "condition_score_dry_2022_2025_project.tif",
    "condition_score_current": DATA_DIR
    / "condition_score_current_2022_2025_project.tif",
}

#################### SITE METADATA ##########################
SITES = [
    {
        "site_id": "enarau",
        "site_name": "Enarau Conservancy",
        "path": AOI_PATHS["enarau"],
    },
    {
        "site_id": "mbokishi",
        "site_name": "Mbokishi Conservancy",
        "path": AOI_PATHS["mbokishi"],
    },
    {
        "site_id": "corridor_p1",
        "site_name": "Corridor Phase 1",
        "path": AOI_PATHS["phase_1_corridor"],
    },
    {
        "site_id": "corridor_p2",
        "site_name": "Corridor Phase 2",
        "path": AOI_PATHS["phase_2_corridor"],
    },
]
STUDY_AREA_BUFFER_M = (
    150  # buffer around the union of all sites for project-wide exports
)
REFERENCE_SITE_ID = (
    "mbokishi"  # intact reference site for site-relative anomaly comparisons
)

#################### PROJECT-WIDE SETTINGS ##########################
PROJECT_CRS = "EPSG:32736"  # WGS 84 / UTM zone 36S -- used by every notebook/script in this repo

#################### DYNAMIC WORLD HISTORICAL CHANGE ##########################
DW_EXPORT_FOLDER = "CERK_Enarau_DW_HistoricalChange"
DW_EXCLUDED_PROB_BANDS = [
    "snow_and_ice"
]  # filtered out of eetools.constants.DW_PROBABILITY_BANDS

DW_DERIVED_BANDS = [
    "natural_prob",
    "woody_prob",
    "grass_prob",
    "conversion_pressure_prob",
    "hard_conversion_prob",
    "bare_degradation_prob",
    "water_wetland_prob",
    "top1_prob",
    "valid_obs_count",
]

DW_YEAR_START = 2016
DW_YEAR_END = 2025
DW_SEASONS = ["wet", "dry", "annual"]
DW_PERIODS = {
    "baseline": (2016, 2018),
    "pre": (2019, 2021),
    "current": (2022, 2025),
}

DW_MIN_OBS_ANNUAL = 3
# Seasonal floor is deliberately low: the wet season (Mar-May) is the rainiest part of the year at
# this AOI and frequently clears no more than 1-2 cloud-free Sentinel-2 passes -- see notes.md.
DW_MIN_OBS_SEASONAL = 1
DW_COVERAGE_WARNING_PCT = (
    60  # reporting threshold only -- does not mask any pixels
)

# Habitat classification thresholds -- calibrated against a ground-truth RF classification (see
# notes.md's "DW Historical Change Detection" section for the full calibration history, including
# two classes -- Bare/degraded and Water/flooded veg -- that remain unclassifiable by threshold
# choice alone). The classification test is `probability_band.gte(threshold)`; lowering a
# threshold makes more pixels match that class.
DW_HABITAT_THRESHOLDS = {
    "crops_min": 0.14,  # crops is a single raw DW band while woody/grass/natural are sums of 2-3
    # bands sharing the same 1.0 probability budget, so a matched floor would
    # systematically favor the aggregated bands -- kept well below woody/grass.
    "built_min": 0.25,
    "water_wetland_min": 0.35,
    "bare_min": 0.30,
    "woody_min": 0.43,
    "grass_min": 0.00,  # combined with woody_grass_margin=0.00, reduces to "grass_prob >= woody_prob"
    "woody_grass_margin": 0.00,  # no dominance gap required between woody vs. grass
    "natural_min": 0.30,  # "mixed natural habitat" catch-all; no margin restriction (true fallback)
    "top1_min": 0.26,  # DW's own confidence proxy; sand/bare/arid surfaces depress this by scoring
    # ambiguously across several classes at once
}
DW_HABITAT_CLASS_CODES = list(
    range(1, 9)
)  # classify_habitat never emits 0 (NoData/outside AOI)
DW_HABITAT_CLASS_LABELS = {
    1: "Woody",
    2: "Grassland",
    3: "Mixed natural",
    4: "Cropland",
    5: "Built",
    6: "Bare/degraded",
    7: "Water/flooded veg",
    8: "Uncertain",
}

DW_PRESSURE_THRESHOLDS = {"moderate_min": 0.35, "high_min": 0.55}
DW_PRESSURE_CLASS_CODES = [0, 1, 2]
DW_PRESSURE_CLASS_LABELS = {0: "Low", 1: "Moderate", 2: "High"}

# All from-class x to-class combinations of the 8 habitat classes.
DW_TRANSITION_CODES = [
    f * 10 + t for f in DW_HABITAT_CLASS_CODES for t in DW_HABITAT_CLASS_CODES
]

# Connectivity-mask thresholds feeding the natural-habitat/high-quality-source evidence layers.
DW_CONNECTIVITY_THRESHOLDS = {
    "natural_prob_min": 0.60,
    "conversion_pressure_max": 0.30,
    "top1_prob_min": 0.28,
}

# Visualization presets
DW_HABITAT_CLASS_VIS = {
    "min": 0,
    "max": 8,
    "palette": [
        "#cccccc",  # 0 nodata
        "#397d49",  # 1 woody
        "#e7df44",  # 2 grassland
        "#a3c586",  # 3 mixed natural
        "#e49635",  # 4 cropland
        "#c4281b",  # 5 built
        "#a59b8f",  # 6 bare/degraded
        "#419bdf",  # 7 water/flooded vegetation
        "#b39fe1",  # 8 uncertain
    ],
}
DW_PRESSURE_VIS = {
    "min": 0,
    "max": 2,
    "palette": ["#1a9850", "#fee08b", "#d73027"],
}
# transition_code = from_class * 10 + to_class (11-88). NOT a severity scale -- color is driven
# mainly by the FROM class (tens digit); the ramp is a visual differentiator only.
DW_TRANSITION_VIS = {
    "min": 11,
    "max": 88,
    "palette": [
        "#800026",
        "#f03b20",
        "#fd8d3c",
        "#ffffb2",
        "#c7e9b4",
        "#41b6c4",
    ],
}

#################### PRODUCTIVITY & DEGRADATION TIME SERIES (LANDTRENDR) ##########################
EXPORT_FOLDER = "CERK_Enarau_Objective2_ProductivityDegradation"

# Sensor record start years (native data availability, not a study-window choice).
LANDSAT_YEAR_START = 1984
HLS_YEAR_START = 2015
S2_YEAR_START = 2017
YEAR_END = 2025  # last complete year as of this repo's current date

SEASON_MONTHS = {
    "wet": (3, 5),
    "dry": (7, 10),
    "annual": (1, 12),
}  # each season's inclusive last month

# eetools.utils.get_date_window's season_months values are the exclusive upper-bound month
# (ee.Date.fromYMD(year_end, end_month, 1)), one past SEASON_MONTHS's inclusive last month above.
EETOOLS_SEASON_MONTHS = {
    season: (start, end + 1)
    for season, (start, end) in SEASON_MONTHS.items()
    if season != "annual"
}

# Headline multi-year periods -- distinct from DW_PERIODS above, which uses different year ranges
# since Dynamic World only starts mid-2015.
PERIODS = {
    "baseline": (1984, 2000),  # long-term historical reference (Landsat only)
    "pre": (2016, 2021),  # recent pre-Enarau baseline
    "current": (2022, 2025),  # post-establishment / current complete period
}

# Minimum valid_obs_count thresholds per season type -- starting values, not calibrated against
# visual QA (same caveat as DW_MIN_OBS_*). HLS borrows the Landsat thresholds.
MIN_OBS = {
    "landsat": {"wet": 2, "dry": 2, "annual": 4},
    "hls": {"wet": 2, "dry": 2, "annual": 4},
    "sentinel2": {"wet": 3, "dry": 3, "annual": 6},
}

# Index bands common to every sensor (eetools.sensors.indices.INDEX_REGISTRY). NDVI and MNDWI are
# also requested purely to satisfy eetools' water-masking precondition -- housekeeping bands,
# dropped before composites/exports.
WATER_MASK_HOUSEKEEPING_BANDS = ["MNDWI"]
INDEX_BANDS_COMMON = ["NDVI", "EVI2", "MSAVI2", "NDMI", "NBR", "NBR2", "BSI"]
# Sentinel-2-only red-edge indices -- only computable where the band map has a red-edge band.
S2_INDEX_BANDS_EXTRA = ["NDRE", "CIred_edge"]

VALID_OBS_BAND = "valid_obs_count"

# LandTrendr run_params intentionally omitted: eetools.constants.LANDTRENDR_DEFAULT_RUN_PARAMS
# already matches this project's starting values (maxSegments=6, spikeThreshold=0.9,
# vertexCountOvershoot=3, preventOneYearRecovery=True, recoveryThreshold=0.25, pvalThreshold=0.05,
# bestModelProportion=0.75, minObservationsNeeded=6).
LANDTRENDR_YEAR_START = 1984
LANDTRENDR_YEAR_END = 2025
LANDTRENDR_SEASON_DAYS_DRY = ("07-01", "10-31")  # matches SEASON_MONTHS["dry"]
LANDTRENDR_SEASON_DAYS_WET = ("03-01", "05-31")  # matches SEASON_MONTHS["wet"]
LANDTRENDR_SEGMENTATION_INDEX = "NBR"
# eetools.landtrendr accepts any INDEX_REGISTRY index computable from the Landsat common bands as
# an FTV band -- CIred_edge/NDRE excluded since Landsat has no red-edge band.
LANDTRENDR_FTV_INDICES = ["NDMI", "MSAVI2", "BSI"]

# Complementary run: segments on wet-season MSAVI2 instead of dry-season NBR, to catch
# productivity decline / sparse-vegetation-cover loss the woody-condition-oriented NBR run
# under-detects (see notes.md). NBR/NDMI/BSI ride as FTV bands at the MSAVI2 vertex years.
LANDTRENDR_MSAVI2SEG_SEGMENTATION_INDEX = "MSAVI2"
LANDTRENDR_MSAVI2SEG_FTV_INDICES = ["NBR", "NDMI", "BSI"]

LANDTRENDR_RECENT_WINDOWS = {
    "disturbance": [(2016, 2025), (2022, 2025)],
    "recovery": [(2016, 2025)],
}

#################### AIRBUS 1M RANDOM FOREST LAND-COVER CLASSIFIER ##########################
# Standalone high-resolution (1 m, 4-band Airbus) classifier, independent of the Dynamic
# World-derived DW_HABITAT_CLASS_LABELS above. Raw inputs (the 4-band mosaic and training
# GeoPackage) are multi-GB and live outside this repo -- see notes.md for the full workflow.
# Training schema splits cultivated into two spectrally-distinct subclasses (cultivated_a/b, e.g.
# active vs. bare/harvested cropland) to aid separation from bareground/shrubland;
# RF_FINAL_CLASS_LABELS collapses them back into one "cultivated" class for the delivered map.
RF_CLASS_LABELS = {
    1: "dense_forest",
    2: "bareground",
    3: "grassland",
    4: "cultivated_a",
    5: "cultivated_b",
    6: "shrubland",
    7: "water",
    8: "built",
}

# Final delivered classification schema -- matches the original (pre-split) 7-class scheme.
RF_FINAL_CLASS_LABELS = {
    1: "dense_forest",
    2: "bareground",
    3: "grassland",
    4: "cultivated",
    5: "shrubland",
    6: "water",
    7: "built",
}

# Maps RF_CLASS_LABELS (training) class IDs to RF_FINAL_CLASS_LABELS (delivered) class IDs.
RF_CLASS_REMAP = {1: 1, 2: 2, 3: 3, 4: 4, 5: 4, 6: 5, 7: 6, 8: 7}

# Crosswalk from RF_FINAL_CLASS_LABELS to DW_HABITAT_CLASS_LABELS, used to treat the RF map as
# ground truth for calibrating DW_HABITAT_THRESHOLDS. shrubland -> Woody, matching Dynamic
# World's own woody_prob = trees + shrub_and_scrub (no separate "shrubland" class there). DW's
# Mixed natural(3)/Uncertain(8) have no RF equivalent and never appear as a crosswalk value.
RF_TO_DW_HABITAT_CROSSWALK = {
    1: 1,  # dense_forest  -> Woody
    2: 6,  # bareground    -> Bare/degraded
    3: 2,  # grassland     -> Grassland
    4: 4,  # cultivated    -> Cropland
    5: 1,  # shrubland     -> Woody
    6: 7,  # water         -> Water/flooded veg
    7: 5,  # built         -> Built
}

RF_RASTER_NODATA = 65535  # Airbus mosaic NoData value
RF_CLASSIFICATION_NODATA = (
    255  # output raster NoData; does not overlap class IDs 1-8
)
RF_RANDOM_SEED = 42
RF_TEST_FRACTION = 0.20
RF_MAX_PIXELS_PER_POLYGON = 150
RF_PARAMS = {
    "n_estimators": 500,
    "max_features": "sqrt",
    "min_samples_leaf": 1,
    "class_weight": "balanced_subsample",
    "n_jobs": -1,
    "random_state": RF_RANDOM_SEED,
}

#################### CONNECTIVITY VEGETATION CONDITION (RESISTANCE MODEL C INPUT) ####################
# Recent (non-historical) wet/dry vegetation-condition composite feeding the connectivity
# analysis's condition-adjusted Resistance Model C -- a single current-period snapshot, distinct
# from the full historical LandTrendr suite above. Built by
# scripts/python/notebooks/connectivity_condition_composite.ipynb, reusing the same eetools
# Sentinel-2 collection builder and PERIODS/SEASON_MONTHS constants already established above, at
# S2 native 10m (aggregated to the 30m connectivity master grid on the R side, not here).
CONNECTIVITY_CONDITION_EXPORT_FOLDER = (
    "CERK_Enarau_Objective4_ConditionComposite"
)
CONNECTIVITY_CONDITION_PERIOD = PERIODS["current"]  # (2022, 2025)

# MSAVI2 (not NDVI) for productivity -- this AOI is savanna/sparse-canopy, where MSAVI2's
# soil-brightness correction outperforms NDVI (same choice as the LandTrendr MSAVI2 run above).
# NDMI for moisture, BSI for bare soil (inverted before weighting -- high BSI = more bare/degraded).
CONNECTIVITY_CONDITION_PRODUCTIVITY_INDEX = "MSAVI2"
CONNECTIVITY_CONDITION_MOISTURE_INDEX = "NDMI"
CONNECTIVITY_CONDITION_BARE_SOIL_INDEX = "BSI"
CONNECTIVITY_CONDITION_SCORE_WEIGHTS = {
    "productivity": 0.40,
    "moisture": 0.35,
    "inverse_bare_soil": 0.25,
}
# Robust-percentile clamp-normalize bounds for scaling each raw index to 0-1 before weighting --
# not yet calibrated beyond this starting choice.
CONNECTIVITY_CONDITION_PERCENTILE_BOUNDS = (5, 95)

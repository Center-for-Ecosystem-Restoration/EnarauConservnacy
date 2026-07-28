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
# Manually-downloaded Objective 1 (Dynamic World) raster exports -- Drive folder
# DW_EXPORT_FOLDER (below) is the source of truth; these are not re-exported here, just the local
# landing folder Objective 3's R scripts read from after a manual Drive download, same convention
# as outputs/tables/ for the CSVs. Not an R-importable constant -- scripts/r/00_config.R mirrors
# this path literally since R cannot `import config.py`.
DW_RASTER_INPUT_DIR = RASTER_DIR / "dynamic_world"

# Output directory names
OUTPUT_DIRS = {
    "plots": PLOTS_DIR,
    "landscape_metrics": LANDSCAPE_RASTER_DIR,
    "tables": TABLES_DIR,
    "rasters": RASTER_DIR,
    "vectors": VECTORS_DIR,
    "rf_hab_classifier": RF_CLASSIFIER_DIR,
}

#################### AOI BOUNDARIES ##########################
AOI_PATHS = {
    "enarau": DATA_DIR / "enarau_conservancy.geojson",
    "mbokishi": DATA_DIR / "mbokishi_conservancy.geojson",
    "phase_1_corridor": DATA_DIR / "phase_1_corridor.geojson",
    "phase_2_corridor": DATA_DIR / "phase_2_corridor.geojson",
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

#################### PROJECT-WIDE SETTINGS ##########################
# Single project-wide CRS, used by every objective's notebook -- confirmed 2026-07-06 as WGS 84
# / UTM zone 36S. The Objective 1 plan document's own EPSG:32637 (UTM zone 37N) is the wrong
# hemisphere for this AOI (~35.3°E, ~1.0-1.1°S); propagate this correction rather than
# re-verifying it per objective.
PROJECT_CRS = "EPSG:32736"

#################### DYNAMIC WORLD HISTORICAL CHANGE (Objective 1) ##########################
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
# -- visual QA after round 1 still showed a moderate amount of masked (no-class) pixels. valid_obs_count is a
# per-pixel count of cloud-free Sentinel-2 acquisitions in the window; the wet season in
# particular (Mar-May, the rainiest months) frequently doesn't clear more than 1-2 cloud-free
# passes at this AOI. The plan itself (objective-1 doc, §6) anticipates this: "Adjust these
# thresholds if cloud masking or image availability is too restrictive." At min_obs=1 the
# "composite" is effectively whatever single image was available -- still transparently a
# median, just over a window of 1, and still not a final calibration; revisit against
# high-resolution imagery per the plan's open questions.

DW_MIN_OBS_ANNUAL = 3
DW_MIN_OBS_SEASONAL = 1
DW_COVERAGE_WARNING_PCT = 60  # -- QA/reporting threshold only (see coverage_flag); does not mask any pixels

# Habitat classification thresholds -- round 3 recalibration (2026-07-28), the first
# ground-truth-quantitative pass (rounds 1-2 were ad hoc visual QA only). Calibrated against a
# genuine ground-truth layer -- a random-forest classification from 1m 4-band Airbus aerial
# imagery (outputs/rf_hab_classifier/, RF_TO_DW_HABITAT_CROSSWALK below) -- via a local numpy
# reimplementation of classify_habitat() in scripts/python/notebooks/calibrate_habitat_thresholds.ipynb:
# a coordinate-ascent search over all 9 thresholds, maximizing macro-F1 (per-class harmonic mean
# of recall/precision, averaged across classes with RF reference pixels). Improved kappa
# 0.325->0.407 and overall accuracy 0.581->0.639 against the RF ground truth. The chosen values
# were then re-run through the REAL Earth Engine classify_habitat() (not just the local
# reimplementation) for one current-period confirmation export and found to match the local
# reimplementation at 100.0000% pixel agreement (0 disagreeing pixels of 1,644,812) -- the
# accepted risk of the two implementations drifting apart did not materialize.
#
# Two classes remain effectively unclassifiable by ANY threshold choice here, for two different,
# diagnosed reasons (see the calibration notebook's own diagnostic section for the full numbers) --
# not a gap in this calibration pass, a limitation of classify_habitat()'s rule design and/or this
# AOI's spectral reality:
#   - Bare/degraded: at real RF "bareground" pixels, the raw `bare` DW band averages only ~0.08,
#     and `crops`/`built` outscore it 87% of the time at the same pixel -- the rule's own
#     dominance check (bare.gt(crops).And(bare.gt(built))) fails on most true bare pixels
#     regardless of bare_min. This AOI's dry/heavily-grazed ground reads to Dynamic World as
#     low-vigor crops/grass, not exposed soil. Fixing this needs a classify_habitat() rule-logic
#     change (e.g. dropping/loosening the dominance check), not a threshold change.
#   - Water/flooded veg: true water pixels average water_wetland_prob of only ~0.14 against this
#     threshold of 0.35, which looks under-thresholded from band stats alone -- but water is
#     extremely rare here (2,045 RF reference pixels, ~0.1-0.2% of scored pixels), so lowering the
#     threshold trades a small water-recall gain for outsized precision losses on the much larger
#     Woody/Grassland/Cropland classes at every value tested; 0.35 empirically maximizes macro-F1.
#
# A parallel diagnostic checked whether comparing a 2022-2025 4-year composite against a
# single-year-2025 ground truth (temporal mismatch) was inflating the apparent miscalibration --
# it was not: a single-year-2025 DW composite scored WORSE across every metric (macro-F1
# 0.458->0.354) than the 2022-2025 composite used for the real calibration, most likely because a
# single year pools far fewer Sentinel-2 acquisitions into its median, making it a noisier
# per-pixel estimate despite being temporally matched to the ground truth. The 2022-2025 composite
# (the one actually used throughout this pipeline) remains the right calibration target.
#
# Not final: calibrated against one ground-truth source at one point in time; the two structural
# gaps above are known and unresolved. Revisit if a second ground-truth source becomes available,
# or if classify_habitat()'s rule logic changes.


# *** The classification test is probability_band.gte(threshold)Lowering the threshold makes that comparison true for more pixels, so more pixels get assigned to that class.
DW_HABITAT_THRESHOLDS = {
    "crops_min": 0.14,  # -- crops is a single raw DW band,
    # while natural_prob/woody_prob are SUMS of 2-3 bands; since all 9 class probabilities sum
    # to 1 per pixel, an aggregated band starts from a structurally higher ceiling than any
    # single band, so a similar absolute floor systematically favors natural/woody/grass over
    # crops even when crops is the clear plurality. RISK: crops has the highest effective
    # precedence (see classify_habitat), so this floor alone decides cropland with no
    # competing-signal check -- the ground-truth search pushed this well below round 2's 0.28,
    # which raised Cropland recall substantially (0.082->0.398); re-check Mbokishi (the
    # reference/intact-habitat site) for false-positive cropland if this ever needs revisiting.
    "built_min": 0.25,  # -- built-up pixels are often small/mixed, per the plan's own note;
    # lowered from round 2's 0.38 by the ground-truth search.
    "water_wetland_min": 0.35,  # -- unchanged from round 2; the ground-truth search confirmed
    # this is macro-F1-optimal despite looking under-thresholded from raw band stats alone (see
    # the round-3 note above -- water is too rare here for a lower threshold to pay off).
    "bare_min": 0.30,  # -- unchanged from round 2; not the binding constraint for Bare/degraded
    # (see the round-3 note above -- this class fails the rule's dominance check structurally,
    # not a threshold problem).
    "woody_min": 0.43,
    "grass_min": 0.00,  # -- combined with woody_grass_margin=0.00 below, the grass rule reduces
    # to "grass_prob >= woody_prob" with no absolute floor -- a pixel with real but very low
    # vegetation signal on both bands can now be called Grassland purely on which one is larger.
    # Empirically the macro-F1-maximizing choice against ground truth; watch for implausible
    # grassland calls in very low-signal (e.g. bare-adjacent) areas if this AOI's composition
    # changes materially.
    "woody_grass_margin": 0.00,  # -- no dominance gap required between woody vs. grass (round 2
    # used 0.06); see grass_min's note above for the combined effect.
    "natural_min": 0.30,  # -- unchanged from round 2; the "mixed natural habitat"
    # catch-all; a true fallback (no margin restriction, see notebook classify_habitat) so this
    # is the main lever for how much moderate-confidence vegetation signal counts as classifiable
    "top1_min": 0.26,  # -- DW confidence proxy; sand/bare/arid surfaces
    # are known to depress top1_prob by scoring across multiple classes at once (see
    # wiki/tools/dynamic-world.md). Nudged up slightly from round 2's 0.25 by the ground-truth search.
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

# Conversion-pressure thresholds
DW_PRESSURE_THRESHOLDS = {"moderate_min": 0.35, "high_min": 0.55}
DW_PRESSURE_CLASS_CODES = [0, 1, 2]
DW_PRESSURE_CLASS_LABELS = {0: "Low", 1: "Moderate", 2: "High"}

# All from-class x to-class combinations of the 8 habitat classes.
DW_TRANSITION_CODES = [
    f * 10 + t for f in DW_HABITAT_CLASS_CODES for t in DW_HABITAT_CLASS_CODES
]

# Objective 4 connectivity-mask thresholds (connectivity-input handoff amendment)
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
        "#88b053",  # 2 grassland
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
# transition_code = from_class * 10 + to_class, where both from_class and to_class are
# DW_HABITAT_CLASS_CODES (1-8, see DW_HABITAT_CLASS_VIS above for what each code means). "min"
# and "max" are the lowest/highest codes that can occur (11 = woody->woody i.e. persistent
# woody; 88 = uncertain->uncertain i.e. persistent uncertain) -- NOT a severity scale. EE/geemap
# linearly interpolates the 6 palette colors across that 11-88 numeric range, so color is driven
# mainly by the FROM class (the tens digit) and only subtly by the TO class (the ones digit,
# worth only ~1/77th of the range) -- the ramp is a visual differentiator, not a "loss=red,
# gain=green" encoding. Approximate stop values under linear interpolation (step = 77/5 = 15.4):

DW_TRANSITION_VIS = {
    "min": 11,
    "max": 88,
    "palette": [
        "#800026",  # ~11.0 -- from_class 1 (woody) origin, e.g. persistent woody (11)
        "#f03b20",  # ~26.4 -- from_class 2 (grassland) origin, e.g. grass->cropland (24)
        "#fd8d3c",  # ~41.8 -- from_class 4 (cropland) origin, e.g. cropland->woody recovery (41)
        "#ffffb2",  # ~57.2 -- from_class 5-6 (built/bare) origin
        "#c7e9b4",  # ~72.6 -- from_class 7 (water/flooded) origin
        "#41b6c4",  # ~88.0 -- from_class 8 (uncertain) origin, e.g. persistent uncertain (88)
    ],
}

#################### PRODUCTIVITY & DEGRADATION TIME SERIES (Objective 2) ##########################
EXPORT_FOLDER = "CERK_Enarau_Objective2_ProductivityDegradation"

# Sensor record start years (native data availability, not a study-window choice).
LANDSAT_YEAR_START = 1984
HLS_YEAR_START = 2015
S2_YEAR_START = 2017
# Last COMPLETE year as of this repo's current date (2026-07-08): the 2026 wet season
# (Mar-May) is already complete but the 2026 dry season (Jul-Oct) is still in progress, so every
# sensor/season composite stops at 2025 -- keeping all three seasons' year ranges identical
# avoids a partial-season 2026 composite silently looking comparable to a complete one. Revisit
# once the 2026 dry season closes (after ~Nov 2026) if an earlier wet-2026 composite is wanted.
YEAR_END = 2025

SEASON_MONTHS = {"wet": (3, 5), "dry": (7, 10), "annual": (1, 12)}

# Headline multi-year periods (plan Sec.4) -- distinct from Objective 1's DW_PERIODS, which uses
# different year ranges since Dynamic World only starts mid-2015.
PERIODS = {
    "baseline": (1984, 2000),  # long-term historical reference (Landsat only)
    "pre": (2016, 2021),  # recent pre-Enarau baseline
    "current": (2022, 2025),  # post-establishment / current complete period
}

# Minimum valid_obs_count thresholds per season type -- starting values (plan Sec.6.4 for
# Landsat, Sec.8.2 for Sentinel-2; HLS has no plan-specified threshold, so it borrows the Landsat
# values as a starting point). Not yet calibrated against visual QA, same caveat as
# config.DW_MIN_OBS_*.
MIN_OBS = {
    "landsat": {"wet": 2, "dry": 2, "annual": 4},
    "hls": {"wet": 2, "dry": 2, "annual": 4},
    "sentinel2": {"wet": 3, "dry": 3, "annual": 6},
}

# Index bands common to every sensor, all present in eetools.sensors.indices.INDEX_REGISTRY
# (including MSAVI2 as of the eetools update that added calc_msavi2/calc_ci_red_edge). NDVI and
# MNDWI are requested from every sensor collection builder purely to satisfy eetools'
# water-masking precondition (sensors.masking.validate_water_mask_selection); MNDWI is dropped
# before composites/exports.
WATER_MASK_HOUSEKEEPING_BANDS = ["MNDWI"]
INDEX_BANDS_COMMON = ["NDVI", "EVI2", "MSAVI2", "NDMI", "NBR", "NBR2", "BSI"]
# Sentinel-2-only red-edge indices (plan Sec.5), both from eetools' INDEX_REGISTRY -- only
# computable where the band map has a red-edge band, i.e. Sentinel-2 (HLS/Landsat have none).
S2_INDEX_BANDS_EXTRA = ["NDRE", "CIred_edge"]

VALID_OBS_BAND = "valid_obs_count"

# LandTrendr (plan Sec.11) -- run_params intentionally omitted: eetools.constants.
# LANDTRENDR_DEFAULT_RUN_PARAMS already matches the plan's own LANDTRENDR_PARAMS starting values
# exactly (maxSegments=6, spikeThreshold=0.9, vertexCountOvershoot=3, preventOneYearRecovery=True,
# recoveryThreshold=0.25, pvalThreshold=0.05, bestModelProportion=0.75, minObservationsNeeded=6),
# so no override is needed.
LANDTRENDR_YEAR_START = 1984
LANDTRENDR_YEAR_END = 2025
LANDTRENDR_SEASON_DAYS_DRY = (
    "07-01",
    "10-31",
)  # dry season, matches SEASON_MONTHS["dry"]
LANDTRENDR_SEASON_DAYS_WET = (
    "03-01",
    "05-31",
)  # wet season, matches SEASON_MONTHS["wet"] -- plan Sec.11.6 complementary MSAVI2 run
LANDTRENDR_SEGMENTATION_INDEX = "NBR"
# eetools.landtrendr now accepts any INDEX_REGISTRY index computable from the Landsat common
# bands as an FTV band (generalized beyond the old NBR/NDVI/NDMI-only allowlist), so MSAVI2 and
# BSI (the plan's own Sec.11.2 request) are included alongside NDMI -- CIred_edge/NDRE are not
# usable here since Landsat has no red-edge band.
LANDTRENDR_FTV_INDICES = ["NDMI", "MSAVI2", "BSI"]

# Plan Sec.11.6 -- complementary run segmented on wet-season MSAVI2 instead of dry-season NBR,
# to catch productivity decline / sparse-vegetation-cover loss that the woody-condition-oriented
# NBR segmentation under-detects. NBR, NDMI, and BSI are fit as FTV bands at the MSAVI2 vertex
# years (not re-segmented independently) -- same set the plan's Sec.11.6 calls for. Segmentation
# orientation resolves the plan's own open question: eetools.constants.LANDTRENDR_DIST_DIR has no
# MSAVI2 entry, so it falls back to LANDTRENDR_DEFAULT_DIST_DIR (-1), which is correct since
# MSAVI2 is vegetation-positive like NDVI/NBR/NDMI (loss = negative delta).
LANDTRENDR_MSAVI2SEG_SEGMENTATION_INDEX = "MSAVI2"
LANDTRENDR_MSAVI2SEG_FTV_INDICES = ["NBR", "NDMI", "BSI"]

LANDTRENDR_RECENT_WINDOWS = {
    "disturbance": [(2016, 2025), (2022, 2025)],
    "recovery": [(2016, 2025)],
}

#################### AIRBUS 1M RANDOM FOREST LAND-COVER CLASSIFIER ##########################
# Standalone high-resolution (1 m, 4-band Airbus) classifier -- separate from Objective 1's
# Dynamic World-derived DW_HABITAT_CLASS_LABELS above (different scheme, different source
# imagery). Raw inputs (the 4-band mosaic and training GeoPackage) are multi-GB and live outside
# the repo on the analyst's machine; only output-side config lives here, per
# scripts/python/notebooks/hab_class.ipynb, which sets the raster/GeoPackage paths itself.
# Training/model schema -- cultivated is split into two spectrally-distinct subclasses
# (cultivated_a/cultivated_b, e.g. active vs. bare/harvested cropland) to give the classifier a
# better shot at separating them from bareground and shrubland; RF_FINAL_CLASS_LABELS collapses
# them back into a single "cultivated" class for the delivered classification map (see
# RF_CLASS_REMAP and hab_class.ipynb's combine-classes step).
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

# Maps RF_CLASS_LABELS (training) class IDs to RF_FINAL_CLASS_LABELS (delivered) class IDs --
# cultivated_a and cultivated_b (4, 5) both collapse to "cultivated" (4); everything after them
# shifts down by one to close the gap.
RF_CLASS_REMAP = {1: 1, 2: 2, 3: 3, 4: 4, 5: 4, 6: 5, 7: 6, 8: 7}

# Crosswalk from RF_FINAL_CLASS_LABELS (this classifier's delivered 7-class scheme) to
# DW_HABITAT_CLASS_LABELS (Objective 1's 8-class scheme), for using the RF map as ground truth to
# calibrate DW_HABITAT_THRESHOLDS (scripts/python/notebooks/calibrate_habitat_thresholds.ipynb).
# shrubland -> Woody(1), matching Dynamic World's own woody_prob = trees + shrub_and_scrub (this
# repo's habitat scheme has no separate "shrubland" class). DW's Mixed natural(3)/Uncertain(8)
# have no RF equivalent and never appear as a crosswalk value -- they can still appear as
# classify_habitat() predictions, just with no ground-truth pixels to score producer's accuracy
# against (see calibrate_habitat_thresholds.ipynb's compare_to_reference()).
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

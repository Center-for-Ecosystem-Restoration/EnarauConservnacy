# Step 07 (Objective 4): land-cover permeability/confidence, resistance Models A/B/C, and
# source-strength surfaces. RUN AS: cd scripts/r && Rscript 07_build_resistance_source_surfaces.R
# (see 00_config.R for the renv/cwd requirement).
#
# Requires 06_prepare_connectivity_inputs.R to have already run (reads CONNECTIVITY_RASTER_DIR).
# No fence data exists yet, so Resistance Model D isn't built here; only the neutral
# riparian-factor scenario feeds default Model C (facilitation scenario is written alongside for
# later sensitivity testing, not consumed by default).

source("00_config.R")
source("R/io.R")
source("R/grid.R")
source("R/qa.R")
source("R/resistance.R")

read_connectivity_raster <- function(name) {
  terra::rast(file.path(CONNECTIVITY_RASTER_DIR, paste0(name, ".tif")))
}

message("=== 07_build_resistance_source_surfaces: loading step-06 outputs ===")
fraction_stack <- read_connectivity_raster("landcover_class_fractions_30m")
natural_fraction <- read_connectivity_raster("natural_cover_fraction_30m")
built_fraction <- read_connectivity_raster("built_fraction_30m")
settlement_pressure_r <- read_connectivity_raster("settlement_pressure_30m")
road_pressure_r <- read_connectivity_raster("road_pressure_30m")
slope_scaled_r <- read_connectivity_raster("slope_scaled_30m")
riparian_natural_cover_r <- read_connectivity_raster("riparian_natural_cover_30m")
condition_current_r <- read_connectivity_raster("condition_score_current_30m")

master_grid <- build_master_grid()

message("=== Land-cover permeability + confidence ===")
landcover_perm <- landcover_permeability(fraction_stack)
confidence_crosswalk <- build_landcover_confidence_crosswalk()
print(confidence_crosswalk)
landcover_conf <- landcover_confidence(fraction_stack, confidence_crosswalk)

message("=== Human/road/terrain permeability + riparian-factor scenarios ===")
human_perm <- clamp01(1 - settlement_pressure_r)
names(human_perm) <- "human_permeability"
road_perm <- clamp01(1 - road_pressure_r)
names(road_perm) <- "road_permeability"
terrain_perm <- clamp01(1 - slope_scaled_r)
names(terrain_perm) <- "terrain_permeability"
riparian_neutral <- riparian_factor_scenario(riparian_natural_cover_r, "neutral")
riparian_facilitation <- riparian_factor_scenario(riparian_natural_cover_r, "facilitation")

message("=== Resistance Models A/B/C (neutral riparian scenario) ===")
resistance_models <- build_resistance_models(
  landcover_perm = landcover_perm, human_perm = human_perm, road_perm = road_perm,
  condition = condition_current_r, terrain_perm = terrain_perm,
  riparian_factor = riparian_neutral, built_fraction = built_fraction
)

message("=== Source strength (primary + conservative) ===")
source_strength <- build_source_strength(
  natural_fraction = natural_fraction, condition = condition_current_r, human_perm = human_perm,
  built_fraction = built_fraction, settlement_pressure = settlement_pressure_r,
  road_pressure = road_pressure_r
)

message("=== QA: grid alignment + finite-value check ===")
all_layers <- list(
  landcover_permeability = landcover_perm, landcover_confidence = landcover_conf,
  human_permeability = human_perm, road_permeability = road_perm, terrain_permeability = terrain_perm,
  riparian_factor_neutral = riparian_neutral, riparian_factor_facilitation = riparian_facilitation,
  resistance_A = resistance_models[["resistance_A"]], resistance_B = resistance_models[["resistance_B"]],
  resistance_C = resistance_models[["resistance_C"]],
  source_primary = source_strength[["source_primary"]], source_conservative = source_strength[["source_conservative"]]
)
qa_table <- check_connectivity_grid_alignment(all_layers, master_grid)
readr::write_csv(qa_table, file.path(TABLES_DIR, "connectivity_resistance_source_qa.csv"))

message("=== Writing rasters to ", CONNECTIVITY_RASTER_DIR, " ===")
terra::writeRaster(landcover_perm, file.path(CONNECTIVITY_RASTER_DIR, "landcover_permeability_30m.tif"), overwrite = TRUE)
terra::writeRaster(landcover_conf, file.path(CONNECTIVITY_RASTER_DIR, "landcover_confidence_30m.tif"), overwrite = TRUE)
terra::writeRaster(riparian_neutral, file.path(CONNECTIVITY_RASTER_DIR, "riparian_factor_neutral_30m.tif"), overwrite = TRUE)
terra::writeRaster(riparian_facilitation, file.path(CONNECTIVITY_RASTER_DIR, "riparian_factor_facilitation_30m.tif"), overwrite = TRUE)
terra::writeRaster(resistance_models, file.path(CONNECTIVITY_RASTER_DIR, "resistance_models_30m.tif"), overwrite = TRUE)
terra::writeRaster(source_strength, file.path(CONNECTIVITY_RASTER_DIR, "source_strength_models_30m.tif"), overwrite = TRUE)

message("=== 07_build_resistance_source_surfaces complete ===")

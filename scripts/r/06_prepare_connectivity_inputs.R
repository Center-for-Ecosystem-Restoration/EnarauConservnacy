# Step 06 (Objective 4): builds the 30m connectivity master grid and aligns every raw input onto
# it -- land-cover class fractions, settlement/road pressure, river proximity, riparian buffer,
# slope/terrain ruggedness, and the vegetation-condition composite. Resistance/source-strength
# surfaces are built separately in 07. RUN AS: cd scripts/r && Rscript
# 06_prepare_connectivity_inputs.R (see 00_config.R for the renv/cwd requirement).
#
# No fence/gate data exists yet, so fence_barrier_30m.tif isn't produced here; Resistance Model D
# stays deferred until that data is mapped.

source("00_config.R")
source("R/io.R")
source("R/grid.R")
source("R/landcover.R")
source("R/pressure.R")
source("R/qa.R")

message("=== 06_prepare_connectivity_inputs: building master grid ===")
master_grid <- build_master_grid()
message(sprintf(
  "Master grid: %dx%d cells @ %dm, extent %s, CRS %s",
  dim(master_grid)[1], dim(master_grid)[2], CONNECTIVITY_GRID_RESOLUTION_M,
  paste(as.vector(terra::ext(master_grid)), collapse = ", "),
  terra::crs(master_grid, describe = TRUE)$code
))

message("=== Land-cover class fractions (10m -> 30m) ===")
lc_path <- file.path(RF_CLASSIFIER_DIR, "airbus_landcover_classification_10m_clipped.tif")
fraction_stack <- class_fraction_stack(lc_path, master_grid)
natural_fraction <- grouped_fraction(fraction_stack, NATURAL_LC_CLASSES)
names(natural_fraction) <- "natural_fraction"
cultivated_fraction <- grouped_fraction(fraction_stack, CULTIVATED_LC_CLASSES)
names(cultivated_fraction) <- "cultivated_fraction"
built_fraction <- grouped_fraction(fraction_stack, BUILT_LC_CLASSES)
names(built_fraction) <- "built_fraction"
water_fraction <- grouped_fraction(fraction_stack, WATER_LC_CLASSES)
names(water_fraction) <- "water_fraction"

message("=== Settlement pressure ===")
settlement_pressure_r <- settlement_pressure(
  CONNECTIVITY_INPUT_PATHS$settlement_heatmap, built_fraction, master_grid
)

message("=== Road pressure ===")
road_pressure_r <- road_pressure(CONNECTIVITY_INPUT_PATHS$roads, master_grid)

message("=== River proximity / riparian buffer ===")
river_proximity_r <- feature_distance(CONNECTIVITY_INPUT_PATHS$streams, master_grid)
names(river_proximity_r) <- "river_proximity_m"
riparian_buffer_r <- riparian_buffer(river_proximity_r)
# counted as natural cover only where natural_fraction >= 0.5 (dominance)
riparian_natural_cover_r <- riparian_buffer_r * (natural_fraction >= 0.5)
names(riparian_natural_cover_r) <- "riparian_natural_cover"

message("=== Slope + terrain ruggedness ===")
slope_aligned_r <- align_to_grid(terra::rast(CONNECTIVITY_INPUT_PATHS$slope), master_grid, method = "bilinear")
names(slope_aligned_r) <- "slope_degrees"
slope_scaled_r <- slope_scaled(CONNECTIVITY_INPUT_PATHS$slope, master_grid)
terrain_ruggedness_r <- terrain_ruggedness(CONNECTIVITY_INPUT_PATHS$elevation, master_grid)

message("=== Vegetation-condition composite (10m -> 30m) ===")
condition_scores <- list(
  current = CONNECTIVITY_INPUT_PATHS$condition_score_current,
  wet = CONNECTIVITY_INPUT_PATHS$condition_score_wet,
  dry = CONNECTIVITY_INPUT_PATHS$condition_score_dry
)
condition_score_aligned <- lapply(condition_scores, function(path) {
  r <- terra::rast(path)[["condition_score"]]
  out <- align_to_grid(r, master_grid, method = "bilinear")
  names(out) <- "condition_score"
  out
})

message("=== QA: grid alignment + finite-value check across all derived layers ===")
all_layers <- c(
  list(
    natural_fraction = natural_fraction,
    cultivated_fraction = cultivated_fraction,
    built_fraction = built_fraction,
    water_fraction = water_fraction,
    settlement_pressure = settlement_pressure_r,
    road_pressure = road_pressure_r,
    river_proximity = river_proximity_r,
    riparian_buffer = riparian_buffer_r,
    riparian_natural_cover = riparian_natural_cover_r,
    slope_degrees = slope_aligned_r,
    slope_scaled = slope_scaled_r,
    terrain_ruggedness = terrain_ruggedness_r
  ),
  setNames(condition_score_aligned, paste0("condition_score_", names(condition_score_aligned)))
)
qa_table <- check_connectivity_grid_alignment(all_layers, master_grid)
readr::write_csv(qa_table, file.path(TABLES_DIR, "connectivity_input_alignment_qa.csv"))

message("=== Writing aligned rasters to ", CONNECTIVITY_RASTER_DIR, " ===")
terra::writeRaster(fraction_stack, file.path(CONNECTIVITY_RASTER_DIR, "landcover_class_fractions_30m.tif"), overwrite = TRUE)
terra::writeRaster(natural_fraction, file.path(CONNECTIVITY_RASTER_DIR, "natural_cover_fraction_30m.tif"), overwrite = TRUE)
terra::writeRaster(cultivated_fraction, file.path(CONNECTIVITY_RASTER_DIR, "cultivated_fraction_30m.tif"), overwrite = TRUE)
terra::writeRaster(built_fraction, file.path(CONNECTIVITY_RASTER_DIR, "built_fraction_30m.tif"), overwrite = TRUE)
terra::writeRaster(water_fraction, file.path(CONNECTIVITY_RASTER_DIR, "water_fraction_30m.tif"), overwrite = TRUE)
terra::writeRaster(settlement_pressure_r, file.path(CONNECTIVITY_RASTER_DIR, "settlement_pressure_30m.tif"), overwrite = TRUE)
terra::writeRaster(road_pressure_r, file.path(CONNECTIVITY_RASTER_DIR, "road_pressure_30m.tif"), overwrite = TRUE)
terra::writeRaster(river_proximity_r, file.path(CONNECTIVITY_RASTER_DIR, "river_proximity_30m.tif"), overwrite = TRUE)
terra::writeRaster(riparian_buffer_r, file.path(CONNECTIVITY_RASTER_DIR, "riparian_buffer_30m.tif"), overwrite = TRUE)
terra::writeRaster(riparian_natural_cover_r, file.path(CONNECTIVITY_RASTER_DIR, "riparian_natural_cover_30m.tif"), overwrite = TRUE)
terra::writeRaster(slope_aligned_r, file.path(CONNECTIVITY_RASTER_DIR, "slope_30m.tif"), overwrite = TRUE)
terra::writeRaster(slope_scaled_r, file.path(CONNECTIVITY_RASTER_DIR, "slope_scaled_30m.tif"), overwrite = TRUE)
terra::writeRaster(terrain_ruggedness_r, file.path(CONNECTIVITY_RASTER_DIR, "terrain_ruggedness_30m.tif"), overwrite = TRUE)
for (season in names(condition_score_aligned)) {
  terra::writeRaster(
    condition_score_aligned[[season]],
    file.path(CONNECTIVITY_RASTER_DIR, sprintf("condition_score_%s_30m.tif", season)),
    overwrite = TRUE
  )
}

message("=== 06_prepare_connectivity_inputs complete ===")
message(sprintf("Wrote %d raster files to %s", 13 + length(condition_score_aligned), CONNECTIVITY_RASTER_DIR))

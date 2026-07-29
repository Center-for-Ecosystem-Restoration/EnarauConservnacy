# Step 11 (Objective 4): consensus mapping, bottleneck/barrier candidates, protection/restoration
# priority, and patch-level importance scores (plan Sec.11-12).
#
# RUN AS: cd scripts/r && Rscript 11_consensus_priority_mapping.R
#
# Requires steps 07 (resistance/source-strength), 08 (patches/focal nodes), 09 (Omniscape, all 6
# scenarios), and 10 (Circuitscape pairwise + all-to-one) to have already run.

source("00_config.R")
source("R/io.R")
source("R/grid.R")
source("R/qa.R")
source("R/scoring.R")
source("R/consensus.R")

read_connectivity_raster <- function(name) {
  terra::rast(file.path(CONNECTIVITY_RASTER_DIR, paste0(name, ".tif")))
}

message("=== 11_consensus_priority_mapping: loading step-07/08/09/10 outputs ===")
resistance_c <- read_connectivity_raster("resistance_models_30m")[["resistance_C"]]
source_primary <- read_connectivity_raster("source_strength_models_30m")[["source_primary"]]
built_fraction <- read_connectivity_raster("built_fraction_30m")
settlement_pressure_r <- read_connectivity_raster("settlement_pressure_30m")

omniscape_dir <- file.path(CONNECTIVITY_OUTPUT_DIR, "omniscape")
scenario_labels <- vapply(OMNISCAPE_RUN_SET, function(spec) {
  radius_cells <- OMNISCAPE_RADII_CELLS[[spec$radius]]
  sprintf("%s_r%d%s", spec$model, radius_cells, if (spec$source == "conservative") "_conservative_source" else "")
}, character(1))

normalized_current_list <- lapply(scenario_labels, function(lbl) {
  terra::rast(file.path(omniscape_dir, lbl, "output", "normalized_cum_currmap.tif"))
})
names(normalized_current_list) <- scenario_labels

reference_normalized_current <- normalized_current_list[[PRIORITY_REFERENCE_SCENARIO]]
reference_flow_potential <- terra::rast(file.path(omniscape_dir, PRIORITY_REFERENCE_SCENARIO, "output", "flow_potential.tif"))

message("=== Consensus score across ", length(normalized_current_list), " Omniscape scenarios ===")
consensus_r <- consensus_score(normalized_current_list)
message(sprintf("Consensus score distribution: %s", paste(names(table(terra::values(consensus_r))), table(terra::values(consensus_r)), sep = "=", collapse = ", ")))

message("=== Bottleneck candidates (reference scenario: ", PRIORITY_REFERENCE_SCENARIO, ") ===")
bottlenecks <- bottleneck_candidates(reference_normalized_current, resistance_c, consensus_r)
message(sprintf(
  "Moderate: %d cells, High-confidence: %d cells",
  sum(terra::values(bottlenecks[["bottleneck_moderate"]]), na.rm = TRUE),
  sum(terra::values(bottlenecks[["bottleneck_high_confidence"]]), na.rm = TRUE)
))

message("=== Barrier candidates ===")
barriers <- barrier_candidates(resistance_c, reference_flow_potential, source_primary)
message(sprintf("Barrier candidate cells: %d", sum(terra::values(barriers), na.rm = TRUE)))

message("=== Protection + restoration priority ===")
protection <- protection_priority(source_primary, reference_normalized_current, resistance_c)
restoration <- restoration_priority(reference_flow_potential, resistance_c, built_fraction)
message(sprintf(
  "Protection priority cells: %d, Restoration priority cells: %d",
  sum(terra::values(protection), na.rm = TRUE), sum(terra::values(restoration), na.rm = TRUE)
))

message("=== QA: grid alignment check ===")
all_layers <- list(
  consensus_score = consensus_r, bottleneck_moderate = bottlenecks[["bottleneck_moderate"]],
  bottleneck_high_confidence = bottlenecks[["bottleneck_high_confidence"]],
  barrier_candidate = barriers, protection_priority = protection, restoration_priority = restoration
)
master_grid <- build_master_grid()
qa_table <- check_connectivity_grid_alignment(all_layers, master_grid)
readr::write_csv(qa_table, file.path(TABLES_DIR, "connectivity_consensus_priority_qa.csv"))

message("=== Writing consensus/priority rasters ===")
for (nm in names(all_layers)) {
  terra::writeRaster(all_layers[[nm]], file.path(CONNECTIVITY_RASTER_DIR, paste0(nm, "_30m.tif")), overwrite = TRUE)
}

message("=== Vector outputs (dissolved polygons) ===")
to_polygons <- function(binary_r) {
  poly <- terra::as.polygons(binary_r, dissolve = TRUE, na.rm = TRUE)
  poly <- poly[terra::values(poly)[, 1] == 1, ]
  if (nrow(poly) == 0) return(NULL)
  sf::st_as_sf(poly)
}
vector_outputs <- list(
  bottleneck_candidates = to_polygons(bottlenecks[["bottleneck_high_confidence"]]),
  barrier_candidates = to_polygons(barriers),
  protection_priority = to_polygons(protection),
  restoration_priority = to_polygons(restoration)
)
for (nm in names(vector_outputs)) {
  if (!is.null(vector_outputs[[nm]])) {
    sf::st_write(vector_outputs[[nm]], file.path(VECTORS_DIR, paste0("connectivity_", nm, ".gpkg")), delete_dsn = TRUE, quiet = TRUE)
  } else {
    message("  (no ", nm, " cells found -- skipping vector output)")
  }
}

message("=== Patch-level importance scores ===")
patch_table <- readr::read_csv(file.path(TABLES_DIR, "connectivity_patch_metrics_current.csv"), show_col_types = FALSE)
patch_poly <- terra::vect(sf::st_read(file.path(VECTORS_DIR, "connectivity_habitat_patches_current.gpkg"), quiet = TRUE)[, "patch_id"])

# mean/max Omniscape normalized_current per patch, across all 6 scenarios (fills in the
# mean_omniscape_current/max_omniscape_current columns step 08 deliberately left for this step).
omniscape_patch_stats <- Reduce(function(a, b) dplyr::left_join(a, b, by = "patch_id"), lapply(scenario_labels, function(lbl) {
  patch_current_stats(patch_poly, normalized_current_list[[lbl]], paste0("omniscape_current_", lbl))
}))
# Reference-scenario columns get the plan's own plain names (Sec.10.2); per-scenario detail kept too.
omniscape_patch_stats$mean_omniscape_current <- omniscape_patch_stats[[paste0("mean_omniscape_current_", PRIORITY_REFERENCE_SCENARIO)]]
omniscape_patch_stats$max_omniscape_current <- omniscape_patch_stats[[paste0("max_omniscape_current_", PRIORITY_REFERENCE_SCENARIO)]]

# Circuitscape all-to-one cumulative current per patch -- the plan's stepping-stone-position proxy
# (see R/consensus.R's compute_protection_importance() docs for why this replaces a Euclidean
# betweenness score here).
all_to_one_current <- terra::rast(file.path(CONNECTIVITY_OUTPUT_DIR, "circuitscape", "all_to_one", "cs_all_to_one_cum_curmap.tif"))
stepping_stone_stats <- patch_current_stats(patch_poly, all_to_one_current, "all_to_one_current")

patch_table <- patch_table |>
  dplyr::left_join(omniscape_patch_stats, by = "patch_id") |>
  dplyr::left_join(stepping_stone_stats, by = "patch_id")

# proximity_to_focal_linkage: linear decay from the corridor phases specifically (plan's
# restoration-importance component -- proximity to the linkage this whole objective targets),
# reusing R/scoring.R's distance_decay_score() and config's own CORRIDOR_PROXIMITY_DECAY_M.
corridor_sites <- do.call(rbind, lapply(c("corridor_p1", "corridor_p2"), function(sid) {
  b <- read_site_boundary(sid)
  sf::st_sf(site_id = sid, geometry = sf::st_geometry(sf::st_union(b)))
}))
patch_poly_sf <- sf::st_as_sf(patch_poly)
patch_table$corridor_proximity <- distance_decay_score(patch_poly_sf, corridor_sites)

patch_table$protection_importance_score <- compute_protection_importance(
  connectivity_contribution = patch_table$mean_omniscape_current,
  source_strength = patch_table$mean_natural_fraction * patch_table$mean_landcover_permeability,
  core_area_ha = patch_table$core_area_ha,
  stepping_stone_position = patch_table$mean_all_to_one_current,
  settlement_pressure = patch_table$mean_settlement_pressure
)
patch_table$restoration_importance_score <- compute_restoration_importance(
  current_or_flow_potential = patch_table$mean_omniscape_current,
  resistance = patch_table$mean_resistance_C,
  proximity_to_focal_linkage = patch_table$corridor_proximity
)

readr::write_csv(patch_table, file.path(TABLES_DIR, "connectivity_patch_importance_scores_current.csv"))

message("=== 11_consensus_priority_mapping complete ===")
message("Top 5 patches by protection_importance_score:")
print(patch_table[order(-patch_table$protection_importance_score), c("patch_id", "primary_site_id", "area_ha", "protection_importance_score")][1:5, ])
message("Top 5 patches by restoration_importance_score:")
print(patch_table[order(-patch_table$restoration_importance_score), c("patch_id", "primary_site_id", "area_ha", "restoration_importance_score")][1:5, ])

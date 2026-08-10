# Step 10 (Objective 4): Circuitscape pairwise + all-to-one runs on the focal nodes.
#
# RUN AS: cd scripts/r && Rscript 10_run_circuitscape.R
#
# Requires 07_build_resistance_source_surfaces.R and 08_habitat_patches_focal_nodes.R to have
# already run.
#
# Only does FAST prep here (focal-node point raster + INI configs) -- does NOT invoke Julia.
# Pairwise mode solves a GLOBAL circuit once per focal-node pair, and per step 09's experience a
# single scenario can run past what a blocking call should take, so each Julia invocation is
# launched separately and explicitly (see the run manifest this script stages).
#
# Uses Resistance Model C only, not all three models. Focal-node count is whatever
# 08_habitat_patches_focal_nodes.R selected (6 as of the 2026-07-29 settlement-heatmap fix) --
# don't hardcode an expected pair count here or downstream.

source("00_config.R")
source("R/io.R")
source("R/grid.R")
source("R/connectivity_run.R")

message("=== 10_run_circuitscape: loading step-07/08 outputs ===")
resistance_c <- terra::rast(file.path(CONNECTIVITY_RASTER_DIR, "resistance_models_30m.tif"))[["resistance_C"]]
master_grid <- build_master_grid()

focal_nodes <- sf::st_read(file.path(VECTORS_DIR, "connectivity_focal_nodes_current.gpkg"), quiet = TRUE)
message(nrow(focal_nodes), " focal nodes loaded: ", paste(focal_nodes$patch_id, collapse = ", "))

message("=== Building focal-node point raster (patch_id as the Circuitscape point ID) ===")
# guarantees a point inside the polygon (unlike a centroid, which can fall outside a concave patch)
focal_points <- sf::st_point_on_surface(focal_nodes)
points_raster <- terra::rasterize(terra::vect(focal_points), master_grid, field = "patch_id")
names(points_raster) <- "focal_node_id"

circuitscape_dir <- CIRCUITSCAPE_OUTPUT_DIR

habitat_path <- file.path(circuitscape_dir, "resistance_C.tif")
points_path <- file.path(circuitscape_dir, "focal_nodes.tif")
terra::writeRaster(resistance_c, habitat_path, overwrite = TRUE)
terra::writeRaster(points_raster, points_path, overwrite = TRUE, datatype = "INT4S")

message("=== Writing pairwise + all-to-one INI configs ===")
pairwise_dir <- file.path(circuitscape_dir, "pairwise")
all_to_one_dir <- file.path(circuitscape_dir, "all_to_one")

pairwise_config <- write_circuitscape_config(
  habitat_path = habitat_path, point_path = points_path,
  output_base = file.path(pairwise_dir, "cs_pairwise"),
  scenario = "pairwise", write_cur_maps = TRUE, write_cum_cur_map_only = FALSE
)
all_to_one_config <- write_circuitscape_config(
  habitat_path = habitat_path, point_path = points_path,
  output_base = file.path(all_to_one_dir, "cs_all_to_one"),
  scenario = "all-to-one", write_cur_maps = TRUE, write_cum_cur_map_only = FALSE
)

message("Staged configs:")
message("  pairwise:    ", pairwise_config)
message("  all-to-one:  ", all_to_one_config)
message("Not run automatically -- see this script's header comment. Launch each explicitly:")
message(sprintf('  "%s" -t%d "%s" "%s"', JULIA_BIN, JULIA_THREADS,
                file.path(JULIA_SCRIPTS_DIR, "run_circuitscape.jl"), pairwise_config))
message(sprintf('  "%s" -t%d "%s" "%s"', JULIA_BIN, JULIA_THREADS,
                file.path(JULIA_SCRIPTS_DIR, "run_circuitscape.jl"), all_to_one_config))

message("=== 10_run_circuitscape prep complete ===")

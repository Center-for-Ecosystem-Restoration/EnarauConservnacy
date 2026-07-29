# Step 10 (Objective 4): Circuitscape pairwise + all-to-one runs on the focal nodes (plan
# Sec.10.5).
#
# RUN AS: cd scripts/r && Rscript 10_run_circuitscape.R
#
# This script only does the FAST prep work: builds the focal-node point raster and writes the
# pairwise/all-to-one INI configs. It deliberately does NOT invoke Julia itself -- pairwise mode
# solves a GLOBAL circuit (not moving-window like Omniscape) once per focal-node pair, and step
# 09's experience showed even Omniscape's single largest scenario can run well past the calling
# tool's ability to babysit a blocking call; treat the actual Julia invocation as a separate,
# explicitly-launched step per config (see the run manifest this script stages), same as
# 09_run_omniscape.R's individual scenarios ended up needing.
#
# Uses Resistance Model C (the plan's "recommended production model after validation", Sec.7.6,
# and the exact choice its own Sec.13.9 R implementation outline makes for both cs_pairwise and
# cs_all_to_one) -- not a re-run across all three resistance models. Focal-node count is whatever
# 08_habitat_patches_focal_nodes.R selected (6 as of the 2026-07-29 settlement-heatmap fix, not a
# fixed number -- don't hardcode an expected pair count here or in downstream reporting).

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
# st_point_on_surface() guarantees a point INSIDE the polygon (unlike a centroid, which can fall
# outside an irregular/concave patch) -- same choice the plan's own Sec.13.8 R outline makes.
focal_points <- sf::st_point_on_surface(focal_nodes)
points_raster <- terra::rasterize(terra::vect(focal_points), master_grid, field = "patch_id")
names(points_raster) <- "focal_node_id"

circuitscape_dir <- file.path(CONNECTIVITY_OUTPUT_DIR, "circuitscape")
if (!dir.exists(circuitscape_dir)) dir.create(circuitscape_dir, recursive = TRUE)

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

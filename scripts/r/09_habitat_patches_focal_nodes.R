# Step 09 (Objective 4): habitat patches + focal nodes (plan Sec.10).
#
# RUN AS: cd scripts/r && Rscript 09_habitat_patches_focal_nodes.R
#
# Rebuilds patches from the NEW land-cover-derived core-habitat mask -- NOT a reuse of Objective
# 3's Dynamic-World-based patches (plan's own resolution of that open question, see wiki Sec.
# "Open Questions"). No igraph Euclidean patch-graph is built here (unlike Objective 3's
# 05_patch_importance_graph.R) -- that structural approximation is explicitly superseded by this
# objective's real resistance-based Circuitscape/Omniscape current-flow measures (see
# [[circuit-theory-connectivity]]'s Related Methods note); "stepping-stone position"/"connectivity
# contribution" scores are computed in step 12 from actual current-flow output, once it exists.
# mean_omniscape_current/max_omniscape_current (plan Sec.10.2) are therefore NOT in this script's
# patch table -- step 12 joins them in after Omniscape (step 10) has run.

source("00_config.R")
source("R/io.R")
source("R/grid.R")
source("R/qa.R")
source("R/patch_graph.R")
source("R/patches.R")

read_connectivity_raster <- function(name) {
  terra::rast(file.path(CONNECTIVITY_RASTER_DIR, paste0(name, ".tif")))
}

message("=== 09_habitat_patches_focal_nodes: loading step-07/08 outputs ===")
natural_fraction <- read_connectivity_raster("natural_cover_fraction_30m")
landcover_perm <- read_connectivity_raster("landcover_permeability_30m")
settlement_pressure_r <- read_connectivity_raster("settlement_pressure_30m")
road_pressure_r <- read_connectivity_raster("road_pressure_30m")
condition_current_r <- read_connectivity_raster("condition_score_current_30m")
resistance_models <- read_connectivity_raster("resistance_models_30m")

message("=== Core-habitat mask (natural_fraction >= 0.70, landcover_permeability >= 0.70, settlement_pressure <= 0.25) ===")
core_habitat <- build_core_habitat_mask(natural_fraction, landcover_perm, settlement_pressure_r)
message(sprintf(
  "%.1f%% of valid cells meet the core-habitat rule.",
  100 * terra::global(core_habitat, "mean", na.rm = TRUE)[1, 1]
))

message("=== Delineating patches (>= ", MIN_PATCH_AREA_HA, " ha, 8-connectivity) ===")
patches_result <- delineate_patches(core_habitat)
patch_poly <- patches_result$patch_polygons
message(nrow(patch_poly), " patches retained.")

message("=== Patch-level metrics (area/core/shape, ENN, perimeter) ===")
patch_metrics_long <- calculate_patch_metrics(patches_result$patch_id_raster)
patch_metrics_wide <- tidyr::pivot_wider(
  patch_metrics_long[, c("patch_id", "metric", "value")],
  names_from = metric, values_from = value
)
names(patch_metrics_wide)[names(patch_metrics_wide) == "ca"] <- "area_ha"
names(patch_metrics_wide)[names(patch_metrics_wide) == "core_mn"] <- "core_area_ha"
names(patch_metrics_wide)[names(patch_metrics_wide) == "shape_mn"] <- "shape_index"

patch_enn <- calculate_patch_nearest_neighbor(patch_poly)

patch_sf <- sf::st_as_sf(patch_poly)
# sf::st_perimeter() needs the optional lwgeom package (not in renv.lock) -- st_length() on the
# polygon boundary is an equivalent GEOS-only alternative that needs no extra dependency.
perimeter_m <- data.frame(
  patch_id = patch_sf$patch_id,
  perimeter_m = as.numeric(units::drop_units(sf::st_length(sf::st_boundary(patch_sf))))
)

n_poly_patches <- nrow(patch_poly)
n_metric_patches <- length(unique(patch_metrics_long$patch_id))
if (n_poly_patches != n_metric_patches) {
  warning(sprintf(
    "Patch count mismatch: %d polygons vs %d patch-metric IDs -- investigate before trusting the join.",
    n_poly_patches, n_metric_patches
  ))
} else {
  message("Patch count cross-check OK: ", n_poly_patches, " patches agree.")
}

message("=== Attributing patches to primary sites ===")
sites_sf <- do.call(rbind, lapply(SITES$site_id, function(sid) {
  b <- read_site_boundary(sid)
  sf::st_sf(site_id = sid, geometry = sf::st_geometry(sf::st_union(b)))
}))
site_attribution <- attribute_patches_to_sites(patch_poly, sites_sf)

message("=== Mean within-patch quality/pressure attributes ===")
attr_layers <- list(
  mean_natural_fraction = natural_fraction,
  mean_landcover_permeability = landcover_perm,
  mean_settlement_pressure = settlement_pressure_r,
  mean_road_pressure = road_pressure_r,
  mean_condition_score = condition_current_r,
  mean_resistance_A = resistance_models[["resistance_A"]],
  mean_resistance_B = resistance_models[["resistance_B"]],
  mean_resistance_C = resistance_models[["resistance_C"]]
)
attr_tables <- lapply(names(attr_layers), function(nm) mean_within_patches(patch_poly, attr_layers[[nm]], nm))
patch_attrs <- Reduce(function(a, b) dplyr::left_join(a, b, by = "patch_id"), attr_tables)

message("=== Combining patch table ===")
patch_table <- patch_metrics_wide |>
  dplyr::left_join(patch_enn, by = "patch_id") |>
  dplyr::left_join(perimeter_m, by = "patch_id") |>
  dplyr::left_join(site_attribution, by = "patch_id") |>
  dplyr::left_join(patch_attrs, by = "patch_id")
patch_table$tier <- tier_patches(patch_table$area_ha)
message("Tier counts: ", paste(names(table(patch_table$tier)), table(patch_table$tier), sep = "=", collapse = ", "))

readr::write_csv(patch_table, file.path(TABLES_DIR, "connectivity_patch_metrics_current.csv"))

message("=== Selecting focal nodes (area_ha >= ", FOCAL_NODE_MIN_AREA_HA, " ha) ===")
focal_nodes <- select_focal_nodes(patch_table)
message(nrow(focal_nodes), " focal nodes selected across ", length(unique(focal_nodes$primary_site_id)), " site groups:")
print(table(focal_nodes$primary_site_id))
readr::write_csv(focal_nodes, file.path(TABLES_DIR, "connectivity_focal_nodes_current.csv"))

message("=== Writing vector/raster outputs ===")
patch_poly_sf <- sf::st_as_sf(patch_poly) |> dplyr::left_join(patch_table, by = "patch_id")
sf::st_write(patch_poly_sf, file.path(VECTORS_DIR, "connectivity_habitat_patches_current.gpkg"), delete_dsn = TRUE, quiet = TRUE)

focal_nodes_sf <- patch_poly_sf[patch_poly_sf$patch_id %in% focal_nodes$patch_id, ]
sf::st_write(focal_nodes_sf, file.path(VECTORS_DIR, "connectivity_focal_nodes_current.gpkg"), delete_dsn = TRUE, quiet = TRUE)

terra::writeRaster(
  patches_result$patch_id_raster,
  file.path(CONNECTIVITY_RASTER_DIR, "habitat_patch_id_current_30m.tif"),
  overwrite = TRUE
)

message("=== 09_habitat_patches_focal_nodes complete ===")

# Human-pressure / road / hydrology / terrain derived layers on the 30m master grid. Each function
# returns one aligned, named SpatRaster layer.

#' Settlement-pressure raster: 0.70*heatmap_scaled + 0.30*built_fraction. built_fraction is
#' assumed already in [0, 1] (a class_fraction_stack() grouping) and used as-is.
#'
#' NA FILL: settlement_heatmap.tif's valid-data footprint has interior gaps (~16% of the grid)
#' relative to the AOI mask every other layer shares. Unfilled, this NA propagates downstream and
#' Circuitscape treats NA as an absolute graph barrier, silently disconnecting focal nodes. A KDE
#' heatmap trends toward 0 far from any input point, so filling NA with 0 here is conservative --
#' the true AOI boundary is still enforced by every other resistance-formula input.
#' @param heatmap_path Path to settlement_heatmap.tif (continuous KDE raster, arbitrary units).
#' @param built_fraction Aligned built_fraction raster (grouped_fraction() on BUILT_LC_CLASSES).
#' @param master_grid The 30m master grid.
settlement_pressure <- function(heatmap_path, built_fraction, master_grid) {
  heatmap_aligned <- align_to_grid(terra::rast(heatmap_path), master_grid, method = "bilinear")
  heatmap_aligned <- terra::ifel(is.na(heatmap_aligned), 0, heatmap_aligned)
  heatmap_scaled <- percentile_scale(heatmap_aligned, CONNECTIVITY_PERCENTILE_BOUNDS)
  w <- SETTLEMENT_PRESSURE_WEIGHTS
  out <- clamp01(as.numeric(w["heatmap"]) * heatmap_scaled + as.numeric(w["built_fraction"]) * built_fraction)
  names(out) <- "settlement_pressure"
  out
}

#' Road-pressure raster: for each OSM fclass present in `roads_path`, a linear distance-decay to
#' ROAD_INFLUENCE_DISTANCE_M scaled by ROAD_CLASS_SCORES, combined via max across classes.
road_pressure <- function(roads_path, master_grid) {
  roads <- sf::st_read(roads_path, quiet = TRUE)
  present_classes <- intersect(names(ROAD_CLASS_SCORES), unique(roads$fclass))
  if (length(present_classes) == 0) stop("No recognized fclass values found in ", roads_path)

  class_layers <- lapply(present_classes, function(cls) {
    subset_v <- terra::vect(roads[roads$fclass == cls, ])
    dist_r <- terra::distance(master_grid, subset_v)
    clamp01(1 - dist_r / ROAD_INFLUENCE_DISTANCE_M) * ROAD_CLASS_SCORES[[cls]]
  })
  out <- max(do.call(c, class_layers))
  names(out) <- "road_pressure"
  out
}

#' Distance (m), per master-grid cell, to the nearest feature in a line/point vector layer.
feature_distance <- function(vector_path, master_grid) {
  v <- terra::vect(sf::st_read(vector_path, quiet = TRUE))
  out <- terra::distance(master_grid, v)
  names(out) <- "distance_m"
  out
}

#' Binary riparian buffer: 1 where `river_distance` <= RIPARIAN_BUFFER_M, else 0.
riparian_buffer <- function(river_distance) {
  out <- terra::ifel(river_distance <= RIPARIAN_BUFFER_M, 1, 0)
  names(out) <- "riparian_buffer"
  out
}

#' Percentile-scaled slope.
slope_scaled <- function(slope_path, master_grid) {
  slope_aligned <- align_to_grid(terra::rast(slope_path), master_grid, method = "bilinear")
  out <- percentile_scale(slope_aligned, CONNECTIVITY_PERCENTILE_BOUNDS)
  names(out) <- "slope_scaled"
  out
}

#' Terrain Ruggedness Index from elevation, aligned to the master grid.
terrain_ruggedness <- function(elevation_path, master_grid) {
  elev_aligned <- align_to_grid(terra::rast(elevation_path), master_grid, method = "bilinear")
  out <- terra::terrain(elev_aligned, v = "TRI")
  names(out) <- "terrain_ruggedness"
  out
}

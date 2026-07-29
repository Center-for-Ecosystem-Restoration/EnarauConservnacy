# Master-grid / raster-alignment plumbing for Objective 4. Objective 3 resampled ad hoc onto
# whichever raster loaded first; Objective 4 needs one explicit shared grid since it aligns many
# more heterogeneous sources (vectors, categorical land cover, continuous rasters at multiple
# native resolutions) onto a common 30m grid.

#' Build the Objective 4 30m master grid: an empty template SpatRaster covering
#' project_geom_vect(), extent rounded outward to a clean CONNECTIVITY_GRID_RESOLUTION_M origin.
#' Every other raster in this pipeline gets aligned onto this via align_to_grid(), never onto
#' each other.
build_master_grid <- function(resolution_m = CONNECTIVITY_GRID_RESOLUTION_M) {
  e <- terra::ext(project_geom_vect())
  xmin <- floor(e$xmin / resolution_m) * resolution_m
  xmax <- ceiling(e$xmax / resolution_m) * resolution_m
  ymin <- floor(e$ymin / resolution_m) * resolution_m
  ymax <- ceiling(e$ymax / resolution_m) * resolution_m
  terra::rast(
    xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
    resolution = resolution_m, crs = PROJECT_CRS
  )
}

#' A finer-resolution template sharing the master grid's exact origin -- nests a
#' higher-resolution categorical source (e.g. 10m land cover) before block-aggregating it up to
#' the master grid, guaranteeing each master cell maps to an exact integer number of source cells
#' (a raw source raster's extent isn't guaranteed to be a clean multiple of resolution_m).
build_nested_fine_grid <- function(master_grid, fine_resolution_m) {
  terra::rast(
    terra::ext(master_grid), resolution = fine_resolution_m, crs = terra::crs(master_grid)
  )
}

#' Align any raster onto `grid`'s exact geometry (CRS/extent/origin/resolution), reprojecting if
#' needed. method="bilinear" for continuous rasters (default), method="near" for
#' categorical/discrete ones -- caller must choose correctly.
align_to_grid <- function(r, grid, method = "bilinear") {
  terra::project(r, grid, method = method)
}

#' Clamp-normalize to [0, 1] using robust (p_low, p_high) percentiles rather than raw min/max --
#' the R-side equivalent of connectivity_condition_composite.ipynb's percentile_scale():
#' clamp((x - p_low) / (p_high - p_low), 0, 1).
#' @param r SpatRaster (single layer).
#' @param bounds c(low, high) percentile pair, e.g. c(5, 95).
percentile_scale <- function(r, bounds) {
  p <- terra::global(r, fun = quantile, probs = bounds / 100, na.rm = TRUE)
  p_low <- as.numeric(p[1, 1])
  p_high <- as.numeric(p[1, 2])
  terra::clamp((r - p_low) / (p_high - p_low), lower = 0, upper = 1)
}

#' Plain clamp-normalize to [0, 1] via min/max -- for inputs already known to be in [0, 1] by
#' construction, where percentile scaling isn't warranted.
clamp01 <- function(r) {
  terra::clamp(r, lower = 0, upper = 1)
}

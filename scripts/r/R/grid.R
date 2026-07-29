# Master-grid / raster-alignment plumbing for Objective 4. No equivalent existed before this --
# Objective 3 only ever resampled ad hoc onto whichever raster happened to load first (see
# 06_figures_and_exports.R's grid_template pattern) -- Objective 4 needs a real, explicit one
# since it aligns many more heterogeneous raw sources (vectors, categorical land cover, continuous
# rasters at multiple native resolutions) onto one shared 30m grid.

#' Build the Objective 4 30m master grid: an empty template SpatRaster covering
#' project_geom_vect(), with its extent rounded outward to a clean CONNECTIVITY_GRID_RESOLUTION_M
#' origin -- every other raster in this pipeline gets aligned onto this via align_to_grid(),
#' never onto each other. Confirmed 2026-07-29 that this reproduces data/elevation.tif's own grid
#' exactly (see 00_config.R's comment) -- a useful built-in cross-check, not a coincidence to rely
#' on going forward (elevation.tif still gets aligned like everything else).
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

#' A finer-resolution template sharing the master grid's exact origin -- used to nest a
#' higher-resolution categorical source (e.g. 10m land cover) before block-aggregating it up to
#' the master grid. Guarantees each master cell maps to an exact integer number of source cells
#' (fact = resolution_m / fine_resolution_m); aggregating a raw source raster directly would leave
#' partial edge cells, since its own extent is not guaranteed to be a clean multiple of
#' resolution_m (confirmed true of the 10m land-cover raster -- its extent is NOT exactly
#' divisible by 30).
build_nested_fine_grid <- function(master_grid, fine_resolution_m) {
  terra::rast(
    terra::ext(master_grid), resolution = fine_resolution_m, crs = terra::crs(master_grid)
  )
}

#' Align any raster onto `grid`'s exact geometry (CRS/extent/origin/resolution), reprojecting if
#' needed. method="bilinear" for continuous rasters (the default), method="near" for
#' categorical/discrete ones -- caller's responsibility to choose correctly, same discipline as
#' terra::resample()/terra::project() themselves require.
align_to_grid <- function(r, grid, method = "bilinear") {
  terra::project(r, grid, method = method)
}

#' Clamp-normalize to [0, 1] using robust (p_low, p_high) percentiles rather than raw min/max --
#' the R-side equivalent of connectivity_condition_composite.ipynb's percentile_scale() and the
#' plan's own slope_scaled formula (Sec.5.6): clamp((x - p_low) / (p_high - p_low), 0, 1).
#' @param r SpatRaster (single layer).
#' @param bounds c(low, high) percentile pair, e.g. c(5, 95).
percentile_scale <- function(r, bounds) {
  p <- terra::global(r, fun = quantile, probs = bounds / 100, na.rm = TRUE)
  p_low <- as.numeric(p[1, 1])
  p_high <- as.numeric(p[1, 2])
  terra::clamp((r - p_low) / (p_high - p_low), lower = 0, upper = 1)
}

#' Plain clamp-normalize to [0, 1] via min/max -- for inputs already known to be well-behaved
#' (e.g. fractions that are already in [0, 1] by construction), where percentile scaling isn't
#' warranted.
clamp01 <- function(r) {
  terra::clamp(r, lower = 0, upper = 1)
}

# Moving-window local connectivity change maps.
#
# RUN AS: cd scripts/r && Rscript 04_moving_window_connectivity.R
#
# Runs project-wide first, clips only for reporting/figures afterward -- a real corridor
# pinch-point can straddle a site boundary, so masking to site before window_lsm() would
# truncate it.
#
# window_lsm() is the single most expensive step in this pipeline (PD requires per-window patch
# delineation, far more costly than ED/AI's adjacency-count approach or PLAND's focal-mean
# below). Run the smoke test below first and check the printed timing before committing to a
# full run.
#
# METRIC NOTE (found 2026-07-28, first real production run): window_lsm() only supports
# landscape-level ("lsm_l_*") metrics and errors on class-level names. The originally intended
# lsm_l_pland/lsm_l_clumpy don't exist at landscape level at all (PLAND/CLUMPY are class-level
# concepts -- see 03/R/metrics.R's calculate_binary_metrics(), which computes them class-level
# and filters to class==1). window_lsm() silently drops unrecognized metric names instead of
# erroring, so this went uncaught until a real (non-smoke-test) run used the results. Fixed here:
# PLAND is computed as a terra::focal() mean of the binary raster (mathematically identical to
# "% of the window's classified area that's natural"); CLUMPY is replaced by lsm_l_ai
# (Aggregation Index, landscape-level) -- 03's correlation screen found ai correlates >0.85 with
# clumpy/pland/lpi in this landscape's data, so it carries similar signal.

source("00_config.R")
source("R/io.R")
source("R/recode.R")

# Smoke-test controls: set SMOKE_TEST_SITE to a site_id to crop + time a single radius before
# running the full project extent.
SMOKE_TEST_SITE <- NULL   # NULL for the full production run
SMOKE_TEST_RADII_M <- 500  # single radius timed during the smoke test

message("=== 04_moving_window_connectivity ===")

current_class_path <- period_manifest$class_file[period_manifest$token == "current_2022_2025"]
baseline_class_path <- period_manifest$class_file[period_manifest$token == "baseline_2016_2018"]

if (!file.exists(current_class_path) || !file.exists(baseline_class_path)) {
  stop("Current and/or baseline period class rasters not yet downloaded -- run 01_prepare_inputs.R first and check the manifest.")
}

current_r <- read_habitat_raster(current_class_path)
baseline_r <- read_habitat_raster(baseline_class_path)

current_bin <- make_natural_binary(current_r)
baseline_bin <- make_natural_binary(baseline_r)

if (!is.null(SMOKE_TEST_SITE)) {
  message("SMOKE TEST MODE: cropping to '", SMOKE_TEST_SITE, "' + 150 m buffer, radius = ", SMOKE_TEST_RADII_M, " m only.")
  site_boundary <- read_site_boundary(SMOKE_TEST_SITE)
  site_buffered <- sf::st_buffer(site_boundary, dist = 150)
  current_bin <- terra::crop(current_bin, terra::vect(site_buffered))
  baseline_bin <- terra::crop(baseline_bin, terra::vect(site_buffered))
  radii_to_run <- SMOKE_TEST_RADII_M
} else {
  radii_to_run <- MOVING_WINDOW_RADII_M
}

# lsm_l_pland dropped -- doesn't exist at landscape level, computed separately via terra::focal()
# below. lsm_l_clumpy replaced by lsm_l_ai -- see the METRIC NOTE above.
window_metrics <- c("lsm_l_ed", "lsm_l_ai", "lsm_l_pd")

#' Odd window size (so there's a defined center pixel) -- rounds DOWN to the nearest odd size on
#' the rare radius that comes out even (currently only 250m: 26 -> 25), not up. 500m (51) and
#' 1000m (101) are already odd and untouched. This edge case was never exercised by the smoke
#' test, which only ever ran the 500m radius.
compute_win_size <- function(radius_m) {
  win_size <- radius_m %/% 10 + 1
  if (win_size %% 2 == 0) win_size <- win_size - 1
  win_size
}

run_window_lsm_for_period <- function(r_bin, radius_m) {
  win_size <- compute_win_size(radius_m)
  win <- matrix(1, nrow = win_size, ncol = win_size)

  t0 <- Sys.time()
  raw_result <- landscapemetrics::window_lsm(
    landscape = r_bin, window = win, what = window_metrics, directions = 8, progress = TRUE
  )
  elapsed_lsm <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  # window_lsm() nests its result one level under a per-input-layer key (e.g. "layer_1") even for
  # a single-layer landscape like ours (confirmed empirically 2026-07-28, landscapemetrics 2.2.1).
  # Unwrap positionally, not by the literal string "layer_1", so downstream code can index metrics
  # by name -- a second latent bug alongside the metric-name one above: top-level indexing like
  # current_windows[["lsm_l_pland"]] would have silently returned NULL.
  metrics <- raw_result[[1]]

  t1 <- Sys.time()
  # PLAND has no landscape-level definition (see the METRIC NOTE above) -- a focal mean of the
  # binary raster is mathematically identical to "% of the window's classified area that's
  # natural" (na.rm=TRUE excludes unclassified pixels from the denominator, matching PLAND's own
  # convention documented in R/metrics.R). Scaled by 100 to match landscapemetrics' 0-100 range.
  metrics[["lsm_l_pland"]] <- terra::focal(r_bin, w = win, fun = "mean", na.rm = TRUE) * 100
  elapsed_focal <- as.numeric(difftime(Sys.time(), t1, units = "secs"))

  message(sprintf(
    "  window_lsm() at radius %dm (%dx%d cells) took %.1f sec (+ %.1f sec focal PLAND).",
    radius_m, win_size, win_size, elapsed_lsm, elapsed_focal
  ))
  metrics
}

for (radius_m in radii_to_run) {
  message("=== Radius ", radius_m, "m ===")
  current_windows <- run_window_lsm_for_period(current_bin, radius_m)
  baseline_windows <- run_window_lsm_for_period(baseline_bin, radius_m)

  if (!is.null(SMOKE_TEST_SITE)) {
    message("Smoke test complete for radius ", radius_m, "m -- review timing above before running the full pipeline. ",
            "No output rasters written in smoke-test mode.")
    next
  }

  # metrics is keyed by name after run_window_lsm_for_period()'s unwrap/focal-PLAND additions above.
  pland_change <- current_windows[["lsm_l_pland"]] - baseline_windows[["lsm_l_pland"]]
  ed_change    <- current_windows[["lsm_l_ed"]] - baseline_windows[["lsm_l_ed"]]
  pd_change    <- current_windows[["lsm_l_pd"]] - baseline_windows[["lsm_l_pd"]]
  ai_change    <- current_windows[["lsm_l_ai"]] - baseline_windows[["lsm_l_ai"]]  # replaces clumpy, see METRIC NOTE above

  scale_raster <- function(r) (r - terra::global(r, "mean", na.rm = TRUE)[1, 1]) / terra::global(r, "sd", na.rm = TRUE)[1, 1]
  local_connectivity_change_score <- scale_raster(pland_change) + scale_raster(ai_change) -
    scale_raster(ed_change) - scale_raster(pd_change)
  names(local_connectivity_change_score) <- "local_connectivity_change_score"

  suffix <- sprintf("_w%dm", radius_m)
  terra::writeRaster(current_windows[["lsm_l_pland"]], file.path(LANDSCAPE_RASTER_DIR, paste0("local_natural_prop_current", suffix, ".tif")), overwrite = TRUE)
  terra::writeRaster(baseline_windows[["lsm_l_pland"]], file.path(LANDSCAPE_RASTER_DIR, paste0("local_natural_prop_baseline", suffix, ".tif")), overwrite = TRUE)
  terra::writeRaster(pland_change, file.path(LANDSCAPE_RASTER_DIR, paste0("local_natural_prop_change_baseline_to_current", suffix, ".tif")), overwrite = TRUE)
  terra::writeRaster(ed_change, file.path(LANDSCAPE_RASTER_DIR, paste0("local_edge_density_change_baseline_to_current", suffix, ".tif")), overwrite = TRUE)
  terra::writeRaster(pd_change, file.path(LANDSCAPE_RASTER_DIR, paste0("local_patch_density_change_baseline_to_current", suffix, ".tif")), overwrite = TRUE)
  terra::writeRaster(local_connectivity_change_score, file.path(LANDSCAPE_RASTER_DIR, paste0("local_connectivity_change_score", suffix, ".tif")), overwrite = TRUE)

  message("Wrote radius-", radius_m, "m rasters to ", LANDSCAPE_RASTER_DIR)
}

message("=== 04_moving_window_connectivity complete ===")
if (!is.null(SMOKE_TEST_SITE)) {
  message("This was a SMOKE TEST run (SMOKE_TEST_SITE = '", SMOKE_TEST_SITE, "'). ",
          "Set SMOKE_TEST_SITE <- NULL at the top of this script for the full production run, ",
          "after confirming the timing above extrapolates to an acceptable full-extent runtime.")
}

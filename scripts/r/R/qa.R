# Valid-pixel-coverage QA: a site-year with only ~55% valid pixel coverage produced artificial
# patch breaks that inflated NP/PD/ED. No standalone valid_obs_count raster exists per-year --
# the NA fraction on habitat_class itself is the QA signal.

#' Compute valid-pixel coverage for one habitat_class raster, restricted to one site's polygon.
#' @param habitat_class_path Path to a habitat_class GeoTIFF.
#' @param site_vect A terra SpatVector (or sf object) of the site boundary, already in PROJECT_CRS.
compute_valid_coverage <- function(habitat_class_path, site_vect) {
  r <- read_habitat_raster(habitat_class_path)
  if (inherits(site_vect, "sf")) site_vect <- terra::vect(site_vect)
  r_crop <- terra::crop(r, site_vect)
  vals <- terra::extract(r_crop, site_vect, ID = FALSE)[[1]]
  total <- length(vals)
  valid <- sum(!is.na(vals))
  data.frame(
    valid_pixel_count = valid,
    total_pixel_count = total,
    coverage_pct = if (total > 0) valid / total else NA_real_,
    below_threshold = if (total > 0) (valid / total) < VALID_PIXEL_COVERAGE_MIN else NA
  )
}

#' Run compute_valid_coverage() across every (site x year x season) row of a manifest data.frame.
compute_valid_coverage_table <- function(manifest, id_cols) {
  rows <- lapply(seq_len(nrow(manifest)), function(i) {
    site_ids <- SITES$site_id
    do.call(rbind, lapply(site_ids, function(sid) {
      site_vect <- terra::vect(read_site_boundary(sid))
      cov <- compute_valid_coverage(manifest$habitat_class_file[i], site_vect)
      cbind(
        site_id = sid,
        manifest[i, id_cols, drop = FALSE],
        cov
      )
    }))
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Print the excluded (below-threshold) rows loudly -- never a silent drop.
report_excluded_rows <- function(coverage_table, context_label) {
  excluded <- coverage_table[coverage_table$below_threshold %in% TRUE, ]
  if (nrow(excluded) > 0) {
    message(sprintf(
      "[QA] %d row(s) excluded from %s for <%.0f%% valid-pixel coverage:",
      nrow(excluded), context_label, 100 * VALID_PIXEL_COVERAGE_MIN
    ))
    print(excluded)
  } else {
    message(sprintf("[QA] No rows excluded from %s -- all site/period-season combinations meet the %.0f%% coverage threshold.",
                     context_label, 100 * VALID_PIXEL_COVERAGE_MIN))
  }
  invisible(excluded)
}

#' Objective 4 grid-alignment QA: verify every raster in `rasters` shares the master grid's exact
#' CRS/extent/dims, and report each raster's finite-value range.
check_connectivity_grid_alignment <- function(rasters, master_grid) {
  ref_ext <- as.vector(terra::ext(master_grid))
  ref_dim <- dim(master_grid)[1:2]
  results <- lapply(names(rasters), function(nm) {
    r <- rasters[[nm]]
    ext_ok <- isTRUE(all.equal(as.vector(terra::ext(r)), ref_ext))
    dim_ok <- identical(dim(r)[1:2], ref_dim)
    crs_ok <- terra::same.crs(r, master_grid)
    vals <- terra::values(r, na.rm = TRUE)
    rng <- if (length(vals) > 0) range(vals) else c(NA_real_, NA_real_)
    has_nonfinite <- length(vals) > 0 && any(!is.finite(vals))
    data.frame(
      layer = nm, ext_ok = ext_ok, dim_ok = dim_ok, crs_ok = crs_ok,
      min = rng[1], max = rng[2], has_nonfinite = has_nonfinite
    )
  })
  out <- do.call(rbind, results)
  bad <- out[!(out$ext_ok & out$dim_ok & out$crs_ok) | out$has_nonfinite, ]
  if (nrow(bad) > 0) {
    warning("[QA] Grid-alignment/finite-value issues found:")
    print(bad)
  } else {
    message(sprintf("[QA] All %d connectivity layers share the master grid's geometry with finite values.", nrow(out)))
  }
  out
}

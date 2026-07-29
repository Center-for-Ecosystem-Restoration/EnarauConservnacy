# Patch delineation and patch-level metrics. Runs on the full project-extent binary
# natural-habitat raster, before any per-site clipping -- a corridor patch spanning two sites
# must not be truncated.
#
# This file used to also contain an igraph Euclidean-distance patch-graph connectivity screen
# (build_patch_graph(), mean_pressure_around_patches()), removed 2026-07-29: it was a structural
# approximation for real resistance-based connectivity, now superseded by Objective 4's
# Circuitscape/Omniscape analysis (scripts/r/06-11_*.R), so it and its dependent
# linkage_priority_score synthesis were deleted rather than kept alongside a better answer.
# delineate_patches()/calculate_patch_metrics()/calculate_patch_nearest_neighbor()/
# attribute_patches_to_sites() below are unaffected -- generic utilities reused by Objectives 3 and 4.

#' Delineate patches from a binary natural-habitat raster (1 = natural, 0 = converted, NA =
#' excluded), filter to >= MIN_PATCH_AREA_HA, and return both the cleaned patch-ID raster and its
#' dissolved polygons.
#'
#' zeroAsNA = TRUE is required: without it, terra::patches() also delineates "patches" out of the
#' 0 background, corrupting the area filter and ID numbering. With it, only class-1 cells get
#' patch IDs, matching the connected-component labeling calculate_lsm(level="patch") uses
#' internally (verified via a patch-count cross-check in each caller).
delineate_patches <- function(r_bin_natural) {
  patch_id <- terra::patches(r_bin_natural, directions = 8, zeroAsNA = TRUE)
  pixel_area_ha <- prod(terra::res(patch_id)) / 10000
  # terra::freq() (this version) has no useNA argument and does not emit a row for NA values.
  patch_freq <- as.data.frame(terra::freq(patch_id))
  patch_freq$area_ha <- patch_freq$count * pixel_area_ha
  keep_ids <- patch_freq$value[patch_freq$area_ha >= MIN_PATCH_AREA_HA]

  # `patch_id %in% keep_ids` does not dispatch correctly on a SpatRaster in this terra version
  # ("match requires vector arguments") despite a method appearing to exist -- use classify()
  # with an identity reclass + others=NA instead, which is already verified to work.
  patch_id_clean <- terra::classify(patch_id, rcl = cbind(keep_ids, keep_ids), others = NA)
  patch_poly <- terra::as.polygons(patch_id_clean, dissolve = TRUE, na.rm = TRUE)
  names(patch_poly) <- "patch_id"

  list(patch_id_raster = patch_id_clean, patch_polygons = patch_poly, area_table = patch_freq, keep_ids = keep_ids)
}

#' Patch-level AREA/CORE/SHAPE metrics, computed WITHOUT relying on
#' landscapemetrics::calculate_lsm(level="patch")'s own internal patch-ID numbering.
#'
#' calculate_lsm(level="patch")'s `id` column does NOT match terra::patches()'s patch IDs (zero
#' overlap in testing) despite both using connected-component labeling with the same `directions`.
#' Rather than reconcile two non-matching ID schemes, this treats the already-delineated
#' `patch_id_raster` (whose IDs this project controls) as a multi-class categorical raster -- one
#' "class" per patch -- so class-level metrics (lsm_c_ca, lsm_c_core_mn, lsm_c_shape_mn) equal
#' that single patch's own area/core-area/shape-index, with the join to `patch_id` exact by
#' construction. ENN is NOT available this way (needs >1 patch per class) -- see
#' calculate_patch_nearest_neighbor() instead.
#' @param patch_id_raster The `patch_id_raster` returned by delineate_patches() (already filtered
#'   to >= MIN_PATCH_AREA_HA).
calculate_patch_metrics <- function(patch_id_raster) {
  m <- landscapemetrics::calculate_lsm(
    landscape = patch_id_raster,
    what = c("lsm_c_ca", "lsm_c_core_mn", "lsm_c_shape_mn"),
    directions = 8,
    edge_depth = EDGE_DEPTH_CELLS
  )
  names(m)[names(m) == "class"] <- "patch_id"
  m
}

#' Nearest-neighbor distance (m) from each patch to its closest OTHER patch, computed directly
#' from patch_poly's own geometry (polygon-to-polygon, not centroid-to-centroid) -- uses
#' sf::st_distance() rather than landscapemetrics' lsm_p_enn, which has the same ID-mismatch
#' problem as calculate_patch_metrics() above.
calculate_patch_nearest_neighbor <- function(patch_poly) {
  patch_sf <- sf::st_as_sf(patch_poly)
  n <- nrow(patch_sf)
  if (n < 2) {
    return(data.frame(patch_id = patch_sf$patch_id, enn_m = rep(NA_real_, n)))
  }
  dist_mat <- units::drop_units(sf::st_distance(patch_sf))
  diag(dist_mat) <- NA
  data.frame(patch_id = patch_sf$patch_id, enn_m = apply(dist_mat, 1, min, na.rm = TRUE))
}

#' Assign each patch polygon to its primary site by largest-area overlap; flag patches spanning
#' more than one site (expected/meaningful for corridor-crossing patches, not an error).
attribute_patches_to_sites <- function(patch_poly, sites_sf) {
  patch_sf <- sf::st_as_sf(patch_poly)
  inter <- suppressWarnings(sf::st_intersection(patch_sf, sites_sf))
  inter$overlap_area_m2 <- as.numeric(sf::st_area(inter))

  by_patch <- split(inter, inter$patch_id)
  summary_rows <- lapply(by_patch, function(rows) {
    primary <- rows[which.max(rows$overlap_area_m2), ]
    data.frame(
      patch_id = primary$patch_id[1],
      primary_site_id = primary$site_id[1],
      spans_multiple_sites = length(unique(rows$site_id)) > 1,
      site_ids = paste(sort(unique(rows$site_id)), collapse = ";")
    )
  })
  do.call(rbind, summary_rows)
}

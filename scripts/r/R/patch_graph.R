# Patch delineation and patch-level metrics. Runs on the full project-extent binary
# natural-habitat raster (see masking-order rule in 00_config.R/plan) -- a corridor patch spanning
# two sites must not be truncated.
#
# The igraph Euclidean-distance patch-graph connectivity screen this file used to also contain
# (build_patch_graph(), mean_pressure_around_patches()) was removed 2026-07-29: it was always
# documented as "a structural approximation" standing in for real resistance-based connectivity
# (see wiki [[circuit-theory-connectivity]]) until Objective 4's Circuitscape/Omniscape analysis
# existed. That analysis is now built (scripts/r/06-11_*.R) and supersedes it, so the Euclidean
# graph and its dependent linkage_priority_score synthesis (formerly in
# 05_patch_importance_graph.R and part of 06_figures_and_exports.R) were deleted rather than kept
# alongside a better answer to the same question. delineate_patches()/calculate_patch_metrics()/
# calculate_patch_nearest_neighbor()/attribute_patches_to_sites() below are unaffected -- they're
# generic patch-delineation utilities reused by both Objective 3 (03/04_*.R) and Objective 4
# (08_habitat_patches_focal_nodes.R).

#' Delineate patches from a binary natural-habitat raster (1 = natural, 0 = converted, NA =
#' excluded), filter to >= MIN_PATCH_AREA_HA, and return both the cleaned patch-ID raster and its
#' dissolved polygons.
#'
#' zeroAsNA = TRUE is required here: without it, terra::patches() also delineates "patches" out
#' of the 0 (converted/non-natural) background, which would corrupt both the area filter and the
#' patch_id numbering. With zeroAsNA = TRUE, only class-1 (natural) cells receive patch IDs --
#' the same connected-component labeling landscapemetrics::calculate_lsm(level="patch") uses
#' internally for this class, on the same directions=8 setting, so the resulting patch_id values
#' are expected to align with calculate_patch_metrics()'s own `id` column. This is verified via a
#' patch-count cross-check in each caller (e.g. 08_habitat_patches_focal_nodes.R) rather than
#' assumed silently.
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
#' Empirically confirmed 2026-07-15: calculate_lsm(level="patch")'s `id` column does NOT match
#' terra::patches()'s patch IDs (0 of 271 IDs overlapped in a real test) -- the two use different
#' internal labeling schemes despite both nominally using connected-component labeling with the
#' same `directions`. Rather than reconcile two independent, non-matching ID schemes, this
#' function treats the ALREADY-DELINEATED `patch_id_raster` (from delineate_patches(), whose IDs
#' this project controls and uses for the graph/polygons) as a multi-class categorical raster --
#' one "class" per patch. Since each class then contains exactly one connected patch by
#' construction, class-level metrics (lsm_c_ca = total class area, lsm_c_core_mn/lsm_c_shape_mn =
#' mean core-area/shape-index across patches in that class) equal that single patch's own
#' area/core-area/shape-index -- with the join to `patch_id` now exact by construction (class ==
#' patch_id), not assumed. ENN is NOT available this way (a class-level nearest-neighbor metric
#' needs >1 patch per class) -- see calculate_patch_nearest_neighbor() below instead.
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

# Objective 4's own habitat-patch/focal-node logic (plan Sec.10). Patch DELINEATION reuses
# R/patch_graph.R's generic functions unchanged (delineate_patches, calculate_patch_metrics,
# calculate_patch_nearest_neighbor, attribute_patches_to_sites all operate on any binary-natural
# raster/patch polygon regardless of source) -- only the core-habitat mask, per-patch attribute
# extraction, tiering, and focal-node selection are new here, since Objective 4 rebuilds patches
# from the NEW land-cover classification rather than reusing Objective 3's Dynamic-World-based
# ones (plan's own resolution of that open question). No igraph patch-graph is built for Objective
# 4 -- see R/patch_graph.R's header comment on why that Euclidean-distance approach was removed
# entirely (superseded by this objective's own real current-flow analysis, not reused by it).

#' Binary core-habitat raster (1/0/NA) per plan Sec.10.1: natural_fraction >= 0.70 AND
#' landcover_permeability >= 0.70 AND settlement_pressure <= 0.25. All three inputs must already
#' share the master grid.
build_core_habitat_mask <- function(natural_fraction, landcover_permeability, settlement_pressure) {
  crit <- CORE_HABITAT_CRITERIA
  out <- (natural_fraction >= crit$natural_fraction_min) &
    (landcover_permeability >= crit$landcover_permeability_min) &
    (settlement_pressure <= crit$settlement_pressure_max)
  # `&` on SpatRasters with NA operands already propagates NA correctly; terra::mask() not needed.
  names(out) <- "core_habitat"
  out
}

#' Mean value of `r` WITHIN each patch polygon itself (no buffer, unlike a buffer-outward
#' "surrounding pressure" measure). Returns a data.frame(patch_id, <band_name>).
mean_within_patches <- function(patch_poly, r, band_name) {
  vals <- terra::extract(r, patch_poly, fun = mean, na.rm = TRUE, ID = FALSE)
  out <- data.frame(patch_id = patch_poly$patch_id, value = vals[[1]])
  names(out)[2] <- band_name
  out
}

#' Assign each patch a size tier (plan Sec.10.3) from its area_ha. Patches below tier3_min are
#' "untiered" -- retained in the patch table but not eligible as focal-node candidates.
tier_patches <- function(area_ha) {
  t <- PATCH_TIER_THRESHOLDS_HA
  dplyr::case_when(
    area_ha >= t[["tier1_min"]] ~ "tier1",
    area_ha >= t[["tier2_min"]] ~ "tier2",
    area_ha >= t[["tier3_min"]] ~ "tier3",
    TRUE ~ "untiered"
  )
}

#' Select focal-node candidates (plan Sec.10.4): area_ha >= FOCAL_NODE_MIN_AREA_HA, ranked by
#' area_ha (descending) within each site group ("external_buffer" for patches outside all 4 named
#' sites), capped at FOCAL_NODE_TARGET_COUNTS per site (uncapped for external_buffer).
#'
#' GUARANTEED MINIMUM (added 2026-07-29, real finding not anticipated by the plan): a strict
#' area_ha >= 20 cutoff leaves Corridor Phase 2 with ZERO focal nodes -- its only delineated patch
#' at all is 10.17 ha (tier3), below the cutoff -- and Corridor Phase 1 with only one (22.86 ha,
#' barely above it). Both corridor phases are exactly the linkage the whole objective exists to
#' test (plan Sec.10.5's own priority linkage list requires a Corridor Phase 1/2 endpoint), so
#' `require_min_one_per_named_site = TRUE` (default) falls back to each named SITES$site_id's
#' single largest patch (regardless of area/tier) when that site has zero candidates clearing
#' min_area_ha -- never for "external_buffer", which has no linkage requirement. This is a
#' fragmentation finding worth reporting on its own terms (the corridor phases are far more
#' fragmented than Enarau/Mbokishi), not something to paper over by lowering the area threshold
#' project-wide.
#' @param patch_table Must have columns patch_id, area_ha, primary_site_id (NA -> "external_buffer").
select_focal_nodes <- function(patch_table, min_area_ha = FOCAL_NODE_MIN_AREA_HA,
                                target_counts = FOCAL_NODE_TARGET_COUNTS,
                                require_min_one_per_named_site = TRUE) {
  patch_table$primary_site_id[is.na(patch_table$primary_site_id)] <- "external_buffer"
  candidates <- patch_table[!is.na(patch_table$area_ha) & patch_table$area_ha >= min_area_ha, ]

  by_site <- split(candidates, candidates$primary_site_id)
  selected <- lapply(names(by_site), function(site_id) {
    rows <- by_site[[site_id]][order(-by_site[[site_id]]$area_ha), ]
    cap <- if (site_id %in% names(target_counts)) target_counts[[site_id]] else nrow(rows)
    rows[seq_len(min(cap, nrow(rows))), ]
  })
  out <- do.call(rbind, selected)

  if (require_min_one_per_named_site) {
    missing_sites <- setdiff(names(target_counts), unique(out$primary_site_id))
    fallback_rows <- lapply(missing_sites, function(site_id) {
      site_rows <- patch_table[!is.na(patch_table$primary_site_id) & patch_table$primary_site_id == site_id, ]
      if (nrow(site_rows) == 0) return(NULL)
      row <- site_rows[which.max(site_rows$area_ha), ]
      message(sprintf(
        "[focal nodes] %s has no patch >= %g ha -- falling back to its single largest patch (id %d, %.2f ha, tier %s).",
        site_id, min_area_ha, row$patch_id, row$area_ha, row$tier
      ))
      row
    })
    out <- do.call(rbind, c(list(out), fallback_rows))
  }

  out[order(out$primary_site_id, -out$area_ha), ]
}

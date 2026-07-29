# Consensus mapping, bottleneck/barrier candidates, and protection/restoration priority surfaces
# (plan Sec.11-12). Operates on step 07's resistance/source-strength rasters and step 09-10's
# Omniscape/Circuitscape outputs -- no new resistance/permeability logic here.

#' The raw value at the `pct`-th percentile of `r` (landscape-wide, not per-site) -- the building
#' block for every "high"/"low X" rule in this file (plan's own "use quantiles ... rather than
#' assuming one universal numeric threshold" guidance, Sec.9.5/12.1).
percentile_value <- function(r, pct) {
  as.numeric(terra::global(r, fun = quantile, probs = pct / 100, na.rm = TRUE)[1, 1])
}

above_percentile <- function(r, pct) r >= percentile_value(r, pct)
below_percentile <- function(r, pct) r <= percentile_value(r, pct)

#' Per-scenario high-current mask (plan Sec.12.2): normalized_current >= its own
#' HIGH_CURRENT_PERCENTILE-th percentile.
high_current_mask <- function(normalized_current_r) {
  above_percentile(normalized_current_r, HIGH_CURRENT_PERCENTILE)
}

#' Consensus score across scenarios (plan Sec.12.2/14.3): count of scenarios in which each cell
#' clears its own high-current mask. `normalized_current_list` is a named list of
#' normalized_current SpatRasters, one per Omniscape scenario.
consensus_score <- function(normalized_current_list) {
  masks <- lapply(normalized_current_list, high_current_mask)
  out <- Reduce(`+`, lapply(masks, function(m) terra::ifel(m, 1, 0)))
  names(out) <- "consensus_score"
  out
}

#' Moderate- and high-confidence bottleneck candidates (plan Sec.12.1), from ONE reference
#' scenario's normalized_current + the shared resistance surface, cross-checked against the
#' multi-scenario consensus_score for the high-confidence variant.
bottleneck_candidates <- function(normalized_current_r, resistance_r, consensus_r) {
  moderate <- above_percentile(normalized_current_r, BOTTLENECK_CURRENT_PERCENTILE) &
    above_percentile(resistance_r, BOTTLENECK_RESISTANCE_PERCENTILE)
  high_confidence <- above_percentile(normalized_current_r, BOTTLENECK_HC_CURRENT_PERCENTILE) &
    above_percentile(resistance_r, BOTTLENECK_HC_RESISTANCE_PERCENTILE) &
    (consensus_r >= BOTTLENECK_HC_MIN_SCENARIOS)
  out <- c(terra::ifel(moderate, 1, 0), terra::ifel(high_confidence, 1, 0))
  names(out) <- c("bottleneck_moderate", "bottleneck_high_confidence")
  out
}

#' Barrier candidates (plan Sec.12.3): high resistance AND high flow potential (i.e. current
#' "wants" to flow there under uniform resistance) AND low source strength.
barrier_candidates <- function(resistance_r, flow_potential_r, source_r) {
  out <- above_percentile(resistance_r, BARRIER_RESISTANCE_PERCENTILE) &
    above_percentile(flow_potential_r, BARRIER_FLOW_POTENTIAL_PERCENTILE) &
    below_percentile(source_r, BARRIER_SOURCE_PERCENTILE)
  out <- terra::ifel(out, 1, 0)
  names(out) <- "barrier_candidate"
  out
}

#' Protection priority (plan Sec.12.7): high source strength AND high current AND low resistance.
#' The plan's own third clause ("conversion or settlement pressure is nearby or increasing") is a
#' qualitative field/monitoring judgment, not a rasterizable rule with a defined formula here --
#' `settlement_pressure_r` is accepted so callers can report it alongside the binary candidate
#' layer for that manual review step, not folded into the boolean rule itself.
protection_priority <- function(source_r, current_r, resistance_r) {
  out <- above_percentile(source_r, PROTECTION_SOURCE_PERCENTILE) &
    above_percentile(current_r, PROTECTION_CURRENT_PERCENTILE) &
    below_percentile(resistance_r, PROTECTION_RESISTANCE_PERCENTILE)
  out <- terra::ifel(out, 1, 0)
  names(out) <- "protection_priority"
  out
}

#' Restoration priority (plan Sec.12.6): high current/flow potential AND moderate-high resistance
#' AND NOT already hard built conversion (built_fraction < BUILT_FRACTION_RESISTANCE_FLOOR$threshold).
restoration_priority <- function(current_or_flow_r, resistance_r, built_fraction_r) {
  out <- above_percentile(current_or_flow_r, RESTORATION_CURRENT_PERCENTILE) &
    above_percentile(resistance_r, RESTORATION_RESISTANCE_PERCENTILE) &
    (built_fraction_r < BUILT_FRACTION_RESISTANCE_FLOOR$threshold)
  out <- terra::ifel(out, 1, 0)
  names(out) <- "restoration_priority"
  out
}

#' Mean/max of a current-flow raster within each patch (no buffer) -- reuses
#' R/patches.R's mean_within_patches() pattern but also computes max, since the plan's patch
#' attribute table (Sec.10.2) wants both mean_omniscape_current and max_omniscape_current.
patch_current_stats <- function(patch_poly, current_r, prefix) {
  mean_vals <- terra::extract(current_r, patch_poly, fun = mean, na.rm = TRUE, ID = FALSE)[[1]]
  max_vals <- terra::extract(current_r, patch_poly, fun = max, na.rm = TRUE, ID = FALSE)[[1]]
  out <- data.frame(patch_id = patch_poly$patch_id, mean_vals, max_vals)
  names(out)[2:3] <- c(paste0("mean_", prefix), paste0("max_", prefix))
  out
}

#' Patch-level protection_importance_score (plan Sec.11.3), using normalize01() from
#' R/scoring.R. `stepping_stone_position` proxy: mean Circuitscape all-to-one current within the
#' patch (how much network current passes through it) -- an Objective-4-native replacement for
#' Objective 3's Euclidean-graph betweenness, per the plan's own resolution that this objective's
#' real current-flow output supersedes that structural approximation.
compute_protection_importance <- function(connectivity_contribution, source_strength, core_area_ha,
                                           stepping_stone_position, settlement_pressure) {
  w <- PROTECTION_IMPORTANCE_WEIGHTS
  w[["connectivity_contribution"]] * normalize01(connectivity_contribution) +
    w[["source_strength"]] * normalize01(source_strength) +
    w[["core_area"]] * normalize01(core_area_ha) +
    w[["stepping_stone_position"]] * normalize01(stepping_stone_position) +
    w[["inverse_human_pressure"]] * (1 - normalize01(settlement_pressure))
}

#' Patch-level restoration_importance_score (plan Sec.11.4) -- see RESTORATION_IMPORTANCE_WEIGHTS'
#' own comment for why this is on a smaller scale than protection_importance (two plan components
#' with no defined formula are omitted, not renormalized in).
compute_restoration_importance <- function(current_or_flow_potential, resistance, proximity_to_focal_linkage) {
  w <- RESTORATION_IMPORTANCE_WEIGHTS
  w[["current_or_flow_potential"]] * normalize01(current_or_flow_potential) +
    w[["resistance_or_degradation"]] * normalize01(resistance) +
    w[["proximity_to_focal_linkage"]] * normalize01(proximity_to_focal_linkage)
}

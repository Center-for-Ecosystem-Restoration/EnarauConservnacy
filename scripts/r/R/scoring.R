# Generic scoring helpers shared across objectives: GLOBAL normalization across all patches/pixels
# pooled together, not per-site -- appropriate since the goal is cross-site prioritization, not a
# within-site ranking. Per-site normalization would make each site's single largest patch always
# score 1.0 locally regardless of true landscape-scale importance.
#
# Objective 3's Euclidean patch-graph-derived scores formerly here were removed 2026-07-29,
# superseded by Objective 4's Circuitscape/Omniscape analysis. normalize01() and
# distance_decay_score() below are unaffected -- both are reused by Objective 4's R/consensus.R.

#' Min-max normalize to [0, 1]. NA-safe (ignores NA in range calc; propagates NA through).
normalize01 <- function(x) {
  rng <- range(x, na.rm = TRUE)
  if (diff(rng) == 0 || !is.finite(diff(rng))) {
    return(rep(if (length(x) > 0) 0.5 else numeric(0), length(x)))
  }
  (x - rng[1]) / diff(rng)
}

#' Linear distance-decay score from a reference geometry: 1 at the boundary, decaying to 0 at
#' `decay_m`.
distance_decay_score <- function(r_or_points, reference_sf, decay_m = CORRIDOR_PROXIMITY_DECAY_M) {
  ref_union <- sf::st_union(reference_sf)
  if (inherits(r_or_points, "SpatRaster")) {
    dist_r <- terra::distance(r_or_points, terra::vect(ref_union))
    score <- 1 - terra::clamp(dist_r / decay_m, lower = 0, upper = 1)
    names(score) <- "corridor_proximity_score"
    return(score)
  }
  dist_v <- as.numeric(sf::st_distance(r_or_points, ref_union))
  pmax(0, 1 - dist_v / decay_m)
}

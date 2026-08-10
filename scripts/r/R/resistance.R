# Land-cover permeability/confidence, resistance Models A/B/C, and source-strength surfaces.
# Requires 06_prepare_connectivity_inputs.R to have already run -- consumes the aligned 30m
# layers it writes to CONNECTIVITY_RASTER_DIR; nothing here reads a raw input directly.

#' Weighted sum of a class_fraction_stack()'s per-class bands against a named lookup of
#' class-name -> value (e.g. LANDCOVER_PERMEABILITY): sum(class_fraction_i * class_value_i).
weighted_class_layer <- function(fraction_stack, values) {
  class_names <- names(values)
  band_names <- paste0(class_names, "_fraction")
  missing <- setdiff(band_names, names(fraction_stack))
  if (length(missing) > 0) stop("fraction_stack is missing bands: ", paste(missing, collapse = ", "))
  layers <- lapply(seq_along(class_names), function(i) {
    fraction_stack[[band_names[i]]] * values[[class_names[i]]]
  })
  Reduce(`+`, layers)
}

#' Fraction-weighted land-cover permeability, from LANDCOVER_PERMEABILITY.
landcover_permeability <- function(fraction_stack) {
  out <- weighted_class_layer(fraction_stack, LANDCOVER_PERMEABILITY)
  names(out) <- "landcover_permeability"
  out
}

#' Build a class_name -> confidence-value lookup from accuracy_metrics_pixels.csv (computed
#' against the 8-class training scheme, RF_CLASS_REMAP'd down to the 7-class delivered scheme).
#' Where two training classes collapse into one delivered class, users_accuracy is averaged,
#' weighted by `support`, matching how the delivered raster pools their pixels.
build_landcover_confidence_crosswalk <- function(accuracy_path = RF_ACCURACY_PIXELS_PATH) {
  acc <- utils::read.csv(accuracy_path, stringsAsFactors = FALSE)
  acc$final_class_id <- RF_CLASS_REMAP[as.character(acc$class_id)]
  agg <- stats::aggregate(
    cbind(weighted = users_accuracy * support, support) ~ final_class_id, data = acc, FUN = sum
  )
  agg$confidence <- agg$weighted / agg$support
  out <- agg$confidence
  names(out) <- unname(RF_FINAL_CLASS_LABELS[as.character(agg$final_class_id)])
  out
}

#' Fraction-weighted land-cover classification confidence, from a crosswalk built by
#' build_landcover_confidence_crosswalk().
landcover_confidence <- function(fraction_stack, confidence_crosswalk) {
  out <- weighted_class_layer(fraction_stack, confidence_crosswalk)
  names(out) <- "landcover_confidence"
  out
}

#' permeability -> resistance: 1 + (rmax - 1) * (1 - permeability)^gamma.
#' gamma = 1 (linear) is the production default; higher gamma is a sensitivity-test variant.
to_resistance <- function(permeability, rmax, gamma = 1) {
  permeability <- clamp01(permeability)
  1 + (rmax - 1) * (1 - permeability)^gamma
}

#' Build Resistance Models A (land-cover baseline), B (+ human/road pressure), and C (+
#' condition/terrain/riparian) as a named 3-band SpatRaster. All inputs must already share the
#' master grid.
#' @param landcover_perm,human_perm,road_perm,condition,terrain_perm,riparian_factor,built_fraction
#'   Aligned 30m SpatRaster layers (human_perm = 1-settlement_pressure, road_perm =
#'   1-road_pressure, terrain_perm = 1-slope_scaled, riparian_factor = neutral or facilitation
#'   scenario -- see riparian_factor_scenario()).
build_resistance_models <- function(landcover_perm, human_perm, road_perm, condition,
                                     terrain_perm, riparian_factor, built_fraction) {
  w_b <- RESISTANCE_B_WEIGHTS
  w_c <- RESISTANCE_C_WEIGHTS
  rmax <- RESISTANCE_RMAX
  floor_spec <- BUILT_FRACTION_RESISTANCE_FLOOR

  perm_a <- landcover_perm
  perm_b <- clamp01(w_b["landcover"] * landcover_perm + w_b["human"] * human_perm + w_b["road"] * road_perm)
  perm_c <- clamp01(
    w_c["landcover"] * landcover_perm + w_c["human"] * human_perm + w_c["road"] * road_perm +
      w_c["condition"] * condition + w_c["terrain"] * terrain_perm + w_c["riparian"] * riparian_factor
  )

  resistance_a <- to_resistance(perm_a, rmax = rmax[["A"]])
  resistance_b <- to_resistance(perm_b, rmax = rmax[["B"]])
  resistance_c <- to_resistance(perm_c, rmax = rmax[["C"]])

  built_floor <- built_fraction >= floor_spec$threshold
  resistance_b <- terra::ifel(built_floor & resistance_b < floor_spec$floor, floor_spec$floor, resistance_b)
  resistance_c <- terra::ifel(built_floor & resistance_c < floor_spec$floor, floor_spec$floor, resistance_c)

  out <- c(resistance_a, resistance_b, resistance_c)
  names(out) <- c("resistance_A", "resistance_B", "resistance_C")
  out
}

#' Neutral (constant 0.50) or facilitation (0.50 outside / RIPARIAN_FACTOR_FACILITATION where
#' riparian_natural_cover==1) riparian-factor scenario raster.
riparian_factor_scenario <- function(riparian_natural_cover, scenario = c("neutral", "facilitation")) {
  scenario <- match.arg(scenario)
  if (scenario == "neutral") {
    out <- riparian_natural_cover * 0 + RIPARIAN_FACTOR_NEUTRAL
  } else {
    out <- terra::ifel(riparian_natural_cover == 1, RIPARIAN_FACTOR_FACILITATION, RIPARIAN_FACTOR_NEUTRAL)
  }
  names(out) <- paste0("riparian_factor_", scenario)
  out
}

#' Primary + conservative source-strength rasters.
#' @param natural_fraction,condition,human_perm,built_fraction,settlement_pressure,road_pressure
#'   Aligned 30m SpatRaster layers.
build_source_strength <- function(natural_fraction, condition, human_perm, built_fraction,
                                   settlement_pressure, road_pressure) {
  criteria <- SOURCE_CONSERVATIVE_CRITERIA
  floor_spec <- BUILT_FRACTION_RESISTANCE_FLOOR

  source_primary <- clamp01(natural_fraction * condition * human_perm)
  source_primary <- terra::ifel(built_fraction >= floor_spec$threshold, 0, source_primary)

  conservative_mask <- (natural_fraction >= criteria$natural_fraction_min) &
    (settlement_pressure <= criteria$settlement_pressure_max) &
    (road_pressure <= criteria$road_pressure_max) &
    (condition >= criteria$condition_score_min)
  source_conservative <- terra::ifel(conservative_mask, source_primary, 0)

  out <- c(source_primary, source_conservative)
  names(out) <- c("source_primary", "source_conservative")
  out
}

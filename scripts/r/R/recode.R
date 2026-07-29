# Derived-raster recodes from a habitat_class raster. Expect values 1-8 with NA elsewhere if
# loaded via read_habitat_raster() (which already substitutes literal 0 -> NA). The explicit
# "0 -> NA" mappings below are defense-in-depth for callers passing a raw, not-yet-normalized raster.

#' Full habitat-class raster for composition/fragmentation metrics: masks out water/flooded
#' vegetation (7) and uncertain (8), keeping classes 1-6.
recode_full_habitat <- function(r) {
  # terra::classify()'s default (others = NULL) leaves unlisted values (here, classes 1-6)
  # unchanged, so no `others=` argument is needed.
  out <- terra::classify(r, rcl = matrix(c(0, NA, 7, NA, 8, NA), ncol = 2, byrow = TRUE))
  names(out) <- "habitat_class"
  out
}

#' Binary natural-habitat raster: 1 = natural (woody/grassland/mixed natural), 0 = conversion
#' pressure classes (cropland/built/bare-degraded), NA = no classification/water/flooded veg/uncertain.
make_natural_binary <- function(r) {
  out <- terra::classify(
    r,
    rcl = matrix(c(0, NA, 1, 1, 2, 1, 3, 1, 4, 0, 5, 0, 6, 0, 7, NA, 8, NA), ncol = 2, byrow = TRUE)
  )
  names(out) <- "natural_binary"
  out
}

#' Current-period binary natural-habitat raster, reconciled against Objective 1's own
#' natural_habitat_mask export.
#'
#' natural_habitat_mask is 1/NA-only (built via .selfMask()), so it can't represent "0 = converted
#' but valid" and can't be a drop-in replacement for make_natural_binary(). Instead: build the
#' 0-class from a plain reclass of the current habitat_class raster, then DEMOTE any pixel the
#' plain reclass called "natural" (1) to NA wherever Objective 1's stricter QA gate
#' (top1_prob/valid_obs_count, see DW_CONNECTIVITY_THRESHOLDS in config.py) does not also confirm
#' it as natural -- never promote a pixel the plain reclass called 0 or NA.
#'
#' Verify the two rasters agree on >95% of valid pixels (see 01_prepare_inputs.R) -- a bigger gap
#' means the QA gate is dropping more than expected and needs investigation.
build_current_binary_natural <- function(current_class_r, natural_habitat_mask_r) {
  plain <- make_natural_binary(current_class_r)
  # natural_habitat_mask_r is 1/NA; align it to plain's grid before comparing.
  mask_aligned <- terra::resample(natural_habitat_mask_r, plain, method = "near")
  downgrade <- is.na(mask_aligned) & (plain == 1)
  out <- terra::ifel(downgrade, NA, plain)
  names(out) <- "natural_binary_current_reconciled"
  out
}

#' % of valid (non-NA) pixels where `plain` and `reconciled` agree. Prints a PASS/INVESTIGATE
#' message rather than failing silently.
check_mask_reuse_agreement <- function(plain, reconciled) {
  p <- terra::values(plain, na.rm = FALSE)
  r <- terra::values(reconciled, na.rm = FALSE)
  either_valid <- !is.na(p) | !is.na(r)
  agree <- (is.na(p) & is.na(r)) | (!is.na(p) & !is.na(r) & p == r)
  pct_agree <- if (sum(either_valid) > 0) sum(agree & either_valid) / sum(either_valid) else NA_real_
  status <- if (!is.na(pct_agree) && pct_agree > 0.95) "PASS" else "INVESTIGATE"
  message(sprintf(
    "[%s] Current-period binary-natural mask-reuse agreement: %.2f%% of valid pixels (expect >95%%).",
    status, 100 * pct_agree
  ))
  invisible(pct_agree)
}

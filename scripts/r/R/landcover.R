# Land-cover fraction/permeability helpers for Objective 4. Operates on the Airbus RF classifier's
# 10m delivered raster (RF_FINAL_CLASS_LABELS, see 00_config.R) -- NOT Objective 1's Dynamic World
# scheme.

#' Aggregate the 10m land-cover raster to fraction-per-class bands on the 30m master grid. Each
#' output band is the fraction of VALID (non-NA) fine cells within a coarse cell that belong to
#' that class -- not a literal class-cell-count/9 -- so a coarse cell straddling the classified
#' raster's edge reports composition among only its classified sub-pixels, rather than being
#' diluted by out-of-AOI padding. A companion `valid_fraction` band (literal count-valid/9) lets
#' callers flag/mask low-confidence coarse cells; any coarse cell with valid_fraction == 0 (fully
#' outside the classified extent) is masked to NA across every band.
#'
#' @param lc_path Path to the 10m land-cover GeoTIFF (categorical, RF_FINAL_CLASS_LABELS scheme).
#' @param master_grid The 30m master-grid SpatRaster (build_master_grid()).
#' @param class_labels Named vector, class_id -> class_name (default RF_FINAL_CLASS_LABELS).
#' @param fine_resolution_m Native resolution of `lc_path` (default
#'   CONNECTIVITY_LANDCOVER_SOURCE_RESOLUTION_M, 10m).
class_fraction_stack <- function(lc_path, master_grid, class_labels = RF_FINAL_CLASS_LABELS,
                                  fine_resolution_m = CONNECTIVITY_LANDCOVER_SOURCE_RESOLUTION_M) {
  lc <- terra::rast(lc_path)
  fine_grid <- build_nested_fine_grid(master_grid, fine_resolution_m)
  lc_aligned <- align_to_grid(lc, fine_grid, method = "near")

  fact <- CONNECTIVITY_GRID_RESOLUTION_M / fine_resolution_m
  if (fact != round(fact)) {
    stop("Master grid resolution is not an exact multiple of fine_resolution_m -- got fact = ", fact)
  }

  class_ids <- as.integer(names(class_labels))
  fraction_bands <- lapply(class_ids, function(cid) {
    ind <- terra::ifel(lc_aligned == cid, 1, 0)
    terra::aggregate(ind, fact = fact, fun = "mean", na.rm = TRUE)
  })
  fractions <- do.call(c, fraction_bands)
  names(fractions) <- paste0(unname(class_labels[as.character(class_ids)]), "_fraction")

  valid_ind <- terra::ifel(is.na(lc_aligned), 0, 1)
  valid_fraction <- terra::aggregate(valid_ind, fact = fact, fun = "mean", na.rm = TRUE)
  names(valid_fraction) <- "valid_fraction"

  out <- c(fractions, valid_fraction)
  terra::mask(out, valid_fraction, maskvalue = 0)
}

#' Sum a class-fraction stack's bands for a set of class IDs into one grouped-fraction layer
#' (e.g. NATURAL_LC_CLASSES -> natural_fraction). `class_ids` indexes into `class_labels` the
#' same way class_fraction_stack() built the band names.
grouped_fraction <- function(fraction_stack, class_ids, class_labels = RF_FINAL_CLASS_LABELS) {
  band_names <- paste0(unname(class_labels[as.character(class_ids)]), "_fraction")
  sum(fraction_stack[[band_names]])
}

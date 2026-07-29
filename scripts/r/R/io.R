# Input manifest for Objective 1's manually-downloaded Dynamic World raster exports
# (DW_INPUT_RASTER_DIR, see 00_config.R). Local filenames drop each Drive export cell's filename
# prefix (seasonal_categorical_/conversion_pressure_/connectivity_inputs_/transitions_), so every
# file starts directly at "DW_", matching the band/class scheme in
# scripts/python/notebooks/historical_change_detection.ipynb.

expand_seasonal_manifest <- function() {
  years <- 2016:2025
  seasons <- c("wet", "dry")
  grid <- expand.grid(year = years, season = seasons, stringsAsFactors = FALSE)
  grid$habitat_class_file <- file.path(
    DW_INPUT_RASTER_DIR,
    sprintf("DW_class_%s_%d_project.tif", grid$season, grid$year)
  )
  grid$pressure_file <- file.path(
    DW_INPUT_RASTER_DIR,
    sprintf("DW_pressure_%s_%d_project.tif", grid$season, grid$year)
  )
  grid
}

period_manifest <- data.frame(
  token = DW_PERIOD_TOKENS,
  stack_file = file.path(
    DW_INPUT_RASTER_DIR,
    sprintf("DW_connectivity_inputs_%s_project.tif", DW_PERIOD_TOKENS)
  ),
  class_file = file.path(
    DW_INPUT_RASTER_DIR,
    sprintf("DW_class_%s_project.tif", DW_PERIOD_TOKENS)
  ),
  pressure_file = file.path(
    DW_INPUT_RASTER_DIR,
    sprintf("DW_pressure_%s_project.tif", DW_PERIOD_TOKENS)
  ),
  stringsAsFactors = FALSE
)

# 9-band stack order, matching config.py's DW_DERIVED_BANDS exactly
DW_STACK_BAND_NAMES <- c(
  "natural_prob", "woody_prob", "grass_prob", "conversion_pressure_prob",
  "hard_conversion_prob", "bare_degradation_prob", "water_wetland_prob",
  "top1_prob", "valid_obs_count"
)

TRANSITION_FILES <- c(
  baseline_to_current = file.path(DW_INPUT_RASTER_DIR, "DW_transition_baseline_2016_2018_to_current_2022_2025_project.tif"),
  pre_to_current       = file.path(DW_INPUT_RASTER_DIR, "DW_transition_pre_2019_2021_to_current_2022_2025_project.tif")
)

MASK_FILES <- c(
  analysis_mask           = file.path(DW_INPUT_RASTER_DIR, "DW_connectivity_analysis_mask_project.tif"),
  natural_habitat_mask     = file.path(DW_INPUT_RASTER_DIR, "DW_natural_habitat_mask_current_2022_2025_project.tif"),
  high_quality_source_mask = file.path(DW_INPUT_RASTER_DIR, "DW_high_quality_source_mask_current_2022_2025_project.tif")
)

#' Check which expected input rasters are present locally.
#' @param strict If TRUE, stop() on any missing file. If FALSE, warn() and return the missing
#'   list -- use FALSE for a partial-download smoke test.
check_inputs_present <- function(strict = TRUE) {
  seasonal <- expand_seasonal_manifest()
  files <- c(
    period_manifest$stack_file, period_manifest$class_file, period_manifest$pressure_file,
    seasonal$habitat_class_file, seasonal$pressure_file,
    TRANSITION_FILES, MASK_FILES
  )
  missing <- files[!file.exists(files)]
  if (length(missing) > 0) {
    msg <- sprintf(
      "%d/%d expected input rasters missing from %s:\n%s",
      length(missing), length(files), DW_INPUT_RASTER_DIR,
      paste(missing, collapse = "\n")
    )
    if (strict) stop(msg) else warning(msg, call. = FALSE)
  } else {
    message(sprintf("All %d expected input rasters present in %s.", length(files), DW_INPUT_RASTER_DIR))
  }
  invisible(missing)
}

#' Read a habitat_class raster, verify it matches the expected 1-8 class scheme, and normalize
#' its NoData representation to real NA.
#'
#' Every export carries a correctly-registered `-9999` GDAL NoData tag that terra applies
#' silently on read -- literal -9999 should never appear in terra::values() (checking via
#' terra::NAflag() instead is misleading: it reports a user-set override, not whether the
#' embedded tag is honored). Separately, rasters exported after a terminal `.clip(project_geom)`
#' also carry a literal `0` fill outside the true AOI polygon but inside the export's rectangular
#' bounding box (an upstream eetools export bug, since fixed). For habitat_class this is harmless
#' to detect: `0` is never a real class (1-8), so it's unambiguous regardless of position. This
#' function converts `0 -> NA` immediately so downstream consumers can rely on ordinary is.na()
#' semantics -- do not read habitat_class rasters via bare terra::rast() elsewhere. (Contrast with
#' read_pressure_raster(), where `0` is a real class value and this trick does not work.)
read_habitat_raster <- function(path) {
  if (!file.exists(path)) stop("Habitat raster not found: ", path)
  r <- terra::rast(path)
  crs_code <- tryCatch(terra::crs(r, describe = TRUE)$code, error = function(e) NA)
  if (is.na(crs_code) || crs_code != "32736") {
    warning(path, ": CRS did not resolve to EPSG:32736 (got ", crs_code, ") -- verify before trusting downstream results")
  }
  vals <- terra::values(r, na.rm = TRUE)
  if (length(vals) > 0) {
    if (any(vals == NODATA_SENTINEL)) {
      warning(path, ": literal -9999 present -- unexpected given empirical findings, investigate before trusting this file")
    }
    if (any(!vals %in% 0:8)) {
      stop(path, ": value outside the 0-8 habitat class scheme found (0 = no classification/outside AOI, 1-8 = real classes)")
    }
  }
  r <- terra::subst(r, 0, NA)
  names(r) <- "habitat_class"
  r
}

#' Read a pressure_class raster (values 0/1/2 -- 0 = "Low" is a REAL class here, unlike
#' habitat_class's 0). Has the same literal-0 exterior-fringe defect as habitat_class, but the
#' 0->NA trick doesn't work here since 0 is also a real "Low" value inside the true AOI --
#' indistinguishable by value alone. Instead masks to the reconstructed project_geom polygon
#' (build_project_geom()/project_geom_vect(), below), converting everything outside the true AOI
#' to NA regardless of value. Only rasters exported before the upstream eetools fix need this clip.
read_pressure_raster <- function(path) {
  if (!file.exists(path)) stop("Pressure raster not found: ", path)
  r <- terra::rast(path)
  r <- terra::mask(r, project_geom_vect())
  vals <- terra::values(r, na.rm = TRUE)
  if (length(vals) > 0) {
    if (any(vals == NODATA_SENTINEL)) {
      warning(path, ": literal -9999 present -- unexpected, investigate")
    }
    if (any(!vals %in% 0:2)) {
      stop(path, ": value outside the 0-2 pressure class scheme found (0=Low, 1=Moderate, 2=High)")
    }
  }
  names(r) <- "pressure_class"
  r
}

#' Read the 9-band period probability/derived stack and apply DW_STACK_BAND_NAMES. Unlike
#' habitat_class/pressure_class, these rasters don't have the exterior-fringe defect.
read_period_stack <- function(path) {
  if (!file.exists(path)) stop("Period stack raster not found: ", path)
  r <- terra::rast(path)
  if (terra::nlyr(r) != length(DW_STACK_BAND_NAMES)) {
    stop(path, ": expected ", length(DW_STACK_BAND_NAMES), " bands, found ", terra::nlyr(r))
  }
  names(r) <- DW_STACK_BAND_NAMES
  r
}

#' Read + reproject a site boundary GeoJSON to PROJECT_CRS. Source GeoJSONs are WGS84 lon/lat --
#' always reproject before any raster crop/mask/area operation.
read_site_boundary <- function(site_id) {
  path <- AOI_PATHS[[site_id]]
  if (is.null(path)) stop("Unknown site_id: ", site_id)
  sf::st_read(path, quiet = TRUE) |> sf::st_transform(crs = PROJECT_CRS)
}

# Reconstruction of the notebook's `project_geom` (union of the 4 SITES polygons, buffered by
# STUDY_AREA_BUFFER_M), used to work around the pressure_class exterior-fringe defect. This is a
# PLANAR buffer (sf::st_buffer() in EPSG:32736) vs GEE's GEODESIC `.buffer(150, maxError=10)` --
# expect a sub-pixel discrepancy at the boundary, immaterial at 10m resolution.
.project_geom_cache <- new.env(parent = emptyenv())

#' Build (or return the cached) reconstructed project_geom polygon, as an sf object in
#' PROJECT_CRS. Memoized per R session since many scripts read rasters that each need it.
build_project_geom <- function(force_refresh = FALSE) {
  if (!force_refresh && !is.null(.project_geom_cache$geom)) return(.project_geom_cache$geom)
  geoms <- do.call(c, lapply(SITES$site_id, function(sid) sf::st_geometry(read_site_boundary(sid))))
  buffered <- sf::st_buffer(sf::st_union(sf::st_make_valid(geoms)), dist = STUDY_AREA_BUFFER_M)
  .project_geom_cache$geom <- sf::st_sf(geometry = buffered)
  .project_geom_cache$geom
}

#' terra::vect() version of build_project_geom(), for direct use in terra::mask().
project_geom_vect <- function(force_refresh = FALSE) {
  terra::vect(build_project_geom(force_refresh))
}

#' Read a transition_code raster (from_class*10 + to_class, valid codes are both digits 1-8,
#' i.e. 11-88) and validate it. Built via arithmetic on two already-clipped habitat_class images,
#' which avoids the exterior-fringe defect -- no clip needed here.
read_transition_raster <- function(path) {
  if (!file.exists(path)) stop("Transition raster not found: ", path)
  r <- terra::rast(path)
  vals <- terra::values(r, na.rm = TRUE)
  if (length(vals) > 0) {
    valid_codes <- as.vector(outer(1:8, 1:8, function(a, b) a * 10 + b))
    if (any(!vals %in% valid_codes)) {
      stop(path, ": transition code outside the valid from*10+to (1-8 x 1-8) scheme found -- ",
           "investigate before trusting this file")
    }
  }
  names(r) <- "transition_code"
  r
}

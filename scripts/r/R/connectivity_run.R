# Orchestration for Circuitscape.jl/Omniscape.jl runs, called as a Julia SUBPROCESS (circuitscaper's
# own R API is unusable on R 4.5+, see 00_config.R). Writes INI config text, invokes `julia.exe`,
# and hands back the output directory for the caller to read with terra::rast().

#' Convert backslashes to forward slashes -- Julia's INI parser and GDAL expect the latter.
to_unix_path <- function(path) gsub("\\\\", "/", path)

#' TRUE/FALSE -> "True"/"False" for Circuitscape.jl/Omniscape.jl's configparser-style INI.
ini_bool <- function(x) if (isTRUE(x)) "True" else "False"

#' Write an Omniscape.jl INI config file.
#'
#' `project_dir` must NOT already exist -- Omniscape.jl silently auto-increments to a numbered
#' sibling instead of reusing it, orphaning results. Keep input rasters in a separate directory.
#' @return The config file path (invisibly).
write_omniscape_config <- function(resistance_path, source_path, radius_cells, project_dir,
                                    config_path,
                                    source_threshold = SOURCE_THRESHOLD_PRIMARY,
                                    block_size = OMNISCAPE_BLOCK_SIZE,
                                    calc_normalized_current = TRUE, calc_flow_potential = TRUE,
                                    parallelize = TRUE) {
  if (dir.exists(project_dir)) {
    stop(
      "project_dir already exists (", project_dir, ") -- Omniscape.jl would silently create a ",
      "numbered sibling instead of reusing it. Remove it first to force a re-run."
    )
  }
  dir.create(dirname(config_path), recursive = TRUE, showWarnings = FALSE)

  lines <- c(
    "[Required]",
    paste0("resistance_file = ", to_unix_path(resistance_path)),
    paste0("radius = ", radius_cells),
    paste0("project_name = ", to_unix_path(project_dir)),
    "",
    "[General options]",
    paste0("source_file = ", to_unix_path(source_path)),
    paste0("source_threshold = ", source_threshold),
    "r_cutoff = Inf",
    paste0("block_size = ", block_size),
    "",
    "[Output options]",
    "write_raw_currmap = True",
    paste0("calc_normalized_current = ", ini_bool(calc_normalized_current)),
    paste0("calc_flow_potential = ", ini_bool(calc_flow_potential)),
    "write_as_tif = True",
    "",
    "[Multiprocessing options]",
    paste0("parallelize = ", ini_bool(parallelize))
  )
  writeLines(lines, config_path)
  invisible(config_path)
}

#' Write a Circuitscape.jl INI config file. `scenario` is "pairwise" or "all-to-one".
#' @return The config file path (invisibly).
write_circuitscape_config <- function(habitat_path, point_path, output_base,
                                       scenario = c("pairwise", "all-to-one"),
                                       write_cur_maps = TRUE, write_cum_cur_map_only = FALSE) {
  scenario <- match.arg(scenario)
  output_dir <- dirname(output_base)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  config_path <- paste0(output_base, "_config.ini")

  lines <- c(
    "[Circuitscape mode]",
    paste0("scenario = ", scenario),
    "data_type = raster",
    "",
    "[Habitat raster or graph]",
    paste0("habitat_file = ", to_unix_path(habitat_path)),
    "habitat_map_is_resistances = True",
    "",
    "[Options for pairwise and one-to-all and all-to-one modes]",
    paste0("point_file = ", to_unix_path(point_path)),
    "use_included_pairs = False",
    "",
    "[Output options]",
    paste0("output_file = ", to_unix_path(output_base)),
    paste0("write_cur_maps = ", ini_bool(write_cur_maps)),
    paste0("write_cum_cur_map_only = ", ini_bool(write_cum_cur_map_only)),
    "write_as_tif = True"
  )
  writeLines(lines, config_path)
  invisible(config_path)
}

#' Run one of the two scripts/julia/*.jl entry points as a subprocess against `config_path`.
#' Returns a one-row data.frame for accumulating into a run-manifest table.
#' @param tool "omniscape" or "circuitscape".
run_julia_connectivity <- function(tool = c("omniscape", "circuitscape"), config_path,
                                    threads = JULIA_THREADS, label = basename(dirname(config_path))) {
  tool <- match.arg(tool)
  script_path <- file.path(JULIA_SCRIPTS_DIR, sprintf("run_%s.jl", tool))
  log_path <- paste0(config_path, ".log")

  message(sprintf("[%s] Running %s (threads=%d)...", label, tool, threads))
  t0 <- Sys.time()
  status <- system2(
    JULIA_BIN,
    args = c(sprintf("-t %d", threads), shQuote(script_path), shQuote(config_path)),
    stdout = log_path, stderr = log_path
  )
  elapsed_s <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (status != 0) {
    warning(sprintf("[%s] %s exited with status %d -- see %s", label, tool, status, log_path))
  } else {
    message(sprintf("[%s] %s completed in %.1fs.", label, tool, elapsed_s))
  }

  data.frame(
    label = label, tool = tool, config_path = config_path, log_path = log_path,
    status = status, elapsed_s = elapsed_s, timestamp = as.character(Sys.time())
  )
}

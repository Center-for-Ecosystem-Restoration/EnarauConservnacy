# Step 09 (Objective 4): Omniscape runs.
#
# RUN AS: cd scripts/r && Rscript 09_run_omniscape.R
#
# Requires 07_build_resistance_source_surfaces.R to have already run. Builds OMNISCAPE_RUN_SET
# (00_config.R) as an explicit task list. Omniscape auto-increments its project_name output dir
# instead of erroring if it already exists, so an `output/` directory existing is used as the
# "already run" signal for idempotent re-runs (see R/connectivity_run.R's
# write_omniscape_config() for why inputs and output live in separate directories).
#
# RUN_FULL_BATCH defaults to FALSE: real runs take up to ~16.5 min (C_r200, largest radius), and
# the tool driving this script caps any single command at 10 minutes -- so each remaining scenario
# is launched as its own separate invocation rather than looping through all of them in one call.

source("00_config.R")
source("R/io.R")
source("R/grid.R")
source("R/connectivity_run.R")

read_connectivity_raster <- function(name) {
  terra::rast(file.path(CONNECTIVITY_RASTER_DIR, paste0(name, ".tif")))
}

message("=== 09_run_omniscape: loading step-07 outputs ===")
resistance_models <- read_connectivity_raster("resistance_models_30m")
source_strength <- read_connectivity_raster("source_strength_models_30m")

omniscape_dir <- OMNISCAPE_OUTPUT_DIR

message("=== Staging per-scenario inputs + INI configs (skipping already-completed scenarios) ===")
scenario_specs <- lapply(OMNISCAPE_RUN_SET, function(spec) {
  radius_cells <- OMNISCAPE_RADII_CELLS[[spec$radius]]
  source_threshold <- if (spec$source == "conservative") OMNISCAPE_CONSERVATIVE_SOURCE_THRESHOLD else SOURCE_THRESHOLD_PRIMARY
  source_band <- if (spec$source == "conservative") "source_conservative" else "source_primary"

  label <- sprintf(
    "%s_r%d%s", spec$model, radius_cells,
    if (spec$source == "conservative") "_conservative_source" else ""
  )
  scenario_dir <- file.path(omniscape_dir, label)
  input_dir <- file.path(scenario_dir, "inputs")
  project_dir <- file.path(scenario_dir, "output")
  config_path <- file.path(scenario_dir, "config.ini")
  already_done <- dir.exists(project_dir)

  if (!already_done) {
    if (!dir.exists(input_dir)) dir.create(input_dir, recursive = TRUE)
    # Omniscape.jl needs whole single-band files, not the multi-band stack.
    resistance_path <- file.path(input_dir, "resistance.tif")
    source_path <- file.path(input_dir, "source.tif")
    terra::writeRaster(resistance_models[[paste0("resistance_", spec$model)]], resistance_path, overwrite = TRUE)
    terra::writeRaster(source_strength[[source_band]], source_path, overwrite = TRUE)

    write_omniscape_config(
      resistance_path = resistance_path, source_path = source_path, radius_cells = radius_cells,
      project_dir = project_dir, config_path = config_path, source_threshold = source_threshold
    )
  }

  list(label = label, scenario_dir = scenario_dir, project_dir = project_dir,
       config_path = config_path, already_done = already_done)
})
names(scenario_specs) <- vapply(scenario_specs, function(s) s$label, character(1))

for (s in scenario_specs) {
  message("  - ", s$label, if (s$already_done) " [already done]" else " [pending]")
}

manifest_path <- file.path(TABLES_DIR, "connectivity_omniscape_run_manifest.csv")
manifest <- if (file.exists(manifest_path)) readr::read_csv(manifest_path, show_col_types = FALSE) else NULL

# MANUAL GATE: keep FALSE -- see header comment for the runtime-cap rationale.
RUN_FULL_BATCH <- FALSE

todo <- Filter(function(s) !s$already_done, scenario_specs)
if (length(todo) == 0) {
  message("All ", length(scenario_specs), " scenarios already completed -- nothing to do.")
} else {
  run_now <- if (RUN_FULL_BATCH) todo else todo[1]
  message(sprintf("Running %d of %d remaining scenario(s)...", length(run_now), length(todo)))
  for (s in run_now) {
    result <- run_julia_connectivity("omniscape", s$config_path, label = s$label)
    manifest <- if (is.null(manifest)) result else rbind(manifest, result)
    readr::write_csv(manifest, manifest_path)
  }
}

message("=== 09_run_omniscape complete ===")
if (!is.null(manifest)) print(manifest[, c("label", "status", "elapsed_s")])

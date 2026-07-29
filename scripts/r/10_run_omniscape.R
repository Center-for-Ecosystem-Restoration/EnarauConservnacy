# Step 10 (Objective 4): Omniscape runs (plan Sec.9).
#
# RUN AS: cd scripts/r && Rscript 10_run_omniscape.R
#
# Requires 08_build_resistance_source_surfaces.R to have already run. Builds the full plan
# Sec.9.3 minimum run set (OMNISCAPE_RUN_SET, 00_config.R) as an explicit task list. Each
# scenario's `output/` directory existing is its own "already run" signal (idempotent re-runs) --
# see R/connectivity_run.R's write_omniscape_config() docs for why inputs and Omniscape's own
# project_name output must live in separate directories.
#
# First real-scale timing (2026-07-29, Model A r100, 408x450 grid, 4 threads): ~6.5 minutes;
# C_r200 (largest radius) took ~16.5 minutes. RUN_FULL_BATCH defaults to FALSE and stays that way
# -- the tool driving this script caps any single command (even backgrounded) at 10 minutes, so
# the calling agent runs each remaining scenario as its own separate invocation (or a fully
# detached process for anything expected to exceed ~8 minutes) rather than looping through all of
# them in one Rscript call, which silently gets killed mid-batch once that ceiling is hit.

source("00_config.R")
source("R/io.R")
source("R/grid.R")
source("R/connectivity_run.R")

read_connectivity_raster <- function(name) {
  terra::rast(file.path(CONNECTIVITY_RASTER_DIR, paste0(name, ".tif")))
}

message("=== 10_run_omniscape: loading step-08 outputs ===")
resistance_models <- read_connectivity_raster("resistance_models_30m")
source_strength <- read_connectivity_raster("source_strength_models_30m")

omniscape_dir <- file.path(CONNECTIVITY_OUTPUT_DIR, "omniscape")
if (!dir.exists(omniscape_dir)) dir.create(omniscape_dir, recursive = TRUE)

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
    # Omniscape.jl reads whole single-band files -- write each scenario's resistance/source band
    # out individually rather than pointing at the multi-band stack.
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

# MANUAL GATE: FALSE processes just one remaining scenario per script run instead of the whole
# batch -- see header comment for why this must stay FALSE given the calling tool's runtime cap.
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

message("=== 10_run_omniscape complete ===")
if (!is.null(manifest)) print(manifest[, c("label", "status", "elapsed_s")])

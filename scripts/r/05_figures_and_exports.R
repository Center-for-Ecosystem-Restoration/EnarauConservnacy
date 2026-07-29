# Objective 3: Objective 2 cross-check.
#
# RUN AS: cd scripts/r && Rscript 05_figures_and_exports.R
#
# Depends on 02 (transition tables, for landscape_net_natural_change_by_site.csv) and Objective
# 2's own LandTrendr event-summary tables. Run 02 first; this script skips gracefully (with a
# message) if its upstream tables aren't present yet.
#
# This script used to also synthesize a linkage_priority_score.tif/candidate_linkage_areas.gpkg
# from 05's Euclidean patch-graph output (betweenness, patch_importance_score). That synthesis
# was removed 2026-07-29 along with 05_patch_importance_graph.R and the rest of the patch-graph
# workflow -- see R/patch_graph.R's header comment for why (superseded by Objective 4's real
# Circuitscape/Omniscape current-flow analysis, scripts/r/06-11_*.R). This script's remaining
# Objective 2 cross-check below is independent of that removed workflow.
#
# Figures are NOT generated here -- all Objective 3 plotting lives in
# scripts/python/plotting/landscape_metrics.ipynb (pandas/matplotlib/seaborn), reading this
# script's and 03's table outputs from outputs/tables/, for consistency with Objectives 1-2's
# plotting convention (kept in Python, not duplicated per-language).

source("00_config.R")
source("R/io.R")

message("=== 05_figures_and_exports: Objective 2 cross-check ===")

net_natural_change_path <- file.path(TABLES_DIR, "landscape_net_natural_change_by_site.csv")
nbr_event_path <- file.path(TABLES_DIR, "landtrendr_nbrseg_event_summary_by_site.csv")
msavi2_event_path <- file.path(TABLES_DIR, "landtrendr_msavi2seg_event_summary_by_site.csv")

if (file.exists(net_natural_change_path) && file.exists(nbr_event_path) && file.exists(msavi2_event_path)) {
  net_natural_change <- readr::read_csv(net_natural_change_path, show_col_types = FALSE)
  nbr_events <- readr::read_csv(nbr_event_path, show_col_types = FALSE)
  msavi2_events <- readr::read_csv(msavi2_event_path, show_col_types = FALSE)

  # area_ha_sum in these CSVs is raw hectares, NOT pre-normalized by site area -- normalize here.
  site_areas_ha <- net_natural_change$site_area_ha
  names(site_areas_ha) <- net_natural_change$site_id

  normalize_landtrendr <- function(df, run_label) {
    if (!"area_ha_sum" %in% names(df)) return(NULL)
    df$pct_of_site_area <- 100 * df$area_ha_sum / site_areas_ha[df$site_id]
    df$run <- run_label
    df
  }
  nbr_norm <- normalize_landtrendr(nbr_events, "nbr_dry")
  msavi2_norm <- normalize_landtrendr(msavi2_events, "msavi2_wet")
  landtrendr_normalized <- rbind(nbr_norm, msavi2_norm)

  crosscheck <- net_natural_change |>
    dplyr::select(site_id, site_name, net_change_baseline_to_current_pct_of_site, net_change_pre_to_current_pct_of_site) |>
    dplyr::left_join(
      landtrendr_normalized |> dplyr::select(site_id, run, change_type, pct_of_site_area) |>
        tidyr::pivot_wider(names_from = c(run, change_type), values_from = pct_of_site_area, names_prefix = "landtrendr_"),
      by = "site_id"
    )

  # Load-bearing caveat check: does Enarau's natural-habitat-expansion signal also appear at
  # Mbokishi (the untouched reference site)? If so, it's more likely regional/rainfall-driven
  # than Enarau-specific conservation activity -- a site *diverging* from Mbokishi is the
  # defensible localized-effect claim (per the Objective 2->3 handoff notes).
  mbokishi_change <- crosscheck$net_change_baseline_to_current_pct_of_site[crosscheck$site_id == "mbokishi"]
  crosscheck$diverges_from_mbokishi_pct_points <- crosscheck$net_change_baseline_to_current_pct_of_site - mbokishi_change
  crosscheck$caveat <- ifelse(
    crosscheck$site_id != "mbokishi" & sign(crosscheck$net_change_baseline_to_current_pct_of_site) == sign(mbokishi_change) &
      abs(crosscheck$diverges_from_mbokishi_pct_points) < 2,
    "CAUTION: change direction/magnitude matches Mbokishi (untouched reference site) within 2 pct points -- likely regional/rainfall-driven, not necessarily Enarau-specific conservation effect.",
    "Diverges from Mbokishi's own trajectory -- more defensible as a localized effect."
  )

  readr::write_csv(crosscheck, file.path(TABLES_DIR, "landscape_vs_objective2_crosscheck_by_site.csv"))
  message("Wrote landscape_vs_objective2_crosscheck_by_site.csv. Caveat flags:")
  print(crosscheck[, c("site_id", "net_change_baseline_to_current_pct_of_site", "caveat")])
} else {
  message("Skipping Objective 2 cross-check -- run 02_area_transition_summaries.R first, and confirm ",
          "landtrendr_nbrseg_event_summary_by_site.csv / landtrendr_msavi2seg_event_summary_by_site.csv ",
          "are present in outputs/tables/ (from Objective 2).")
}

message("=== 05_figures_and_exports complete ===")
message("Figures: run scripts/python/plotting/landscape_metrics.ipynb to (re)generate plots from ",
        "this script's and 03's table outputs.")

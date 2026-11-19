# Package-wide imports and bindings ----

#' Package-wide imports and dynamically created column names
#'
#' Base/stats helpers used unqualified across the package, plus column names
#' created dynamically inside dplyr/dbplyr data-masking pipelines (these are
#' invisible to static code checks and DuckDB SQL translation handles the
#' h3 functions directly in the database).
#'
#' @importFrom graphics plot.new title
#' @importFrom stats ave coef complete.cases model.matrix plogis reorder setNames vcov
#' @importFrom utils capture.output combn head modifyList tail
#' @importFrom rlang .data
#' @importFrom Rcpp sourceCpp
#' @importFrom brand.yml read_brand_yml
#' @name wise-package-globals
#' @keywords internal
NULL

utils::globalVariables(c(
  ".resid", "Estimate", "Group", "Proportion", "Value", "bin_index",
  "channel", "count", "countryyear", "decile", "economy", "est",
  "estimate", "conf.high", "conf.low", "fname",
  "h3_cell_to_boundary_wkt", "h3_weather", "label", "label_wrap",
  "loc_id", "loc_id_orig", "loc_id_panel", "loc_id_x", "loc_id_y",
  "model", "model_label", "modx", "modx_label", "month", "month_num",
  "n_obs", "name", "overlap_x", "overlap_y", "pct", "period_lbl",
  "plot.new", "pop_2020", "prop", "ref_mean", "ref_sd", "scenario", "se",
  "shared_x", "shared_y", "ssp", "st_geomfromtext",
  "survname", "tau", "timestamp", "title", "total",
  "total_x", "total_y", "value", "value_p50", "variable",
  ":=",
  # Data-masking columns in dplyr/dbplyr/echarts pipelines
  "year", "x", "effect", "welfare", "level_log", "resilience_log", "total_log",
  "Baseline", "Policy", "wave", "hh", "weight", "weight_x", "weight_y",
  "cmip_year", "cmip_month_key", "period_id", "n_rows", "n_complete",
  "n_expected", "is_full", ".var",
  # Names passed unevaluated to .busy_guard() (input id), and a mirai argument
  "run_model", "run_sim", "survey_stats", "weather_stats", "clear_credentials"
))

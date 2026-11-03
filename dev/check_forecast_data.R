# Check a data root's seasonal forecast files against what WISE-APP reads.
#
#   Rscript dev/check_forecast_data.R [code] [data_root]
#
# Defaults: BFA and WISEAPP_DATA_PATH. Read-only. Lists the runs the app accepts, why it skips the
# others, the skill of each target month for every lead, and builds the forecast weather for the
# first accepted run (a 3-month window that its predictor rule allows) to prove the files load.
args <- commandArgs(trailingOnly = TRUE)
code <- if (length(args) >= 1L) args[[1L]] else "BFA"
root <- if (length(args) >= 2L) args[[2L]] else Sys.getenv("WISEAPP_DATA_PATH")
stopifnot(nzchar(root), dir.exists(root))
suppressMessages(pkgload::load_all(".", quiet = TRUE))
cat("Data root:", root, "\n")
cp <- list(type = "local", path = root)
runs <- tryCatch(.forecast_catalogue_runs(cp, code), error = function(e) {
  cat("CATALOGUE ERROR:", conditionMessage(e), "\n")
  NULL
})
skipped <- attr(runs, "skipped")
if (!is.null(skipped) && nrow(skipped)) {
  cat("\nSkipped runs:\n")
  print(skipped, row.names = FALSE)
}
if (!length(runs)) quit(status = 1L)
for (run in runs) {
  cat(sprintf("\nRun %s: init %s, %d members, %d leads, context %d months (%s), adjustment %s, status %s\n",
    run$id, run$init, length(run$members), run$n_leads, run$context_months, run$context_source,
    run$adjustment, run$status))
  skill <- .forecast_skill_table(cp, run)
  if (is.null(skill)) {
    cat("  skill: none published\n")
  } else {
    cat("  skill flags by lead:", paste0(skill$variable, ":", skill$lead_month, "=", skill$skill_flag, collapse = ", "), "\n")
  }
}
run <- runs[[1L]]
months <- .step2_forecast_months(run)
starts <- .step2_forecast_starts(months, 3L)
cat("\nAllowed 3-month starts (default lag):", paste(starts, collapse = ", "), "\n")
cat("Weather build for", run$id, "needs survey inputs; run dev/bench/bench_forecast_weather.R",
  "with WISEAPP_FORECAST_FIXTURE=", root, "to time it.\n")

# Real-data parity check for the batch Step 2 tables (Phase 3).
#
# Runs one BFA spec through the batch pipeline (targets, local data): a linear
# fixest model with a user covariate list, the 1991-2020 historical weather and
# one projection period (SSP3-7.0, 2025-2035), that is `sim: {}`, the app's
# defaults. The same selections go through the app's module servers (Step 1
# and Step 2 in one test server, Step 2 run in the process), and the batch
# tables are compared with what the Results and Diagnostics modules register
# for export: the annual outcomes, the headline cards, the return-period
# thresholds, the distributional incidence and the weather support.
# Needs WISEAPP_DATA_PATH (with the climate projections), targets, arrow and
# yaml. Not part of the test suite: run per release.
#
# Usage: Rscript dev/batch_parity_bfa_sim.R [--batch-only]
#   --batch-only  run the batch side only (to time it and read its peak memory,
#                 for example under `/usr/bin/time -l`)

args <- commandArgs(trailingOnly = TRUE)
batch_only <- "--batch-only" %in% args
suppressMessages({
  pkgload::load_all(".", quiet = TRUE)
  library(shiny)
})
stopifnot(nzchar(Sys.getenv("WISEAPP_DATA_PATH")))
# The app side runs Step 2 in this process instead of on the shared worker.
Sys.setenv(WISEAPP_ASYNC_STEP2 = "0")
covs <- c("hhsize", "electricity", "cellphone")

proj <- file.path(tempdir(), "batch-parity-sim")
dir.create(proj, showWarnings = FALSE)
writeLines(c(
  "seed: 123",
  "outcome: {name: welfare, currency: PPP}",
  "model:",
  sprintf("  covariates: {method: user, vars: [%s]}", paste(covs, collapse = ", ")),
  "sim: {}",
  "profiles:",
  "  weather:",
  "    t_bins_r_12m:",
  "      t: {ref_period: [1, 3], form: binned, n_bins: 5}",
  "      r: {ref_period: [1, 12], form: continuous}",
  "axes:",
  "  country: [BFA]",
  "  weather: [t_bins_r_12m]"
), file.path(proj, "spec.yaml"))
writeLines(c(
  "library(targets)",
  sprintf("suppressMessages(pkgload::load_all(%s, quiet = TRUE))", deparse(normalizePath("."))),
  "tar_option_set(error = \"continue\", memory = \"transient\")",
  "wiseapp::wise_targets(\"spec.yaml\", out_dir = \"results\")"
), file.path(proj, "_targets.R"))
old <- setwd(proj)
t0 <- Sys.time()
targets::tar_make(callr_function = NULL, reporter = "silent")
setwd(old)
cat(sprintf("Batch pipeline: %.0f s\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
out <- file.path(proj, "results")
table <- function(name) dplyr::collect(arrow::open_dataset(file.path(out, "tables", name)))
fail <- arrow::read_parquet(file.path(out, "failures.parquet"))
if (nrow(fail)) print(fail)
stopifnot(nrow(fail) == 0L)
prov <- arrow::read_parquet(file.path(out, "provenance.parquet"))
sim_prov <- prov[prov$stage == "sim", ]
cat(sprintf(
  "Step 2 branch: %.0f s, R heap peak %.0f MB, %d prediction rows per year-set, %d scenario(s), %d failed key(s)\n",
  sim_prov$seconds, sim_prov$r_peak_mb, sim_prov$n_rows, sim_prov$n_scenarios, sim_prov$n_failed_keys
))
annual <- table("annual")
summ <- table("summary")
sw <- table("sim_weather")
cat(
  "Batch tables:", nrow(annual), "annual,", nrow(summ), "summary,", nrow(sw), "sim_weather rows;",
  length(unique(annual$scenario)), "scenarios,", length(unique(annual$member)), "members,",
  length(unique(annual$metric)), "metrics\n"
)
if (batch_only) quit(status = 0L)

# The app side: Step 1 and Step 2 modules on the same selections ----
cp <- build_connection_params("local", path = Sys.getenv("WISEAPP_DATA_PATH"))
md <- load_overview_metadata(cp)
app <- list()
both <- function(input, output, session) {
  s1 <- mod_1_modelling_server(
    "step1",
    connection_params = shiny::reactive(cp), survey_list = shiny::reactive(md$survey_list),
    variable_list = shiny::reactive(md$variable_list), cpi_ppp = shiny::reactive(md$cpi_ppp)
  )
  s2 <- mod_2_simulation_server(
    "step2",
    connection_params = shiny::reactive(cp), selected_outcome = s1$selected_outcome,
    selected_weather = s1$selected_weather, selected_surveys = s1$selected_surveys,
    survey_weather = s1$survey_weather, model_fit = s1$model_fit, stored_breaks = s1$stored_breaks,
    survey_version = s1$survey_version
  )
  list(s1 = s1, s2 = s2)
}
shiny::testServer(both, {
  session$setInputs(
    `step1-sample-unit` = "hh", `step1-sample-economy` = "BFA",
    `step1-sample-year_BFA` = c(2018, 2021),
    `step1-outcome-outcome` = "welfare", `step1-outcome-currency` = "PPP",
    `step1-weather-weather_variable_selector` = c("t", "r"),
    `step1-weather-t_relativePeriod` = c(1, 3), `step1-weather-t_contOrBinned` = "Binned",
    `step1-weather-t_numBins` = 5, `step1-weather-t_binningMethod` = "Equal frequency",
    `step1-weather-r_relativePeriod` = c(1, 12), `step1-weather-r_contOrBinned` = "Continuous",
    `step1-weather-hist_years` = c(1991, 2020)
  )
  session$setInputs(`step1-surveystats-survey_stats` = 0L)
  session$setInputs(`step1-surveystats-survey_stats` = 1L)
  session$flushReact()
  session$setInputs(`step1-weatherstats-weather_stats` = 0L)
  session$setInputs(`step1-weatherstats-weather_stats` = 1L)
  session$flushReact()
  session$setInputs(
    `step1-model-model_type` = "Linear regression", `step1-model-interactions` = character(0),
    `step1-model-fixedeffects` = c("year", "gaul1_code"), `step1-model-covariates` = "User-defined",
    `step1-model-hhcov` = covs
  )
  session$flushReact()
  session$setInputs(`step1-model-run_model` = 0L)
  session$setInputs(`step1-model-run_model` = 1L)
  session$flushReact()
  session$elapse(1000)
  session$flushReact()
  # Step 2 at its initial state: the app defaults, the latest survey wave.
  session$setInputs(
    `step2-weathersim-hist_years` = c(1991, 2020), `step2-weathersim-climate` = "ssp3_7_0",
    `step2-weathersim-fut_period_1` = c(2025, 2035), `step2-weathersim-fut_period_2` = c(2015, 2015),
    `step2-weathersim-fut_period_3` = c(2015, 2015), `step2-weathersim-residuals` = "original",
    `step2-weathersim-include_coef_uncertainty` = TRUE,
    `step2-weathersim-propagate_all_covariate_uncertainty` = FALSE
  )
  session$flushReact()
  session$setInputs(`step2-weathersim-run_sim` = 1L)
  session$flushReact()
  session$elapse(1000)
  session$flushReact()
  api <- s2
  stopifnot(identical(api$run_status(), "success"))
  app$so <<- api$hist_sim()$so
  # The aggregation is deterministic: the batch tables are built by this call.
  agg_1 <- step2_run_aggregates(api$hist_sim(), api$saved_scenarios(), skip_coef = FALSE)
  agg_2 <- step2_run_aggregates(api$hist_sim(), api$saved_scenarios(), skip_coef = FALSE)
  app$deterministic <<- identical(agg_1, agg_2)
  app$annual_core <<- step2_annual_table(agg_1)
  # The Results controls at the state the batch tables assume.
  for (method in c("mean", "headcount_ratio")) {
    session$setInputs(
      `step2-results-cmp_agg_method` = method, `step2-results-cmp_deviation` = "none",
      `step2-results-ensemble_band` = STEP2_SUMMARY_ENSEMBLE_BAND,
      `step2-results-uncertainty_band` = "p10_p90", `step2-results-pov_line` = 3
    )
    session$elapse(500)
    session$flushReact()
    items <- wise_export_items(session)
    app[[method]] <<- list(
      annual = items$climate_annual_distribution_data$fun(),
      headline = items$climate_headline_summary$fun(),
      thresholds = items$climate_outcome_thresholds$fun(),
      incidence = items$climate_distributional_incidence_data$fun()
    )
  }
  app$support <<- list()
  for (v in c("t", "r")) {
    session$setInputs(`step2-diagnostics-diag_weather_vars` = v, `step2-diagnostics-diag_weather_scenario` = "all")
    session$flushReact()
    app$support[[v]] <<- items$simulation_weather_support_summary$fun()
  }
  app$hist_label <<- api$hist_sim()$hist_label
  app$baseline <<- api$hist_sim()$sim_summary$baseline_survey
})
stopifnot(!is.null(app$mean$annual))

all_ok <- TRUE
check <- function(name, ok) {
  cat(sprintf("%-72s %s\n", name, if (isTRUE(ok)) "OK" else "DIFFERS"))
  all_ok <<- isTRUE(ok) && all_ok
}
near <- function(a, b) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-10))

cat("\nBaseline survey:", app$baseline, "| batch:",
  unique(arrow::read_parquet(file.path(out, "runs.parquet"))$sim_baseline_survey), "\n")
check("aggregation is deterministic (two calls identical)", app$deterministic)
check(
  "annual: batch table equals the table built in this session from the app's run (1e-10)",
  near(app$annual_core$value[match(
    paste(annual$scenario, annual$metric, annual$member, annual$sim_year),
    paste(app$annual_core$scenario, app$annual_core$metric, app$annual_core$member, app$annual_core$sim_year)
  )], annual$value)
)
for (method in c("mean", "headcount_ratio")) {
  a <- app[[method]]
  cat(sprintf("\n-- metric: %s --\n", method))

  # annual: one value per scenario, member and year.
  b <- annual[annual$metric == method, ]
  ann <- a$annual
  ann_key <- paste(ann$scenario, ann$model_id, ann$sim_year, sep = "|")
  b_key <- paste(b$scenario, b$member, b$sim_year, sep = "|")
  check("annual: same scenario x member x year rows", setequal(ann_key, b_key) && !anyDuplicated(b_key))
  m <- match(ann_key, b_key)
  # The Results pane aggregates a metric together with the metrics of its group
  # (line-free or line-dependent); the batch computes all of them in one call,
  # as the run's streamed tables do. The summation order can move the last
  # digits (about 1e-15).
  check("annual: value equal (1e-10)", near(ann$value, b$value[m]))
  cat(sprintf(
    "  max |diff| value: %.1e (identical: %s)\n", max(abs(ann$value - b$value[m])),
    identical(as.numeric(ann$value), b$value[m])
  ))

  # headline cards.
  hs <- summ[summ$metric == method & summ$section == "headline", ]
  hl <- a$headline
  pick <- function(group, measure) hs$estimate[hs$group == group & hs$measure == measure]
  for (card in unique(hl$Metric)) {
    row <- hl[hl$Metric == card, ]
    if (is.finite(row$Historical_native) && card != "Simulation years") {
      check(sprintf("headline '%s': historical", card), near(pick("historical", card), row$Historical_native))
    }
    if (is.finite(row$Focus_native)) {
      check(sprintf("headline '%s': focus", card), near(pick("focus", card), row$Focus_native))
    }
    if (is.finite(row$Difference_native)) {
      check(sprintf("headline '%s': difference", card), near(pick("difference", card), row$Difference_native))
    }
    if (is.finite(row$Range_lower_native)) {
      rr <- hs[hs$group == "range" & hs$measure == card, ]
      check(sprintf("headline '%s': range", card), near(rr$lo, row$Range_lower_native) && near(rr$hi, row$Range_upper_native))
    }
  }
  check(
    "headline: card text equals the stored text",
    identical(hs$text[hs$group == "focus"], hl$Value[is.finite(hl$Focus_native)])
  )

  # return-period thresholds.
  th <- a$thresholds
  rp_map <- metric_decision_return_periods(method, app$so)
  rp_cols <- setdiff(names(th), c("Scenario / Period", "Estimate"))
  ay <- summ[summ$metric == method & summ$section == "adverse_year", ]
  ok <- TRUE
  for (i in seq_len(nrow(th))) {
    for (col in rp_cols) {
      v <- th[[col]][[i]]
      if (!is.finite(v)) next
      rp <- unname(rp_map[sub("^Adverse 1 in ", "Adverse 1-in-", col)])
      est <- th$Estimate[[i]]
      scen <- th[["Scenario / Period"]][[i]]
      d <- ay[ay$scenario == scen & ay$return_period == rp, ]
      want <- if (est %in% c("Single historical estimate", "Equal-model mean")) {
        d$estimate[d$group == "coefficient"]
      } else {
        grp <- c(Coef = "coefficient", Ensemble = "ensemble", Pooled = "pooled")[[sub(" .*", "", est)]]
        side <- if (as.integer(sub(".*P", "", est)) < 50) "lo" else "hi"
        d[[side]][d$group == grp]
      }
      ok <- ok && length(want) == 1L && near(want, v)
    }
  }
  check("thresholds: every stored value equals the Results table", ok)

  # distributional incidence (metric independent, checked once).
  if (identical(method, "mean")) {
    inc <- a$incidence
    bi <- summ[summ$section == "incidence", ]
    key_a <- paste(inc$scenario, paste0("decile_", inc$decile), sep = "|")
    key_b <- paste(bi$scenario, bi$group, sep = "|")
    check("incidence: same scenario x decile rows", setequal(key_a, key_b))
    check("incidence: effect equal (1e-10)", near(inc$effect, bi$estimate[match(key_a, key_b)]))
    cat(sprintf(
      "  max |diff| effect: %.1e\n", max(abs(inc$effect - bi$estimate[match(key_a, key_b)]))
    ))
  }
}

# weather support: the share outside the historical support, per variable.
for (v in names(app$support)) {
  d <- app$support[[v]]
  s <- sw[sw$section == "support" & sw$variable == v, ]
  ok <- TRUE
  for (i in seq_len(nrow(d))) {
    scen <- d$`Scenario / period`[[i]]
    n <- s$value[s$scenario == scen & s$statistic == "n_scenario"]
    o <- s$value[s$scenario == scen & s$statistic == "outside_n"]
    sh <- s$value[s$scenario == scen & s$statistic == "outside_share"]
    ok <- ok && near(d$`Scenario values`[[i]], n) &&
      identical(d$`Outside interval`[[i]], paste0(o, " (", round(100 * sh, 1), "%)"))
  }
  check(sprintf("sim_weather: support of '%s' equals the Diagnostics table", v), ok && nrow(d) > 0L)
}
check(
  "sim_weather: members listed for every scenario",
  all(vapply(unique(annual$scenario[annual$scenario != "Historical"]), function(s) {
    any(sw$section == "members" & sw$scenario == s)
  }, logical(1)))
)
cat(if (all_ok) "\nAll checks passed.\n" else "\nSome checks differ.\n")
quit(status = if (all_ok) 0L else 1L)

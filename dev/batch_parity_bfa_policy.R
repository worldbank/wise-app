# Real-data parity check for the batch Step 3 tables (Phase 4).
#
# Runs one BFA spec through the batch pipeline (targets, local data): a linear
# fixest model with a user covariate list, the app's Step 2 defaults, a regular
# cash transfer (poorest 30 percent) and a shock-responsive transfer on a
# return-period trigger of the continuous temperature. The same selections go
# through the app's module servers (Steps 1 to 3 in one test server, both
# steps run in the process), and the batch tables are compared with what the
# Step 3 modules register for export: the paired effects, the adverse-year
# table, the annual effects, the headline cards, the distributional incidence,
# the cost-effectiveness and the shock summary.
# Needs WISEAPP_DATA_PATH (with the climate projections), targets, arrow and
# yaml. Not part of the test suite: run per release.
#
# Usage: Rscript dev/batch_parity_bfa_policy.R [--batch-only] [--fixture]
#   --batch-only  run the batch side only (to time it and read its peak memory,
#                 for example under `/usr/bin/time -l`)
#   --fixture     run on the small data folder of the tests (country TST)
#                 instead of BFA, to check the script itself

args <- commandArgs(trailingOnly = TRUE)
batch_only <- "--batch-only" %in% args
use_fixture <- "--fixture" %in% args
suppressMessages({
  pkgload::load_all(".", quiet = TRUE)
  library(shiny)
})
# The app side runs Steps 2 and 3 in this process instead of on the shared worker.
Sys.setenv(WISEAPP_ASYNC_STEP2 = "0", WISEAPP_ASYNC_STEP3 = "0")

# The settings under test ----
cfg <- if (use_fixture) {
  suppressMessages(library(testthat))
  source("tests/testthat/helper-batch-fixture.R", local = TRUE)
  data_dir <- file.path(tempdir(), "parity-data")
  dir.create(data_dir, showWarnings = FALSE)
  batch_fixture_tree(data_dir, projections = TRUE)
  Sys.setenv(WISEAPP_DATA_PATH = data_dir)
  list(
    economy = "TST", years = c(2018, 2019), covs = c("hhsize", "urban", "electricity"),
    fe = "year", weather = c("tx"), hist = c(2017, 2019), sim_hist = c(2018, 2019),
    future = c(2025, 2030), trigger = "tx",
    weather_yaml = "      tx: {ref_period: [1, 3], form: continuous}",
    weather_inputs = list(
      `step1-weather-weather_variable_selector` = "tx",
      `step1-weather-tx_relativePeriod` = c(1, 3), `step1-weather-tx_contOrBinned` = "Continuous",
      `step1-weather-hist_years` = c(2017, 2019)
    ),
    shock_extra = "trigger_type: weather, trigger_value: 29.5"
  )
} else {
  list(
    economy = "BFA", years = c(2018, 2021), covs = c("hhsize", "electricity", "cellphone"),
    fe = c("year", "gaul1_code"), weather = c("t", "r"), hist = c(1991, 2020),
    sim_hist = c(1991, 2020), future = c(2025, 2035), trigger = "t_cont",
    weather_yaml = c(
      "      t: {ref_period: [1, 3], form: binned, n_bins: 5}",
      "      r: {ref_period: [1, 12], form: continuous}"
    ),
    weather_inputs = list(
      `step1-weather-weather_variable_selector` = c("t", "r"),
      `step1-weather-t_relativePeriod` = c(1, 3), `step1-weather-t_contOrBinned` = "Binned",
      `step1-weather-t_numBins` = 5, `step1-weather-t_binningMethod` = "Equal frequency",
      `step1-weather-r_relativePeriod` = c(1, 12), `step1-weather-r_contOrBinned` = "Continuous",
      `step1-weather-hist_years` = c(1991, 2020)
    ),
    shock_extra = "trigger_type: return_period, trigger_return_period_years: 5"
  )
}
stopifnot(nzchar(Sys.getenv("WISEAPP_DATA_PATH")))
cash <- list(
  transfer_amount_usd = 60, targeting = "exante_poor", targeting_threshold_pct = 30,
  admin_cost_pct = 5
)
shock <- c(cash, list(sp_type = "shock", trigger_variable = cfg$trigger))
shock_trigger <- if (use_fixture) {
  list(trigger_type = "weather", trigger_value = 29.5)
} else {
  list(trigger_type = "return_period", trigger_return_period_years = 5)
}
shock <- c(shock, shock_trigger)
yaml_sp <- function(x) {
  paste0("{sp: {", paste(names(x), vapply(x, function(v) as.character(v), ""), sep = ": ", collapse = ", "), "}}")
}

proj <- file.path(tempdir(), "batch-parity-policy")
dir.create(proj, showWarnings = FALSE)
writeLines(c(
  "seed: 123",
  sprintf("outcome: {name: welfare, currency: PPP}"),
  "model:",
  sprintf("  covariates: {method: user, vars: [%s]}", paste(cfg$covs, collapse = ", ")),
  "sim:",
  sprintf("  hist_years: [%d, %d]", cfg$sim_hist[1], cfg$sim_hist[2]),
  sprintf("  future_periods: [[%d, %d]]", cfg$future[1], cfg$future[2]),
  "  ssps: [ssp3_7_0]",
  "profiles:",
  "  weather:",
  "    parity:",
  cfg$weather_yaml,
  "  policy:",
  paste0("    cash: ", yaml_sp(cash)),
  paste0("    shock: ", yaml_sp(shock)),
  "axes:",
  sprintf("  country: [%s]", cfg$economy),
  "  weather: [parity]",
  "  policy: [cash, shock]"
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
for (i in which(prov$stage %in% c("sim", "policy"))) {
  cat(sprintf(
    "%s branch: %.0f s, R heap peak %.0f MB, %d failed key(s)\n",
    prov$stage[i], prov$seconds[i], prov$r_peak_mb[i], prov$n_failed_keys[i]
  ))
}
annual <- table("annual")
summ <- table("summary")
dec <- table("decomposition")
meas <- table("policy_measures")
runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
pid <- function(label) runs$policy_id[runs$axis_policy == label]
cat(
  "Batch tables:", nrow(annual), "annual,", nrow(summ), "summary,", nrow(dec), "decomposition,",
  nrow(meas), "policy_measures rows\n"
)
if (batch_only) quit(status = 0L)

# The app side: Steps 1 to 3 on the same selections ----
cp <- build_connection_params("local", path = Sys.getenv("WISEAPP_DATA_PATH"))
md <- load_overview_metadata(cp)
all_steps <- function(input, output, session) {
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
  s3 <- mod_3_scenario_server(
    "step3",
    selected_outcome = s1$selected_outcome, selected_weather = s1$selected_weather,
    selected_model = s1$selected_model, selected_policies = s1$selected_policies,
    survey_weather = s1$survey_weather, survey_data = s1$survey_data, model_fit = s1$model_fit,
    hist_sim = s2$hist_sim, saved_scenarios = s2$saved_scenarios, selected_hist = s2$selected_hist,
    variable_list = shiny::reactive(md$variable_list), analysis_unit = s1$analysis_unit,
    skip_coef_draws = s2$skip_coef_draws, residuals = s2$residuals,
    propagate_all_covariate_uncertainty = s2$propagate_all_covariate_uncertainty,
    survey_version = s1$survey_version, sim_stale = s2$stale
  )
  list(s1 = s1, s2 = s2, s3 = s3)
}
app <- list()
sp_inputs <- function(values) {
  all <- utils::modifyList(wise_default_policy()$sp, values)
  stats::setNames(all, paste0("step3-sp-", names(all)))
}
shiny::testServer(all_steps, {
  do.call(session$setInputs, c(
    list(
      `step1-sample-unit` = "hh", `step1-sample-economy` = cfg$economy,
      `step1-outcome-outcome` = "welfare", `step1-outcome-currency` = "PPP"
    ),
    stats::setNames(list(cfg$years), paste0("step1-sample-year_", cfg$economy)),
    cfg$weather_inputs
  ))
  session$setInputs(`step1-surveystats-survey_stats` = 0L)
  session$setInputs(`step1-surveystats-survey_stats` = 1L)
  session$flushReact()
  session$setInputs(`step1-weatherstats-weather_stats` = 0L)
  session$setInputs(`step1-weatherstats-weather_stats` = 1L)
  session$flushReact()
  session$setInputs(
    `step1-model-model_type` = "Linear regression", `step1-model-interactions` = character(0),
    `step1-model-fixedeffects` = cfg$fe, `step1-model-covariates` = "User-defined",
    `step1-model-hhcov` = cfg$covs
  )
  session$flushReact()
  session$setInputs(`step1-model-run_model` = 0L)
  session$setInputs(`step1-model-run_model` = 1L)
  session$flushReact()
  session$elapse(1000)
  session$flushReact()
  session$setInputs(
    `step2-weathersim-hist_years` = cfg$sim_hist, `step2-weathersim-climate` = "ssp3_7_0",
    `step2-weathersim-fut_period_1` = cfg$future, `step2-weathersim-fut_period_2` = c(2015, 2015),
    `step2-weathersim-fut_period_3` = c(2015, 2015), `step2-weathersim-residuals` = "original",
    `step2-weathersim-include_coef_uncertainty` = TRUE,
    `step2-weathersim-propagate_all_covariate_uncertainty` = FALSE
  )
  session$flushReact()
  session$setInputs(`step2-weathersim-run_sim` = 1L)
  session$flushReact()
  session$elapse(1000)
  session$flushReact()
  stopifnot(identical(s2$run_status(), "success"))

  results <- list()
  for (label in c("cash", "shock")) {
    values <- if (identical(label, "cash")) cash else shock
    do.call(session$setInputs, sp_inputs(values))
    session$flushReact()
    session$setInputs(`step3-run_policy_sim` = 0L)
    session$setInputs(`step3-run_policy_sim` = if (identical(label, "cash")) 1L else 2L)
    session$flushReact()
    session$elapse(1000)
    session$flushReact()
    stopifnot(identical(s3$run_status(), "success"))
    for (method in c("mean", "headcount_ratio")) {
      session$setInputs(
        `step3-results3-cmp_agg_method` = method, `step3-results3-cmp_deviation` = "none",
        `step3-results3-ensemble_band` = STEP3_SUMMARY_ENSEMBLE_BAND,
        `step3-results3-uncertainty_band` = "p10_p90", `step3-results3-cmp_pov_line` = 3
      )
      session$elapse(500)
      session$flushReact()
      items <- wise_export_items(session)
      grab <- function(key) tryCatch(items[[key]]$fun(), error = function(e) NULL)
      results[[paste(label, method)]] <- list(
        paired = grab("policy_paired_effect_summary"), annual = grab("policy_annual_effect_data"),
        adverse = grab("policy_adverse_effect_table"), headline = grab("policy_headline_summary"),
        incidence = grab("policy_distributional_incidence_data"),
        ce = grab("policy_cost_effectiveness"), shock = grab("policy_shock_summary"),
        shock_annual = grab("policy_shock_annual")
      )
    }
  }
  app <<- results
})
stopifnot(length(app) == 4L)

all_ok <- TRUE
check <- function(name, ok) {
  cat(sprintf("%-84s %s\n", name, if (isTRUE(ok)) "OK" else "DIFFERS"))
  all_ok <<- isTRUE(ok) && all_ok
}
near <- function(a, b) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = 1e-10))
plain <- function(x) ifelse(grepl("^Historical", x), "Historical", x)

for (label in c("cash", "shock")) {
  id <- pid(label)
  for (method in c("mean", "headcount_ratio")) {
    a <- app[[paste(label, method)]]
    cat(sprintf("\n-- policy: %s, metric: %s --\n", label, method))
    s <- summ[summ$policy_id %in% id & summ$metric %in% method, ]

    # Expected effect per scenario.
    p <- a$paired
    e <- s[s$section == "policy_expected" & s$measure == "effect" & s$group == "intermodel", ]
    m <- match(plain(p$scenario), e$scenario)
    check("paired effect: every scenario stored", !anyNA(m))
    check("paired effect: value, band (1e-10)", near(p$value, e$estimate[m]) &&
      near(p$intermod_lo, e$lo[m]) && near(p$intermod_hi, e$hi[m]))

    # Annual paired effects: policy value minus baseline value, per member and year.
    ae <- a$annual
    b <- annual[annual$metric == method & is.na(annual$policy_id), ]
    po <- annual[annual$metric == method & annual$policy_id %in% id, ]
    key <- function(d, scenario, member, year) paste(plain(d[[scenario]]), d[[member]], d[[year]])
    mine <- po$value[match(key(ae, "scenario", "model_id", "sim_year"), key(po, "scenario", "member", "sim_year"))] -
      b$value[match(key(ae, "scenario", "model_id", "sim_year"), key(b, "scenario", "member", "sim_year"))]
    check("annual effects: policy minus baseline equals the paired effect (1e-10)", near(ae$value, mine))

    # Adverse years.
    ad <- a$adverse
    ad <- ad[ad$period != "Expected", ]
    sa <- s[s$section == "policy_adverse" & s$group == "effect", ]
    ok <- TRUE
    for (i in seq_len(nrow(ad))) {
      r <- sa[sa$scenario == plain(ad$scenario[[i]]) & sa$measure == ad$period[[i]], ]
      ok <- ok && length(r$estimate) == 1L && (near(r$estimate, ad$effect[[i]]) || (is.na(r$estimate) && is.na(ad$effect[[i]])))
    }
    check("adverse years: every effect stored", ok && nrow(ad) > 0L)

    # Headline cards.
    hl <- a$headline
    sh <- s[s$section == "policy_headline" & grepl("_value$", s$group), ]
    check("headline: card values equal the stored text", identical(sh$text, hl$value))

    if (identical(method, "mean")) {
      inc <- a$incidence
      bi <- summ[summ$policy_id %in% id & summ$section == "policy_incidence", ]
      ka <- paste(plain(inc$scenario), inc$basis, paste0("decile_", inc$decile))
      kb <- paste(bi$scenario, bi$return_period, bi$group)
      check("incidence: same rows and effects (1e-10)", setequal(ka, kb) && near(inc$effect, bi$estimate[match(ka, kb)]))
    }
    if (!is.null(a$ce)) {
      ce <- a$ce
      bc <- meas[meas$policy_id %in% id & meas$section == "cost_effectiveness" & meas$metric %in% method &
        meas$measure == "cost", ]
      kce <- paste(plain(ce$scenario), ce$basis, ce$measure)
      kbc <- paste(bc$scenario, sub(" / .*$", "", bc$group), sub("^.* / ", "", bc$group))
      check("cost-effectiveness: annual cost per scenario and basis (1e-10)", near(ce$cost, bc$value[match(kce, kbc)]))
    }
  }
  if (identical(label, "shock")) {
    sk <- app[["shock mean"]]$shock
    bs <- meas[meas$policy_id %in% id & meas$section == "shock_summary", ]
    ok <- TRUE
    for (f in c("activation_freq", "mean_total_cost", "false_positive_rate", "leakage_share")) {
      v <- bs$value[bs$measure == f][match(plain(sk$scenario), bs$scenario[bs$measure == f])]
      ok <- ok && near(sk[[f]], v)
    }
    check("shock summary: activation, cost, basis risk and leakage (1e-10)", ok)
    sa <- app[["shock mean"]]$shock_annual
    bsa <- annual[annual$policy_id %in% id & annual$metric == "shock_total_cost", ]
    k1 <- paste(plain(sa$scenario), sa$member, sa$sim_year)
    k2 <- paste(bsa$scenario, bsa$member, bsa$sim_year)
    check("shock rows: annual total cost per member and year (1e-10)", near(sa$total_cost, bsa$value[match(k1, k2)]))
  }
}
cat(if (all_ok) "\nAll checks passed.\n" else "\nSome checks differ.\n")
quit(status = if (all_ok) 0L else 1L)

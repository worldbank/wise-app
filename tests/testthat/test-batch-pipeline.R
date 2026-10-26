# End-to-end smoke test of the batch runner on the fixture data folder:
# the grid becomes runs, the targets pipeline writes the parquet store, shared
# work is reused, and a failing data set is recorded without stopping the rest.

skip_if_not_installed("targets")
skip_if_not_installed("arrow")
skip_if_not_installed("yaml")

write_project <- function(dir, grid_lines, keep = TRUE) {
  writeLines(grid_lines, file.path(dir, "spec.yaml"))
  writeLines(c(
    "library(targets)",
    "tar_option_set(error = \"continue\", memory = \"transient\")",
    paste0("wiseapp::wise_targets(\"spec.yaml\", out_dir = \"results\", keep_step2 = ", keep, ")")
  ), file.path(dir, "_targets.R"))
}

make_it <- function(dir) {
  withr::with_dir(dir, targets::tar_make(callr_function = NULL, reporter = "silent"))
}

# Branch counts per dynamic target after the last run.
progress <- function(dir) {
  p <- withr::with_dir(dir, targets::tar_progress_branches())
  p <- as.data.frame(p[p$name %in% c("data_frames", "data_tables", "weather_tables"), ])
  rownames(p) <- p$name
  p
}

grid_yaml <- c(
  "seed: 7",
  "weather:",
  "  hist_years: [2017, 2019]",
  "profiles:",
  "  weather:",
  "    tx_3m: {tx: {ref_period: [1, 3], form: continuous}}",
  "    tx_bins: {tx: {ref_period: [1, 1], form: binned, n_bins: 4}}",
  "axes:",
  "  country: [TST]",
  "  weather: [tx_3m, tx_bins]"
)

test_that("the pipeline writes the store, reuses shared work and records failures", {
  data <- withr::local_tempdir()
  batch_fixture_tree(data)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, grid_yaml)

  # The grid resolves against the data and shares one data set.
  g <- wise_spec_expand(file.path(proj, "spec.yaml"))
  expect_true(all(g$resolved))
  expect_identical(nrow(g), 2L)
  expect_identical(length(unique(g$data_id)), 1L)

  make_it(proj)
  out <- file.path(proj, "results")
  expect_true(all(file.exists(file.path(
    out, c("runs.parquet", "provenance.parquet", "failures.parquet", "manifest.json")
  ))))

  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_setequal(runs$run_id, g$run_id)
  expect_true(all(c(
    "run_id", "axis_country", "axis_weather", "data_id", "wxvar_ids", "seed", "spec_json"
  ) %in% names(runs)))
  expect_setequal(runs$axis_weather, c("tx_3m", "tx_bins"))
  expect_identical(runs$seed, c(7L, 7L))
  for (id in runs$run_id) {
    spec <- wise_spec_read(file.path(out, "specs", paste0(id, ".json")))
    expect_identical(spec, g$spec[[match(id, g$run_id)]])
  }

  # Table schemas.
  vs <- arrow::open_dataset(file.path(out, "tables", "variable_stats")) |> dplyr::collect()
  expect_identical(
    names(vs)[names(vs) != "code"],
    c(
      "data_id", "wave", "year", "survname", "var_group", "variable", "sample", "n", "n_rows",
      "n_missing", "pct_missing", "n_unique", "mean", "unweighted_mean", "sd", "min", "max",
      paste0("p", seq(10, 90, 10)), "p25", "p75", "share_one", "gini"
    )
  )
  expect_setequal(unique(vs$data_id), g$data_id)
  expect_setequal(unique(vs$sample), c("all", "with_loc", "without_loc", "within_loc"))
  expect_true(all(c("outcome", "hh", "indicator", "policy") %in% vs$var_group))
  expect_type(vs$mean, "double")
  expect_type(vs$n, "integer")

  idt <- arrow::open_dataset(file.path(out, "tables", "interview_dates")) |> dplyr::collect()
  expect_identical(
    names(idt)[names(idt) != "code"],
    c(
      "data_id", "wave", "year", "survname", "month", "n", "n_dates", "first_date", "last_date",
      "n_locations", "avg_dates_per_loc"
    )
  )
  expect_s3_class(idt$first_date, "Date")
  expect_identical(sum(is.na(idt$month)), 2L)

  wx <- arrow::open_dataset(file.path(out, "tables", "weather_stats")) |> dplyr::collect()
  expect_identical(
    names(wx)[names(wx) != "code"],
    c(
      "wxvar_id", "wave", "year", "survname", "variable", "source", "sample", "n", "pct_missing",
      "n_unique", "n_unique_per_loc", "unweighted_mean", "mean", "sd", "min", "max",
      paste0("p", seq(10, 90, 10)), "p25", "p75"
    )
  )
  ids <- unlist(g$wxvar_ids)
  expect_setequal(unique(wx$wxvar_id), unname(ids))
  expect_setequal(unique(wx$source), c("survey", "historical"))
  expect_identical(unique(wx$variable), "tx")

  # The stored numbers are the ones the core functions give.
  md <- load_overview_metadata(build_connection_params("local", path = data))
  cp <- build_connection_params("local", path = data)
  ss <- wise_select_surveys(md$survey_list, "hh", cp)
  df <- prepare_survey_data(load_survey_frame(ss, cp), md$variable_list, md$cpi_ppp)
  oc <- wise_selected_outcome(md$variable_list, df, "welfare", "PPP")
  direct <- variable_stats_table(
    wise_outcome_data(df, oc$info, oc$so), md$variable_list, "welfare",
    wise_default_indicators(), TRUE
  )
  mine <- vs[vs$variable == "welfare" & vs$sample == "all" & vs$wave == "2018", ]
  expect_identical(mine$mean, direct$mean[direct$variable == "welfare" & direct$sample == "all" &
    direct$wave == "2018"])

  # Manifest and failures.
  manifest <- jsonlite::read_json(file.path(out, "manifest.json"))
  expect_identical(manifest$schema_version, WISEAPP_BATCH_SCHEMA_VERSION)
  expect_identical(manifest$n_runs, 2L)
  expect_setequal(unlist(manifest$tables), c("variable_stats", "interview_dates", "weather_stats"))
  expect_identical(manifest$data_source$type, "local")
  expect_true(length(manifest$data_files) > 0L)
  expect_match(manifest$data_files[[1]]$sha256, "^[0-9a-f]{64}$")
  expect_false(grepl(data, paste(readLines(file.path(out, "manifest.json")), collapse = ""), fixed = TRUE))
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  prov <- arrow::read_parquet(file.path(out, "provenance.parquet"))
  expect_setequal(prov$stage, c("data", "weather"))

  # A second run recomputes nothing.
  make_it(proj)
  p <- progress(proj)
  expect_identical(p$skipped, p$branches)
  expect_identical(sum(p$completed), 0L)

  # A new weather profile adds one branch; the data and the old branches are reused.
  write_project(proj, c(
    grid_yaml[1:7], "    tx_6m: {tx: {ref_period: [1, 6], form: continuous}}", grid_yaml[8:9],
    "  weather: [tx_3m, tx_bins, tx_6m]"
  ))
  make_it(proj)
  p <- progress(proj)
  expect_identical(p["weather_tables", "branches"], 3L)
  expect_identical(p["weather_tables", "completed"], 1L)
  expect_identical(p["weather_tables", "skipped"], 2L)
  expect_identical(p["data_frames", "skipped"], 1L)
  expect_identical(p["data_tables", "skipped"], 1L)
  expect_identical(nrow(arrow::read_parquet(file.path(out, "runs.parquet"))), 3L)
})

test_that("a data set that fails is recorded and the others still run", {
  data <- withr::local_tempdir()
  batch_fixture_tree(data)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, c(
    "weather:", "  hist_years: [2017, 2019]",
    "axes:", "  outcome: [welfare, no_such_outcome]"
  ))
  make_it(proj)
  out <- file.path(proj, "results")
  f <- arrow::read_parquet(file.path(out, "failures.parquet"))
  expect_identical(nrow(f), 1L)
  expect_identical(f$stage, "data")
  expect_identical(f$n_runs, 1L)
  expect_match(f$message, "no_such_outcome")
  expect_false(grepl(data, f$message, fixed = TRUE))
  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_identical(nrow(runs), 2L)
  expect_identical(f$run_ids, runs$run_id[runs$axis_outcome == "no_such_outcome"])
  vs <- arrow::open_dataset(file.path(out, "tables", "variable_stats")) |> dplyr::collect()
  expect_identical(length(unique(vs$data_id)), 1L)
  expect_identical(unique(vs$data_id), runs$data_id[runs$axis_outcome == "welfare"])
})

test_that("the project template is complete and consistent", {
  src <- system.file("batch", package = "wiseapp")
  skip_if(!nzchar(src), "template not available")
  expect_true(all(c("_targets.R", "spec.yaml", "run.R", "README.md") %in% list.files(src, all.files = TRUE)))
  for (f in c("_targets.R", "run.R")) expect_no_error(parse(file.path(src, f), keep.source = FALSE))
  dest <- file.path(withr::local_tempdir(), "study")
  wise_batch_template(dest)
  expect_true(file.exists(file.path(dest, "_targets.R")))
  expect_error(wise_batch_template(dest), "not empty")
  # The template grid expands against fixture metadata.
  g <- wise_spec_expand(
    file.path(dest, "spec.yaml"), connection_params = list(type = "hf"),
    metadata = list(
      survey_list = batch_fixture_survey_list(codes = "BFA"),
      variable_list = batch_fixture_variable_list()
    ),
    survey_columns = c("welfare", "hhsize")
  )
  expect_identical(nrow(g), 2L)
  # The template names only exported functions.
  txt <- paste(readLines(file.path(dest, "_targets.R")), collapse = "\n")
  called <- regmatches(txt, gregexpr("wiseapp::[A-Za-z_.]+", txt))[[1]]
  expect_true(all(sub("wiseapp::", "", called) %in% getNamespaceExports("wiseapp")))
})

# Step 1 models ----

model_grid <- c(
  "seed: 7",
  "weather:",
  "  hist_years: [2017, 2019]",
  "model: {}",
  "profiles:",
  "  weather:",
  "    tx_3m: {tx: {ref_period: [1, 3], form: continuous}}",
  "  covariates:",
  "    none: {method: user}",
  "    hh: {method: user, vars: [hhsize, urban]}",
  "axes:",
  "  country: [TST]",
  "  weather: [tx_3m]",
  "  covariates: [none, hh]"
)

fit_progress <- function(dir) {
  p <- withr::with_dir(dir, targets::tar_progress_branches())
  p <- as.data.frame(p[p$name %in% c("data_frames", "wx_frames", "fit_tables"), ])
  rownames(p) <- p$name
  p
}

test_that("model fits run per fit_id, write the three model tables and are reused", {
  data <- withr::local_tempdir()
  batch_fixture_tree(data)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, model_grid)

  g <- wise_spec_expand(file.path(proj, "spec.yaml"))
  expect_identical(nrow(g), 2L)
  expect_identical(length(unique(g$fit_id)), 2L)
  expect_identical(length(unique(g$weather_id)), 1L)
  expect_identical(g$spec[[1]]$outcome$name, "welfare")
  expect_identical(g$spec[[1]]$model$type, "Linear regression")

  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  p <- fit_progress(proj)
  expect_identical(p["wx_frames", "branches"], 1L)
  expect_identical(p["fit_tables", "branches"], 2L)

  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_setequal(runs$fit_id, g$fit_id)
  expect_true(all(c("weather_id", "fit_id", "model_type", "covariate_method") %in% names(runs)))

  terms <- arrow::open_dataset(file.path(out, "tables", "model_terms")) |> dplyr::collect()
  expect_identical(
    names(terms)[names(terms) != "code"],
    c(
      "fit_id", "model", "term", "tau", "is_weather", "estimate", "std_error", "statistic",
      "p_value", "conf_low", "conf_high", "n_obs", "importance_share", "lasso_freq", "translation"
    )
  )
  expect_setequal(unique(terms$fit_id), g$fit_id)
  expect_identical(unique(terms$code), "TST")
  fit <- arrow::open_dataset(file.path(out, "tables", "model_fit")) |> dplyr::collect()
  expect_identical(
    names(fit)[names(fit) != "code"],
    c("fit_id", "section", "variable", "model", "tau", "statistic", "value", "text", "detail")
  )
  vc <- arrow::open_dataset(file.path(out, "tables", "model_vcov")) |> dplyr::collect()
  expect_identical(
    names(vc)[names(vc) != "code"], c("fit_id", "tau", "term_1", "term_2", "covariance")
  )
  # The location panel was joined, so the standard errors are clustered.
  expect_true(all(fit$text[fit$statistic == "location_panel"] == "joined"))
  expect_true(all(fit$text[fit$statistic == "vcov"] == "clustered: loc_id_panel"))
  prov <- arrow::read_parquet(file.path(out, "provenance.parquet"))
  expect_setequal(prov$stage, c("data", "weather", "fit"))
  expect_identical(prov$location_panel[prov$stage == "data"], "joined")
  manifest <- jsonlite::read_json(file.path(out, "manifest.json"))
  expect_true(all(c("model_terms", "model_fit", "model_vcov") %in% unlist(manifest$tables)))

  # The stored numbers are the ones the core gives for the same spec.
  cp <- build_connection_params("local", path = data)
  md <- load_overview_metadata(cp)
  spec <- g$spec[[which(g$covariates == "hh")]]
  ss <- wise_select_surveys(md$survey_list, "hh", cp)
  df <- prepare_survey_data(load_survey_frame(ss, cp), md$variable_list, md$cpi_ppp)
  df <- wise_join_location_panel(df, wise_load_location_panel(ss, cp))
  so <- wise_selected_outcome(md$variable_list, df, "welfare", "PPP")$so
  sw <- wise_selected_weather(spec$weather, md$variable_list)
  w <- wise_load_weather(
    df, ss, sw, stats::setNames(spec$weather$hist_years, c("from", "to")), cp, spec$seed
  )
  m <- wise_model_from_spec(spec$model, "hh", w$survey_weather, so, sw, md$variable_list, spec$seed)
  mf <- wise_fit(w$survey_weather, w$stored_breaks, so, sw, m$selected_model, md$variable_list, spec$seed)
  direct <- step1_model_tables(mf)
  mine <- terms[terms$fit_id == g$fit_id[g$covariates == "hh"], ]
  expect_identical(mine$term, direct$model_terms$term)
  expect_identical(mine$estimate, direct$model_terms$estimate)
  expect_identical(mine$std_error, direct$model_terms$std_error)
  expect_true(all(c("hhsize", "urban") %in% mine$term[mine$model == 3L]))
  expect_false("hhsize" %in% terms$term[terms$fit_id == g$fit_id[g$covariates == "none"]])

  # A second run recomputes nothing.
  make_it(proj)
  p <- fit_progress(proj)
  expect_identical(p$skipped, p$branches)

  # A new model profile adds one fit; data and the weather frame are reused.
  write_project(proj, c(
    model_grid[1:8],
    "    lasso: {method: lasso, lasso: {lambda: lambda.min, stability_threshold: 0.1}}",
    model_grid[9:13],
    "  covariates: [none, hh, lasso]"
  ))
  make_it(proj)
  p <- fit_progress(proj)
  expect_identical(p["fit_tables", "branches"], 3L)
  expect_identical(p["fit_tables", "completed"], 1L)
  expect_identical(p["fit_tables", "skipped"], 2L)
  expect_identical(p["wx_frames", "skipped"], 1L)
  expect_identical(p["data_frames", "skipped"], 1L)
  # The Lasso fit records the selection frequency of its covariates.
  terms <- arrow::open_dataset(file.path(out, "tables", "model_terms")) |> dplyr::collect()
  expect_identical(length(unique(terms$fit_id)), 3L)
  lasso_id <- setdiff(unique(terms$fit_id), g$fit_id)
  expect_identical(length(lasso_id), 1L)
  freq <- terms$lasso_freq[terms$fit_id == lasso_id]
  expect_true(any(!is.na(freq)))
  expect_true(all(freq[!is.na(freq)] >= 0.1 & freq[!is.na(freq)] <= 1))
})

test_that("a fit that cannot run is recorded and the other fits still run", {
  data <- withr::local_tempdir()
  batch_fixture_tree(data)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, c(
    model_grid[1:8], "    bad: {method: user, vars: [no_such_variable]}", model_grid[9:13],
    "  covariates: [hh, bad]"
  ))
  make_it(proj)
  out <- file.path(proj, "results")
  f <- arrow::read_parquet(file.path(out, "failures.parquet"))
  expect_identical(nrow(f), 1L)
  expect_identical(f$stage, "fit")
  expect_match(f$message, "no_such_variable")
  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_identical(f$run_ids, runs$run_id[runs$axis_covariates == "bad"])
  terms <- arrow::open_dataset(file.path(out, "tables", "model_terms")) |> dplyr::collect()
  expect_identical(unique(terms$fit_id), runs$fit_id[runs$axis_covariates == "hh"])
})

# Step 2 simulation ----

# A grid with one weather profile, covariate profiles and simulation profiles.
make_sim_grid <- function(covariates = list(none = "{method: user}", hh = "{method: user, vars: [hhsize, urban]}"),
                          sims = list(ssp3 = "{ssps: [ssp3_7_0], future_periods: [[2025, 2030]]}")) {
  c(
    "seed: 7",
    "weather:",
    "  hist_years: [2017, 2019]",
    "model: {}",
    "sim:",
    "  hist_years: [2018, 2019]",
    "  future_periods: [[2025, 2030]]",
    "  ssps: [ssp3_7_0]",
    "profiles:",
    "  weather:",
    "    tx_3m: {tx: {ref_period: [1, 3], form: continuous}}",
    "  covariates:",
    paste0("    ", names(covariates), ": ", unlist(covariates)),
    "  sim:",
    paste0("    ", names(sims), ": ", unlist(sims)),
    "axes:",
    "  country: [TST]",
    "  weather: [tx_3m]",
    paste0("  covariates: [", paste(names(covariates), collapse = ", "), "]"),
    paste0("  sim: [", paste(names(sims), collapse = ", "), "]")
  )
}
sim_grid <- make_sim_grid()

sim_progress <- function(dir) {
  p <- withr::with_dir(dir, targets::tar_progress_branches())
  p <- as.data.frame(p[p$name %in% c("data_frames", "wx_frames", "fit_tables", "sim_tables"), ])
  rownames(p) <- p$name
  p
}

test_that("simulations run per sim_id, write the three Step 2 tables and are reused", {
  skip_if_not_installed("qs2")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, projections = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, sim_grid)

  g <- wise_spec_expand(file.path(proj, "spec.yaml"))
  expect_identical(nrow(g), 2L)
  expect_identical(length(unique(g$sim_id)), 2L)
  expect_identical(g$spec[[1]]$sim$baseline_survey, "TST|2019")

  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  p <- sim_progress(proj)
  expect_identical(p["fit_tables", "branches"], 2L)
  expect_identical(p["sim_tables", "branches"], 2L)

  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_setequal(runs$sim_id, g$sim_id)
  expect_true(all(c(
    "sim_id", "sim_hist_from", "sim_hist_to", "sim_future_periods", "sim_ssps", "sim_residuals",
    "sim_coef_uncertainty", "sim_baseline_survey"
  ) %in% names(runs)))
  expect_identical(unique(runs$sim_baseline_survey), "TST|2019")
  expect_false("axis_sim_id" %in% names(runs))

  # Table schemas.
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_identical(
    names(annual)[names(annual) != "code"],
    c(
      "sim_id", "policy_id", "scenario", "metric", "member", "sim_year", "value", "sd",
      "sd_resid", "var_within", "var_across", "weighted"
    )
  )
  expect_setequal(unique(annual$sim_id), g$sim_id)
  expect_identical(unique(annual$code), "TST")
  expect_true(all(is.na(annual$policy_id)))
  expect_setequal(unique(annual$scenario), c("Historical", "SSP3-7.0 / 2025-2030"))
  expect_setequal(annual$member[annual$scenario != "Historical"], c("MODEL.A", "MODEL.B"))
  expect_setequal(annual$sim_year, 2018:2019)
  expect_true("mean" %in% annual$metric)
  expect_type(annual$value, "double")

  summ <- arrow::open_dataset(file.path(out, "tables", "summary")) |> dplyr::collect()
  expect_identical(
    names(summ)[names(summ) != "code"],
    c(
      "sim_id", "policy_id", "scenario", "metric", "section", "measure", "group", "return_period",
      "estimate", "lo", "hi", "n", "text"
    )
  )
  expect_true(all(c("expected", "adverse_year", "headline", "uncertainty") %in% summ$section))

  w <- arrow::open_dataset(file.path(out, "tables", "sim_weather")) |> dplyr::collect()
  expect_identical(
    names(w)[names(w) != "code"],
    c("sim_id", "scenario", "section", "member", "variable", "statistic", "value", "text")
  )
  expect_setequal(w$member[w$section == "members"], c("MODEL.A", "MODEL.B"))
  expect_identical(unique(w$variable[w$section == "support"]), "tx")

  prov <- arrow::read_parquet(file.path(out, "provenance.parquet"))
  expect_setequal(prov$stage, c("data", "weather", "fit", "sim"))
  expect_true(all(prov$n_failed_keys[prov$stage == "sim"] == 0L))
  manifest <- jsonlite::read_json(file.path(out, "manifest.json"))
  expect_true(all(c("annual", "summary", "sim_weather") %in% unlist(manifest$tables)))
  expect_identical(manifest$n_sims, 2L)

  # The stored numbers are the ones the core gives for the same spec.
  spec <- g$spec[[which(g$covariates == "hh")]]
  cp <- build_connection_params("local", path = data)
  md <- load_overview_metadata(cp)
  ss <- wise_select_surveys(md$survey_list, "hh", cp)
  df <- prepare_survey_data(load_survey_frame(ss, cp), md$variable_list, md$cpi_ppp)
  df <- wise_join_location_panel(df, wise_load_location_panel(ss, cp))
  so <- wise_selected_outcome(md$variable_list, df, "welfare", "PPP")$so
  sw <- wise_selected_weather(spec$weather, md$variable_list)
  wx <- wise_load_weather(
    df, ss, sw, stats::setNames(spec$weather$hist_years, c("from", "to")), cp, spec$seed
  )
  m <- wise_model_from_spec(spec$model, "hh", wx$survey_weather, so, sw, md$variable_list, spec$seed)
  mf <- wise_fit(wx$survey_weather, wx$stored_breaks, so, sw, m$selected_model, md$variable_list, spec$seed)
  sim <- spec$sim
  input <- wise_step2_input(
    sw, so, step2_baseline_run(wx$survey_weather, sim$baseline_survey, sw, mf, so)$svy,
    .step2_filter_baseline_surveys(ss, sim$baseline_survey), mf, cp, sim$hist_years,
    sim$future_periods, sim$ssps, sim$residuals, sim$coef_uncertainty,
    stored_breaks = wx$stored_breaks, slim = TRUE
  )
  # (dplyr's many-to-many join warning is expected here, see wise_batch_sim().)
  run <- suppressWarnings(step2_compute(
    .wise_step2_async_normalize_input(input), seed = spec$seed, run_id = "direct", weather_storage = "memory"
  ))
  res <- wise_step2_annotate(run$result, sw, sim$hist_years, "")
  direct <- step2_batch_tables(res, skip_coef = FALSE, selected_weather = sw)
  mine <- annual[annual$sim_id == g$sim_id[g$covariates == "hh"], ]
  expect_identical(mine$value, direct$annual$value)
  expect_identical(mine$sd, direct$annual$sd)
  expect_identical(mine$scenario, direct$annual$scenario)
  expect_identical(mine$member, direct$annual$member)
  other <- annual[annual$sim_id == g$sim_id[g$covariates == "none"], ]
  expect_false(identical(other$value, mine$value))
  s_mine <- summ[summ$sim_id == g$sim_id[g$covariates == "hh"], ]
  expect_identical(s_mine$estimate, direct$summary$estimate)

  # A second run recomputes nothing.
  make_it(proj)
  p <- sim_progress(proj)
  expect_identical(p$skipped, p$branches)

  # A new simulation profile reruns only the simulations; the fits are kept.
  write_project(proj, make_sim_grid(sims = list(
    ssp3 = "{ssps: [ssp3_7_0], future_periods: [[2025, 2030]]}", hist = "{future_periods: []}"
  )))
  make_it(proj)
  p <- sim_progress(proj)
  expect_identical(p["sim_tables", "branches"], 4L)
  expect_identical(p["sim_tables", "completed"], 2L)
  expect_identical(p["sim_tables", "skipped"], 2L)
  expect_identical(p["fit_tables", "skipped"], 2L)
  expect_identical(p["wx_frames", "skipped"], 1L)
  expect_identical(p["data_frames", "skipped"], 1L)
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_identical(length(unique(annual$sim_id)), 4L)
  # A historical-only simulation has no scenario rows and no sim_weather rows.
  hist_ids <- setdiff(unique(annual$sim_id), g$sim_id)
  expect_identical(unique(annual$scenario[annual$sim_id %in% hist_ids]), "Historical")
  w <- arrow::open_dataset(file.path(out, "tables", "sim_weather")) |> dplyr::collect()
  expect_false(any(w$sim_id %in% hist_ids))

  # A new model profile reruns its fit and simulation only.
  write_project(proj, make_sim_grid(
    covariates = list(
      none = "{method: user}", hh = "{method: user, vars: [hhsize, urban]}",
      hh2 = "{method: user, vars: [hhsize]}"
    ),
    sims = list(
      ssp3 = "{ssps: [ssp3_7_0], future_periods: [[2025, 2030]]}", hist = "{future_periods: []}"
    )
  ))
  make_it(proj)
  p <- sim_progress(proj)
  expect_identical(p["fit_tables", "completed"], 1L)
  expect_identical(p["fit_tables", "skipped"], 2L)
  expect_identical(p["sim_tables", "completed"], 2L)
  expect_identical(p["data_frames", "skipped"], 1L)
  expect_identical(p["wx_frames", "skipped"], 1L)
})

test_that("a poverty line shares the data and the fit and sets the simulation's headcount line", {
  skip_if_not_installed("qs2")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, projections = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, c(
    make_sim_grid(covariates = list(none = "{method: user}")), "  poverty_line: [3, 8.3]"
  ))
  g <- wise_spec_expand(file.path(proj, "spec.yaml"))
  expect_identical(nrow(g), 2L)
  expect_identical(length(unique(g$data_id)), 1L)
  expect_identical(length(unique(g$fit_id)), 1L)
  expect_identical(length(unique(g$sim_id)), 2L)

  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  p <- sim_progress(proj)
  expect_identical(p["data_frames", "branches"], 1L)
  expect_identical(p["fit_tables", "branches"], 1L)
  expect_identical(p["sim_tables", "branches"], 2L)

  # The headcount of the higher line is higher in every member-year; the other
  # metrics and the model do not change.
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  by_run <- function(metric) {
    x <- annual[annual$metric == metric, c("sim_id", "scenario", "member", "sim_year", "value")]
    lo <- x[x$sim_id == g$sim_id[g$poverty_line == 3], ]
    hi <- x[x$sim_id == g$sim_id[g$poverty_line == 8.3], ]
    merge(lo, hi, by = c("scenario", "member", "sim_year"), suffixes = c("_lo", "_hi"))
  }
  hc <- by_run("headcount_ratio")
  expect_true(nrow(hc) > 0L)
  expect_true(all(hc$value_hi >= hc$value_lo))
  expect_true(any(hc$value_hi > hc$value_lo))
  mn <- by_run("mean")
  expect_equal(mn$value_lo, mn$value_hi)
})

test_that("a simulation that cannot run is recorded and the other simulations still run", {
  data <- withr::local_tempdir()
  batch_fixture_tree(data, projections = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  # The fixture has no SSP5-8.5 projections.
  write_project(proj, make_sim_grid(
    covariates = list(none = "{method: user}"),
    sims = list(
      ssp3 = "{ssps: [ssp3_7_0], future_periods: [[2025, 2030]]}",
      ssp5 = "{ssps: [ssp5_8_5], future_periods: [[2025, 2030]]}"
    )
  ))
  make_it(proj)
  out <- file.path(proj, "results")
  f <- arrow::read_parquet(file.path(out, "failures.parquet"))
  expect_identical(nrow(f), 1L)
  expect_identical(f$stage, "sim")
  expect_identical(f$n_runs, 1L)
  expect_false(grepl(data, f$message, fixed = TRUE))
  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_identical(f$run_ids, runs$run_id[runs$axis_sim == "ssp5"])
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_identical(unique(annual$sim_id), runs$sim_id[runs$axis_sim == "ssp3"])
  # The model tables of the failed simulation's fit are there.
  terms <- arrow::open_dataset(file.path(out, "tables", "model_terms")) |> dplyr::collect()
  expect_identical(length(unique(terms$fit_id)), 1L)
})

test_that("the sim controller is used when the pipeline defines one", {
  skip_if_not_installed("crew")
  withr::defer(targets::tar_option_reset())
  expect_type(.batch_sim_resources(), "list")
  expect_null(.batch_sim_resources()$crew)
  ctl <- wise_batch_controller(workers = 2L, cores = 4L, sim_workers = 1L)
  expect_identical(names(ctl$controllers), c("default", "sim"))
  expect_identical(Sys.getenv("WISEAPP_DUCKDB_THREADS"), "1")
  targets::tar_option_set(controller = ctl)
  expect_identical(.batch_sim_resources()$crew$controller, "sim")
  single <- wise_batch_controller(workers = 2L, cores = 4L)
  expect_null(single$controllers)
  targets::tar_option_set(controller = single)
  expect_null(.batch_sim_resources()$crew)
})

# Step 3 policy ----

# One fit and one simulation, crossed with policy profiles.
make_policy_grid <- function(policies) {
  c(
    "seed: 7",
    "weather:",
    "  hist_years: [2017, 2019]",
    "model:",
    "  covariates: {method: user, vars: [hhsize, urban, electricity]}",
    "sim:",
    "  hist_years: [2018, 2019]",
    "  future_periods: [[2025, 2030]]",
    "  ssps: [ssp3_7_0]",
    "profiles:",
    "  weather:",
    "    tx_3m: {tx: {ref_period: [1, 3], form: continuous}}",
    "  policy:",
    paste0("    ", names(policies), ": ", unlist(policies)),
    "axes:",
    "  country: [TST]",
    "  weather: [tx_3m]",
    paste0("  policy: [", paste(names(policies), collapse = ", "), "]")
  )
}
policy_profiles <- list(
  none = "{}",
  cash = "{sp: {transfer_amount_usd: 60, targeting: exante_poor, targeting_threshold_pct: 30}}",
  mixed = "{sp: {transfer_amount_usd: 60, targeting: exante_poor, targeting_threshold_pct: 30}, infra: {elec_pct: 40}}"
)

policy_progress <- function(dir) {
  p <- withr::with_dir(dir, targets::tar_progress_branches())
  p <- as.data.frame(p[p$name %in% c("fit_tables", "sim_tables", "policy_tables"), ])
  rownames(p) <- p$name
  p
}

test_that("policies run per policy_id on the stored Step 2 run, write the Step 3 tables and are reused", {
  skip_if_not_installed("qs2")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, projections = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, make_policy_grid(policy_profiles))

  g <- wise_spec_expand(file.path(proj, "spec.yaml"))
  expect_identical(nrow(g), 3L)
  expect_identical(length(unique(g$sim_id)), 1L)
  expect_true(is.na(g$policy_id[g$policy == "none"]))
  expect_identical(length(unique(g$policy_id[g$policy != "none"])), 2L)

  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  p <- policy_progress(proj)
  expect_identical(p["fit_tables", "branches"], 1L)
  expect_identical(p["sim_tables", "branches"], 1L)
  expect_identical(p["policy_tables", "branches"], 2L)
  # The Step 2 run is kept for the policy branches.
  stored <- file.path(proj, "_targets", "user", "sims", paste0(g$sim_id[[1L]], ".qs2"))
  expect_true(file.exists(stored))

  runs <- arrow::read_parquet(file.path(out, "runs.parquet"))
  expect_true(all(c("policy_id", "policy_levers", "policy") %in% names(runs)))
  expect_identical(runs$policy_levers[runs$axis_policy == "mixed"], "infra,sp")
  expect_true(is.na(runs$policy[runs$axis_policy == "none"]))

  # The baseline arm is stored once; each policy adds its own rows.
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_identical(
    names(annual)[names(annual) != "code"],
    c(
      "sim_id", "policy_id", "scenario", "metric", "member", "sim_year", "value", "sd",
      "sd_resid", "var_within", "var_across", "weighted"
    )
  )
  expect_setequal(annual$policy_id, c(NA, g$policy_id[g$policy != "none"]))
  base <- annual[is.na(annual$policy_id), ]
  cash_id <- g$policy_id[g$policy == "cash"]
  cash <- annual[!is.na(annual$policy_id) & annual$policy_id == cash_id, ]
  expect_identical(nrow(cash), nrow(base))
  expect_identical(cash$member, base$member)
  # A positive transfer to the poor raises the mean outcome in every year.
  key <- function(d) paste(d$scenario, d$member, d$sim_year, d$metric)
  b_mean <- base[base$metric == "mean", ]
  c_mean <- cash[cash$metric == "mean", ]
  expect_true(all(c_mean$value >= b_mean$value[match(key(c_mean), key(b_mean))]))
  expect_true(any(c_mean$value > b_mean$value[match(key(c_mean), key(b_mean))]))

  summ <- arrow::open_dataset(file.path(out, "tables", "summary")) |> dplyr::collect()
  expect_identical(
    names(summ)[names(summ) != "code"],
    c(
      "sim_id", "policy_id", "scenario", "metric", "section", "measure", "group", "return_period",
      "estimate", "lo", "hi", "n", "text"
    )
  )
  pol <- summ[!is.na(summ$policy_id) & summ$policy_id == cash_id, ]
  expect_true(all(c(
    "policy_expected", "policy_adverse", "policy_threshold", "policy_adverse_dot",
    "policy_headline", "policy_incidence"
  ) %in% pol$section))
  expect_true(all(is.na(summ$policy_id[summ$section == "expected"])))
  # The expected effect of the historical arm is the difference of the stored
  # annual means (one equal-model mean over the same years).
  eff <- pol[pol$section == "policy_expected" & pol$metric == "mean" & pol$measure == "effect" &
    pol$group == "intermodel" & pol$scenario == "Historical", ]
  h <- function(d) mean(d$value[d$scenario == "Historical" & d$metric == "mean"])
  expect_equal(eff$estimate, h(cash) - h(base), tolerance = 1e-10)

  dec <- arrow::open_dataset(file.path(out, "tables", "decomposition")) |> dplyr::collect()
  expect_identical(
    names(dec)[names(dec) != "code"],
    c(
      "sim_id", "policy_id", "source", "scenario", "member", "sim_year", "metric", "group",
      "channel", "value", "sum", "weight", "n_units"
    )
  )
  expect_setequal(unique(dec$policy_id), g$policy_id[g$policy != "none"])
  expect_setequal(unique(dec$source), c("compact", "metric"))
  expect_true(all(c("delta_total", "lvl_total") %in% dec$channel))
  expect_true(all(c("baseline", "policy", "main", "total") %in% dec$channel[dec$source == "metric"]))
  expect_true("mean" %in% dec$metric)
  # The total channel is the policy state minus the baseline state.
  m <- dec[dec$policy_id == cash_id & dec$source == "metric" & dec$metric == "mean" & dec$group == "all", ]
  wide <- tidyr::pivot_wider(m[c("scenario", "member", "sim_year", "channel", "value")], names_from = channel, values_from = value)
  expect_equal(wide$total, wide$policy - wide$baseline, tolerance = 1e-8)

  meas <- arrow::open_dataset(file.path(out, "tables", "policy_measures")) |> dplyr::collect()
  expect_identical(
    names(meas)[names(meas) != "code"],
    c("sim_id", "policy_id", "section", "scenario", "metric", "measure", "group", "value", "text")
  )
  expect_true(all(c("transfer", "sp_effectiveness", "components", "treatment", "reach") %in% meas$section))
  expect_true("input_diagnostics" %in% meas$section[meas$policy_id == g$policy_id[g$policy == "mixed"]])
  expect_identical(unique(meas$code), "TST")

  prov <- arrow::read_parquet(file.path(out, "provenance.parquet"))
  expect_setequal(prov$stage, c("data", "weather", "fit", "sim", "policy"))
  manifest <- jsonlite::read_json(file.path(out, "manifest.json"))
  expect_true(all(c("decomposition", "policy_measures") %in% unlist(manifest$tables)))
  expect_identical(manifest$n_policies, 2L)

  # A second run recomputes nothing.
  make_it(proj)
  p <- policy_progress(proj)
  expect_identical(p$skipped, p$branches)

  # A new policy profile reruns only its policy branch.
  write_project(proj, make_policy_grid(c(policy_profiles, list(
    cash100 = "{sp: {transfer_amount_usd: 100, targeting: exante_poor, targeting_threshold_pct: 30}}"
  ))))
  make_it(proj)
  p <- policy_progress(proj)
  expect_identical(p["policy_tables", "branches"], 3L)
  expect_identical(p["policy_tables", "completed"], 1L)
  expect_identical(p["policy_tables", "skipped"], 2L)
  expect_identical(p["sim_tables", "skipped"], 1L)
  expect_identical(p["fit_tables", "skipped"], 1L)
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_identical(length(unique(annual$policy_id[!is.na(annual$policy_id)])), 3L)
  # A transfer set from a welfare percentile reruns only its branch and records the amount used.
  pct_profile <- paste0(
    "{sp: {transfer_amount_mode: pctile, transfer_pctile: 10, transfer_n_payments: 6, ",
    "targeting: exante_poor, targeting_threshold_pct: 30}}"
  )
  write_project(proj, make_policy_grid(c(policy_profiles, list(
    cash100 = "{sp: {transfer_amount_usd: 100, targeting: exante_poor, targeting_threshold_pct: 30}}",
    p10 = pct_profile
  ))))
  make_it(proj)
  p <- policy_progress(proj)
  expect_identical(p["policy_tables", "branches"], 4L)
  expect_identical(p["policy_tables", "completed"], 1L)
  meas <- arrow::open_dataset(file.path(out, "tables", "policy_measures")) |> dplyr::collect()
  amt <- meas[meas$section == "transfer_amount", ]
  expect_identical(length(unique(amt$policy_id)), 1L)
  val <- stats::setNames(amt$value, amt$measure)
  expect_identical(val[["percentile"]], 10)
  expect_equal(val[["per_payment"]] * 6, val[["per_year"]])
  expect_equal(val[["daily_value"]] * 365, val[["per_year"]])
  expect_identical(unique(amt$text), "PPP")
  # Dropping the policies from the grid removes the stored Step 2 run.
  write_project(proj, make_policy_grid(list(none = "{}")))
  make_it(proj)
  expect_false(file.exists(stored))
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_true(all(is.na(annual$policy_id)))
})

test_that("a shock-responsive policy stores its member-year rows and its program measures", {
  skip_if_not_installed("qs2")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, projections = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, make_policy_grid(list(shock = paste0(
    "{sp: {sp_type: shock, trigger_variable: tx, trigger_type: weather, trigger_value: 29.5, ",
    "trigger_direction: above, transfer_amount_usd: 60, targeting: exante_poor, ",
    "targeting_threshold_pct: 40, loss_event_pct: 5}}"
  ))), keep = FALSE)
  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  shock <- annual[grepl("^shock_", annual$metric), ]
  expect_true(all(c(
    "shock_activated", "shock_exposed_share", "shock_transfer_cost", "shock_admin_cost"
  ) %in% shock$metric))
  expect_false(anyNA(shock$policy_id))
  expect_true(all(shock$value[shock$metric == "shock_activated"] %in% c(0, 1)))
  expect_true(all(shock$value[shock$metric == "shock_transfer_cost"] >= 0))
  # One row per member and year, as the climate-member rows of the other metrics.
  n_mean <- sum(annual$metric == "mean" & !is.na(annual$policy_id))
  expect_identical(sum(shock$metric == "shock_activated"), n_mean)
  meas <- arrow::open_dataset(file.path(out, "tables", "policy_measures")) |> dplyr::collect()
  expect_true(all(c("shock_summary", "shock_climate_cost") %in% meas$section))
  af <- meas$value[meas$section == "shock_summary" & meas$measure == "activation_freq"]
  expect_true(all(af >= 0 & af <= 1))
  # The stored per-year rows give the summary: activation frequency by scenario.
  act <- shock[shock$metric == "shock_activated", ]
  freq <- vapply(split(act$value, act$scenario), mean, 0)
  sc <- meas$scenario[meas$section == "shock_summary" & meas$measure == "activation_freq"]
  expect_equal(unname(freq[sc]), af, tolerance = 1e-12)
  # The Step 2 run was not kept (keep_step2 = FALSE).
  expect_length(list.files(file.path(proj, "_targets", "user", "sims")), 0L)
  # A policy-only change then needs the simulation target invalidated.
  write_project(proj, make_policy_grid(list(shock = paste0(
    "{sp: {sp_type: shock, trigger_variable: tx, trigger_type: weather, trigger_value: 31, ",
    "trigger_direction: above, transfer_amount_usd: 60, targeting: exante_poor, ",
    "targeting_threshold_pct: 40}}"
  ))), keep = FALSE)
  make_it(proj)
  f <- arrow::read_parquet(file.path(out, "failures.parquet"))
  expect_identical(nrow(f), 1L)
  expect_identical(f$stage, "policy")
  expect_match(f$message, "stored Step 2 run is missing|failed")
})

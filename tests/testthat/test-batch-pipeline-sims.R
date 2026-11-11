# Batch runner: Step 2 simulations per sim_id (split from test-batch-pipeline.R so files run in parallel).

skip_if_not_installed("targets")
skip_if_not_installed("arrow")
skip_if_not_installed("yaml")

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
  expect_true(all(prov$residuals_applied[prov$stage == "sim"] == prov$residuals_requested[prov$stage == "sim"]))
  expect_false(anyNA(prov$residuals_applied[prov$stage == "sim"]))
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

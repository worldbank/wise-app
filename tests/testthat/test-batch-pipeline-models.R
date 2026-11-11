# Batch runner: Step 1 model fits per fit_id (split from test-batch-pipeline.R so files run in parallel).

skip_if_not_installed("targets")
skip_if_not_installed("arrow")
skip_if_not_installed("yaml")

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

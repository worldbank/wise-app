# End-to-end smoke test of the batch runner on the fixture data folder:
# the grid becomes runs, the targets pipeline writes the parquet store, shared
# work is reused, and a failing data set is recorded without stopping the rest.

skip_if_not_installed("targets")
skip_if_not_installed("arrow")
skip_if_not_installed("yaml")

write_project <- function(dir, grid_lines) {
  writeLines(grid_lines, file.path(dir, "spec.yaml"))
  writeLines(c(
    "library(targets)",
    "tar_option_set(error = \"continue\", memory = \"transient\")",
    "wiseapp::wise_targets(\"spec.yaml\", out_dir = \"results\")"
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
      paste0("p", seq(10, 90, 10)), "p25", "p75", "share_one"
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
      "avg_dates_per_loc"
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

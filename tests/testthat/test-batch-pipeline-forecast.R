# Batch runner: forecast simulations, ENSO tables and forecast-window policies (split from test-batch-pipeline.R so files run in parallel).

skip_if_not_installed("targets")
skip_if_not_installed("arrow")
skip_if_not_installed("yaml")

test_that("a forecast simulation writes the forecast table and the placement, skill and season rows", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("digest")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, forecast = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, c(
    "seed: 7",
    "model: {}",
    "sim:",
    "  hist_years: [2018, 2019]",
    "  future_periods: []",
    "  ssps: []",
    "  coef_uncertainty: false",
    "  forecast: {product: seasonal, run: '2021-01', start: '2021-02', len: 3}",
    "profiles:",
    "  weather:",
    "    t_1m: {t: {ref_period: [1, 1], form: continuous}}",
    "axes:",
    "  country: [TST]",
    "  weather: [t_1m]"
  ))
  g <- wise_spec_expand(file.path(proj, "spec.yaml"))
  expect_identical(nrow(g), 1L)
  expect_match(g$spec[[1L]]$sim$forecast$identity$data_sha256, "^[0-9a-f]{64}$")

  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  label <- "Seasonal forecast / Feb 2021 - Apr 2021 (January 2021 run)"

  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_setequal(unique(annual$scenario), c("Historical", label))
  expect_length(unique(annual$member[annual$scenario == label]), 3L)

  fc <- arrow::open_dataset(file.path(out, "tables", "forecast")) |> dplyr::collect()
  expect_identical(
    names(fc)[names(fc) != "code"],
    c("sim_id", "scenario", "metric", "kind", "id", "year", "value", "p_adverse", "return_period", "beyond")
  )
  mean_rows <- fc[fc$metric == "mean", ]
  expect_identical(sum(mean_rows$kind == "member"), 3L)
  expect_setequal(mean_rows$id[mean_rows$kind == "reference"], c("refyear_2018", "refyear_2019"))
  expect_setequal(mean_rows$year[mean_rows$kind == "reference"], 2018:2019)
  expect_true(all(is.finite(mean_rows$value)))
  expect_true(all(mean_rows$p_adverse[mean_rows$kind == "member"] >= 0))

  summ <- arrow::open_dataset(file.path(out, "tables", "summary")) |> dplyr::collect()
  placement <- summ[summ$section == "placement" & summ$metric == "mean", ]
  expect_true(all(c("member_median", "reference_median", "share_worse_than_1in10") %in% placement$measure))
  expect_true(all(placement$n == 2))
  expect_setequal(summ$measure[summ$section == "season"], c("training_month_share", "training_month_expected"))
  expect_match(summ$text[summ$section == "skill"], "not assessed")
})

test_that("ENSO tables add labels apart from the simulation, and a refresh does not rerun it", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("digest")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, forecast = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, c(
    "seed: 7",
    "model: {}",
    "sim:",
    "  hist_years: [2018, 2019]",
    "  future_periods: []",
    "  ssps: []",
    "  coef_uncertainty: false",
    "  forecast: {product: seasonal, run: '2021-01', start: '2021-02', len: 3}",
    "profiles:",
    "  weather:",
    "    t_1m: {t: {ref_period: [1, 1], form: continuous}}",
    "axes:",
    "  country: [TST]",
    "  weather: [t_1m]"
  ))
  out <- file.path(proj, "results")
  make_it(proj)
  # Without the tables: no ENSO output, and the run is unaffected.
  expect_false(dir.exists(file.path(out, "tables", "enso_years")))
  expect_null(jsonlite::fromJSON(file.path(out, "manifest.json"))$enso)
  before <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()

  months <- seq(as.Date("2010-01-01"), as.Date("2021-12-01"), by = "month")
  write_enso <- function(roni) {
    utils::write.csv(data.frame(
      timestamp = months, source = "cpc", roni = roni,
      phase = ifelse(roni >= 0.5, "el_nino", ifelse(roni <= -0.5, "la_nina", "neutral"))
    ), file.path(data, "metadata", "enso.csv"), row.names = FALSE)
  }
  write_enso(rep(1, length(months)))
  make_it(proj)
  # Each branch's time stamp: a branch that reruns gets a new one.
  sim_runs <- function() {
    meta <- withr::with_dir(proj, targets::tar_meta(fields = c("name", "time")))
    meta <- meta[startsWith(meta$name, "sim_tables_"), ]
    stats::setNames(as.numeric(meta$time), meta$name)
  }
  ran <- sim_runs()
  expect_gt(length(ran), 0L)
  expect_false(anyNA(ran))
  years <- arrow::open_dataset(file.path(out, "tables", "enso_years")) |> dplyr::collect()
  expect_setequal(years$sample, c("annual", "target_months"))
  expect_true(all(years$label == "el_nino"))
  expect_setequal(years$sim_year[years$sample == "target_months"], 2018:2019)
  summ <- arrow::open_dataset(file.path(out, "tables", "summary")) |> dplyr::collect()
  expect_true(any(summ$section == "enso" & summ$measure == "card_line"))
  manifest <- jsonlite::fromJSON(file.path(out, "manifest.json"))
  expect_match(manifest$enso$enso_observed_sha256, "^[0-9a-f]{64}$")
  expect_identical(manifest$enso$enso_last_cpc_month, "2021-12")
  after <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  sorted <- function(d) as.data.frame(d[do.call(order, d[c("scenario", "metric", "member", "sim_year")]), ])
  expect_equal(sorted(after), sorted(before), tolerance = 0)

  write_enso(rep(-1, length(months)))
  make_it(proj)
  expect_identical(sim_runs(), ran)
  refreshed <- arrow::open_dataset(file.path(out, "tables", "enso_years")) |> dplyr::collect()
  expect_true(all(refreshed$label == "la_nina"))
  expect_false(identical(jsonlite::fromJSON(file.path(out, "manifest.json"))$enso, manifest$enso))
})

test_that("a policy on a forecast window writes the policy arm of the forecast table and the policy effect", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("digest")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, forecast = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, c(
    "seed: 7",
    "model: {}",
    "sim:",
    "  hist_years: [2018, 2019]",
    "  future_periods: []",
    "  ssps: []",
    "  coef_uncertainty: false",
    "  forecast: {product: seasonal, run: '2021-01', start: '2021-02', len: 3}",
    "profiles:",
    "  weather:",
    "    t_1m: {t: {ref_period: [1, 1], form: continuous}}",
    "  policy:",
    "    cash: {sp: {transfer_amount_usd: 60, targeting: exante_poor, targeting_threshold_pct: 30}}",
    "axes:",
    "  country: [TST]",
    "  weather: [t_1m]",
    "  policy: [cash]"
  ))
  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  label <- "Seasonal forecast / Feb 2021 - Apr 2021 (January 2021 run)"

  fc <- arrow::open_dataset(file.path(out, "tables", "forecast")) |> dplyr::collect()
  expect_true(any(is.na(fc$policy_id)) && any(!is.na(fc$policy_id)))
  base <- fc[is.na(fc$policy_id) & fc$metric == "mean" & fc$kind == "member", ]
  pol <- fc[!is.na(fc$policy_id) & fc$metric == "mean" & fc$kind == "member", ]
  expect_identical(sort(base$id), sort(pol$id))
  expect_true(all(pol$value[match(base$id, pol$id)] >= base$value))
  expect_true(any(pol$value[match(base$id, pol$id)] > base$value))

  summ <- arrow::open_dataset(file.path(out, "tables", "summary")) |> dplyr::collect()
  eff <- summ[summ$section == "policy_effect" & summ$metric == "mean" & summ$scenario == label, ]
  expect_true(all(c("effect_member_median", "effect_reference_median", "share_worse_baseline",
    "share_worse_policy") %in% eff$measure))
  expect_gt(eff$estimate[eff$measure == "effect_member_median"], 0)
  expect_gt(eff$estimate[eff$measure == "effect_reference_median"], 0)
  # The fixture has 2 reference years, and a 1-in-10 level needs 9 (Weibull rank 0.1 (n + 1) >= 1): the shares are NA
  expect_true(is.na(eff$estimate[eff$measure == "share_worse_policy"]))
  expect_true(is.na(eff$estimate[eff$measure == "share_worse_baseline"]))
  # The annual tables of the policy arm carry no forecast scenario.
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_false(label %in% annual$scenario[!is.na(annual$policy_id)])
})

test_that("a shock-responsive transfer on a forecast window writes the shock_window rows", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("digest")
  data <- withr::local_tempdir()
  batch_fixture_tree(data, forecast = TRUE)
  proj <- withr::local_tempdir()
  withr::local_envvar(WISEAPP_DATA_PATH = data)
  write_project(proj, c(
    "seed: 7",
    "model: {}",
    "sim:",
    "  hist_years: [2018, 2019]",
    "  future_periods: []",
    "  ssps: []",
    "  coef_uncertainty: false",
    "  forecast: {product: seasonal, run: '2021-01', start: '2021-02', len: 3}",
    "profiles:",
    "  weather:",
    "    t_1m: {t: {ref_period: [1, 1], form: continuous}}",
    "  policy:",
    "    shock: {sp: {sp_type: shock, trigger_variable: t, trigger_type: weather, trigger_value: 0,",
    "      trigger_direction: above, transfer_amount_usd: 60, targeting: exante_poor,",
    "      targeting_threshold_pct: 30}}",
    "axes:",
    "  country: [TST]",
    "  weather: [t_1m]",
    "  policy: [shock]"
  ))
  make_it(proj)
  out <- file.path(proj, "results")
  expect_identical(nrow(arrow::read_parquet(file.path(out, "failures.parquet"))), 0L)
  label <- "Seasonal forecast / Feb 2021 - Apr 2021 (January 2021 run)"

  summ <- arrow::open_dataset(file.path(out, "tables", "summary")) |> dplyr::collect()
  sw <- summ[summ$section == "shock_window" & summ$scenario == label, ]
  expect_true(all(c("member_share", "reference_share", "exposed_member", "exposed_reference",
    "cost_median", "cost_min", "cost_max", "cost_reference") %in% sw$measure))
  expect_true(all(is.na(sw$metric)))
  # `n` is the number of members (the fixture run has three).
  expect_true(all(sw$n == 3))
  # A trigger of 0 degrees pays in every member and reference year.
  expect_equal(sw$estimate[sw$measure == "member_share"], 1)
  expect_equal(sw$estimate[sw$measure == "reference_share"], 1)
  expect_gt(sw$estimate[sw$measure == "cost_median"], 0)
  expect_lte(sw$estimate[sw$measure == "cost_min"], sw$estimate[sw$measure == "cost_max"])
  # The window payout stays out of the annual tables.
  annual <- arrow::open_dataset(file.path(out, "tables", "annual")) |> dplyr::collect()
  expect_false(label %in% annual$scenario[!is.na(annual$policy_id)])
})

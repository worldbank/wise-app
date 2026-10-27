# The Step 3 results views and the batch tables of a policy run. The Results
# pane and the batch tables call the same view functions; these tests drive the
# pane with shiny::testServer() on a small fixture run and compare what it
# holds with what the tables store.

# dev/ is not part of the built package, so the fixture run only exists in a
# source checkout.
bench_ok <- file.exists(testthat::test_path("../../dev/bench/bench_step3_helpers.R"))

step3_fixture_cache <- new.env(parent = emptyenv())

# A real Step 3 run on the benchmark fixture (60 households, two years, one
# scenario): the Step 2 result, the run and its lever configurations.
step3_fixture <- function(label = "targeted_sp") {
  skip_if_not(bench_ok, "dev/ benchmark helpers not available")
  if (!is.null(step3_fixture_cache[[label]])) {
    return(step3_fixture_cache[[label]])
  }
  source(testthat::test_path("../../dev/bench/bench_step3_helpers.R"), local = TRUE)
  source(testthat::test_path("../../dev/bench/bench_step2_helpers.R"), local = TRUE)
  input <- .bench_small_step3_input(n = 60L)
  baseline <- .bench_small_step2_result(input, "ols", "one_ssp_one_period")
  fixture <- .bench_step3_policy_fixtures(label)[[1L]]
  mf <- input$models[["ols"]]
  hs <- baseline$hist_sim_result
  ss <- baseline$new_scenarios %||% list()
  run <- step3_compute(
    svy = input$svy, hs = hs, ss = ss, mf = mf, sp_cfg = fixture$sp, infra_cfg = fixture$infra,
    model_vars = .bench_step3_model_terms(mf), analysis_unit = "hh", skip_coef = TRUE,
    residuals = "original", run_generation = 1L, seed = 123L
  )
  out <- list(
    svy = input$svy, hs = hs, ss = ss, run = run,
    levers = list(sp = fixture$sp, infra = fixture$infra)
  )
  step3_fixture_cache[[label]] <- out
  out
}

fixture_tables <- function(fx) {
  step3_batch_tables(fx$run, fx$hs, fx$ss, fx$svy, fx$levers, skip_coef = TRUE, analysis_unit = "hh")
}

# The Results pane on the run, as the module wires it; its internals go to
# `store$pane`.
pane_server <- function(fx, store) {
  run <- fx$run
  function(input, output, session) {
    store$pane <- .wire_results_pane(
      input, output, session,
      baseline_hist_sim = shiny::reactiveVal(run$baseline_out),
      baseline_saved_scenarios = shiny::reactiveVal(run$baseline_scenarios_out),
      policy_hist_sim = shiny::reactiveVal(run$pol_out$hist_sim),
      policy_saved_scenarios = shiny::reactiveVal(run$pol_out$saved_scenarios),
      selected_hist = shiny::reactiveVal(NULL),
      sp_scenario = shiny::reactiveVal(fx$levers$sp),
      decomp_scenarios = shiny::reactiveVal(run$pol_out$decomp_scenarios),
      decomp_context = shiny::reactiveVal(run$decomp_context),
      annual_channels = shiny::reactiveVal(run$pol_out$annual_channels),
      baseline_svy = shiny::reactiveVal(fx$svy),
      policy_svy = shiny::reactiveVal(step3_published_policy_svy(run$svy_mod, run$pol_out$shock)),
      analysis_unit = shiny::reactiveVal("hh")
    )
  }
}

test_that("the policy tables have their schema and every metric", {
  fx <- step3_fixture()
  out <- fixture_tables(fx)
  expect_identical(out$status$status, "ok")
  expect_identical(out$partial, character(0))
  expect_setequal(names(out$tables), c("annual", "summary", "decomposition", "policy_measures"))
  expect_identical(
    names(out$tables$annual),
    c("policy_id", "scenario", "metric", "member", "sim_year", "value", "sd", "sd_resid", "var_within", "var_across", "weighted")
  )
  expect_identical(
    names(out$tables$summary),
    c("scenario", "metric", "section", "measure", "group", "return_period", "estimate", "lo", "hi", "n", "text")
  )
  expect_identical(
    names(out$tables$decomposition),
    c("source", "scenario", "member", "sim_year", "metric", "group", "channel", "value", "sum", "weight", "n_units")
  )
  expect_identical(
    names(out$tables$policy_measures),
    c("section", "scenario", "metric", "measure", "group", "value", "text")
  )
  methods <- unname(hist_aggregate_choices(fx$hs$so$type, fx$hs$so$name))
  expect_setequal(unique(out$tables$annual$metric), methods)
  s <- out$tables$summary
  expect_setequal(
    unique(s$section),
    c(
      "policy_expected", "policy_adverse", "policy_threshold", "policy_adverse_dot",
      "policy_headline", "policy_incidence"
    )
  )
  expect_setequal(stats::na.omit(unique(s$metric)), methods)
  # The historical arm is `Historical` everywhere.
  scen <- unique(c(out$tables$annual$scenario, s$scenario, out$tables$decomposition$scenario))
  expect_true("Historical" %in% scen)
  expect_setequal(setdiff(scen, "Historical"), names(fx$ss))
  # The compact channels cover every member and year; the metric states every metric.
  d <- out$tables$decomposition
  expect_setequal(unique(d$source), c("compact", "metric"))
  expect_setequal(unique(d$metric[d$source == "metric"]), methods)
  expect_true(all(c("main", "repositioning", "interaction", "total") %in% d$channel[d$source == "metric"]))
  expect_true(all(is.na(d$metric[d$source == "compact"])))
  expect_setequal(unique(d$group[d$source == "compact"]), c("all", paste0("decile_", 1:10)))
  # Measures of a regular transfer.
  m <- out$tables$policy_measures
  expect_true(all(c("transfer", "sp_effectiveness", "components", "treatment", "reach") %in% m$section))
  expect_false("shock_summary" %in% m$section)
})

test_that("the stored values are the ones the Results pane holds", {
  fx <- step3_fixture()
  tab <- fixture_tables(fx)$tables
  store <- new.env()
  shiny::testServer(pane_server(fx, store), {
    internals <- store$pane
    session$setInputs(
      cmp_agg_method = "mean", ensemble_band = "p10_p90", uncertainty_band = "p10_p90",
      cmp_deviation = "none", cmp_pov_line = 3
    )
    session$flushReact()
    pane_summary <- internals$paired_effect_summary()
    s <- tab$summary[tab$summary$metric %in% "mean" & tab$summary$section == "policy_expected", ]
    for (sc in pane_summary$scenario) {
      stored <- function(group) {
        r <- s[s$group == group & s$measure == "effect" & s$scenario == ifelse(grepl("^Historical", sc), "Historical", sc), ]
        stopifnot(nrow(r) == 1L)
        r
      }
      row <- pane_summary[pane_summary$scenario == sc, ]
      expect_equal(stored("intermodel")$estimate, row$value, tolerance = 1e-10)
      expect_equal(stored("intermodel")$lo, row$intermod_lo, tolerance = 1e-10)
      expect_equal(stored("intermodel")$hi, row$intermod_hi, tolerance = 1e-10)
      expect_equal(stored("coefficient")$lo, row$coef_lo, tolerance = 1e-10)
      expect_equal(stored("interannual")$hi, row$interann_hi, tolerance = 1e-10)
    }
    # Thresholds: every row of the pane's table is stored.
    thr <- internals$threshold_table()
    st <- tab$summary[tab$summary$metric %in% "mean" & tab$summary$section == "policy_threshold", ]
    key <- function(scenario, source, estimate, rp) paste(ifelse(grepl("^Historical", scenario), "Historical", scenario), source, estimate, rp)
    expect_identical(nrow(st), nrow(thr))
    expect_equal(
      st$estimate[match(key(thr$scenario, thr$source, thr$Estimate, thr$rp_name), key(st$scenario, st$group, st$measure, st$return_period))],
      unname(thr$value), tolerance = 1e-10
    )
    # Headline cards: the stored text is the card text.
    cards <- step3_headline_df(internals$headline_cards())
    sh <- tab$summary[tab$summary$metric %in% "mean" & tab$summary$section == "policy_headline", ]
    expect_identical(sh$text[grepl("_value$", sh$group)], cards$value)
    # Annual values: the pane's aggregation of the policy arm.
    agg <- internals$policy_agg_scenarios()[[1L]]$out
    st_annual <- tab$annual[tab$annual$metric == "mean" & tab$annual$scenario == names(fx$ss)[[1L]], ]
    expect_equal(sort(st_annual$value), sort(unname(unlist(agg$value_all))), tolerance = 1e-10)
    # The metric decomposition: the stored states.
    decomp <- internals$metric_decomposition()
    dm <- tab$decomposition[tab$decomposition$source == "metric" & tab$decomposition$metric %in% "mean" &
      tab$decomposition$group == "all" & tab$decomposition$channel == "total", ]
    stored_total <- dm$value[match(
      paste(decomp$annual$scenario, decomp$annual$member, decomp$annual$sim_year),
      paste(dm$scenario, dm$member, dm$sim_year)
    )]
    expect_equal(stored_total, decomp$annual$total, tolerance = 1e-10)
  })
})

test_that("the Results pane and the tables agree for a poverty metric", {
  fx <- step3_fixture()
  tab <- fixture_tables(fx)$tables
  store <- new.env()
  shiny::testServer(pane_server(fx, store), {
    internals <- store$pane
    session$setInputs(
      cmp_agg_method = "headcount_ratio", ensemble_band = "p10_p90", uncertainty_band = "p10_p90",
      cmp_deviation = "none", cmp_pov_line = 3
    )
    session$flushReact()
    expect_equal(internals$poverty_line(), 3)
    row <- internals$expected_paired_effect_summary()
    s <- tab$summary[tab$summary$metric %in% "headcount_ratio" & tab$summary$section == "policy_expected" &
      tab$summary$measure == "effect" & tab$summary$group == "range", ]
    expect_equal(s$estimate, row$value, tolerance = 1e-10)
    expect_equal(s$lo, row$intermod_lo, tolerance = 1e-10)
    expect_equal(s$hi, row$intermod_hi, tolerance = 1e-10)
  })
})

test_that("the compact decomposition table keeps the sums and weights of the run", {
  fx <- step3_fixture()
  d <- fixture_tables(fx)$tables$decomposition
  compact <- fx$run$pol_out$decomp_scenarios
  cs <- compact$channel_summary
  one <- d[d$source == "compact" & d$group == "all" & d$channel == "delta_total", ]
  expect_identical(nrow(one), nrow(cs))
  expect_equal(one$sum, cs$sum_delta_total, tolerance = 1e-12)
  expect_equal(one$weight, cs$weight_delta_total, tolerance = 1e-12)
  expect_equal(one$value, cs$sum_delta_total / cs$weight_delta_total, tolerance = 1e-12)
  # Every average of the app is derived from these: the equal-model mean level.
  lvl <- .compact_future_decomp(compact, names(fx$ss)[[1L]], "mean", fx$hs$so)
  mine <- d[d$source == "compact" & d$group == "all" & d$channel == "lvl_total" & d$scenario == names(fx$ss)[[1L]], ]
  per_member <- tapply(mine$sum / mine$weight, mine$member, mean)
  expect_equal(mean(per_member), lvl$lvl_total, tolerance = 1e-10)
})

test_that("an unsupported outcome gives no policy contrast", {
  fx <- step3_fixture()
  hs <- fx$hs
  hs$so$type <- "logical"
  out <- step3_batch_tables(fx$run, hs, fx$ss, fx$svy, fx$levers, skip_coef = TRUE)
  expect_identical(out$status$status, "unsupported")
  expect_length(out$tables, 0L)
})

test_that("the published policy frame marks households paid in a shock run", {
  svy <- data.frame(a = 1:3)
  expect_identical(step3_published_policy_svy(svy, NULL), svy)
  shock <- list(per_household = c(10, 0, 5), paid_historical = c(TRUE, TRUE, FALSE))
  pub <- step3_published_policy_svy(svy, shock)
  expect_identical(pub[[SP_TRANSFER_COL]], c(10, 0, 0))
})

test_that("series, paired data and the tail table follow the pane's rules", {
  fx <- step3_fixture()
  agg <- step2_run_aggregates(fx$run$baseline_out, fx$run$baseline_scenarios_out, TRUE, 3)
  s <- step3_series(agg, "mean", "Historical (test)", names(fx$ss))
  expect_identical(names(s$all), c("Historical (test)", names(fx$ss)))
  expect_identical(s$all[[1L]], s$hist)
  # Identical arms have no effect.
  dat <- step3_paired_data(s$all, s$all)
  expect_identical(names(dat), names(s$all))
  sm <- step3_paired_summary(dat, "p10_p90")
  expect_equal(sm$value, rep(0, nrow(sm)))
  expect_equal(step3_headline_paired_summary(dat)$value, rep(0, nrow(sm)))
  expect_identical(nrow(step3_paired_adverse_table(NULL)), 0L)
  expect_identical(nrow(step3_paired_summary(list())), 0L)
})

test_that("the Step 3 poverty line is the run's, else the outcome's, else 3", {
  expect_equal(step3_pov_line(list(pov_line = 5, so = list(povline = 8.3))), 5)
  expect_equal(step3_pov_line(list(so = data.frame(povline = 8.3))), 8.3)
  expect_equal(step3_pov_line(list(so = data.frame(povline = NA_real_))), 3)
  expect_equal(step3_pov_line(list()), 3)
})

test_that("the tail table finds the historical tails under the run's historical label", {
  rows <- function(source) {
    tibble::tibble(
      scenario = "Historical", source = source, Estimate = "Single historical estimate",
      rp_name = "1:5", rp_label = "1:5", value = 1, n_obs = 30, is_historical = TRUE
    )
  }
  tails <- data.frame(
    scenario = "Historical / 1991-2020", probability = unname(RP_LOW[["1:5"]]),
    baseline = 10, policy = 8, status = "ok", reason = "", center_method = "single_historical"
  )
  testthat::local_mocked_bindings(step3_threshold_rows = function(agg_hist, agg_scn, hist_ref,
                                                                  source_label, ...) rows(source_label))
  thr <- step3_threshold_table(NULL, NULL, NULL, NULL, 0, c(lo = 0.1, hi = 0.9), c(lo = 0.5, hi = 0.5),
    "mean", NULL, character(), tails, hist_label = "Historical / 1991-2020")
  expect_equal(thr$value[thr$source == "Baseline"], 10)
  expect_equal(thr$value[thr$source == "Policy"], 8)
  expect_true(all(thr$status == "ok"))
})

# Step 2 tables of the batch pipeline (`annual`, `summary`, `sim_weather`) and
# the result views they share with the Results module
# (R/fct_step2_tables.R; reference in batch/docs/tables.md).

library(shiny)

step2_tables_weather <- function() {
  data.frame(name = c("temp", "pr"), label = c("Temperature", "Rainfall"))
}

step2_fixture_agg <- function() {
  step2_run_aggregates(step2_fixture_hist(), step2_fixture_scenarios(), skip_coef = FALSE)
}

# Run the Results module on the fixture at the state the stored views assume
# (outcome level, ensemble band p10-p90) for one metric and read its views.
results_module_views <- function(method, extra = NULL) {
  out <- NULL
  testServer(
    mod_2_02_results_server,
    args = list(
      id = "results", hist_sim = reactiveVal(step2_fixture_hist()),
      saved_scenarios = reactiveVal(step2_fixture_scenarios()), selected_hist = reactiveVal(NULL),
      selected_weather = reactiveVal(step2_tables_weather()), tabset_id = "step2_output_tabs"
    ),
    {
      session$setInputs(
        cmp_agg_method = method, cmp_deviation = "none", ensemble_band = STEP2_SUMMARY_ENSEMBLE_BAND,
        uncertainty_band = "p10_p90", pov_line = 3, bandwidth_p0 = 0.05
      )
      session$elapse(500)
      session$flushReact()
      out <<- list(
        hist = hist_agg_rv()$weighted[[method]],
        scn = lapply(scenario_agg_rv(), function(s) s$weighted[[method]]),
        bands = pointrange_bands_rv(), headline_bands = headline_bands_rv(),
        timeseries = timeseries_curves_rv(), threshold = threshold_table_rv(),
        variance = variance_breakdown_rv(), adverse_dot = adverse_dot_data_rv(),
        cards = headline_cards_data_rv(), incidence = incidence_data_rv(),
        threshold_df = threshold_table_df()
      )
    }
  )
  out
}

test_that("the batch views equal the Results module's for every metric", {
  agg <- step2_fixture_agg()
  hs <- step2_fixture_hist()
  scenarios <- step2_fixture_scenarios()
  expect_identical(agg$methods[1:2], c("mean", "median"))
  expect_identical(agg$pov_line, 3)
  expect_identical(agg$weight_key, "weighted")
  for (m in agg$methods) {
    mod <- results_module_views(m)
    core <- step2_method_views(agg, hs, scenarios, m, step2_tables_weather())
    # The aggregation tables themselves, then every view built from them.
    expect_identical(agg$hist[[m]], mod$hist, info = m)
    expect_identical(lapply(agg$scn, `[[`, m), mod$scn, info = m)
    expect_identical(core$bands, mod$bands, info = m)
    expect_identical(core$headline_bands, mod$headline_bands, info = m)
    expect_identical(core$timeseries, mod$timeseries, info = m)
    expect_identical(core$threshold, mod$threshold, info = m)
    expect_identical(core$variance, mod$variance, info = m)
    expect_identical(core$adverse_dot, mod$adverse_dot, info = m)
    expect_identical(core$cards, mod$cards, info = m)
  }
  inc <- results_module_views("mean")$incidence
  expect_identical(step2_incidence_all(hs, scenarios), inc)
  expect_gt(nrow(inc), 0L)
})

test_that("the module's threshold table is the core's, with the run summary", {
  mod <- results_module_views("mean")
  agg <- step2_fixture_agg()
  thr <- step2_method_views(agg, step2_fixture_hist(), step2_fixture_scenarios(), "mean")$threshold
  expect_identical(
    step2_threshold_df(thr, "mean", step2_fixture_outcome(), step2_fixture_hist()$sim_summary),
    mod$threshold_df
  )
  expect_null(step2_threshold_df(NULL, "mean", NULL))
})

# annual ----

test_that("annual has one row per scenario, metric, member and year", {
  agg <- step2_fixture_agg()
  a <- step2_annual_table(agg)
  expect_identical(names(a), c(
    "policy_id", "scenario", "metric", "member", "sim_year", "value", "sd", "sd_resid", "var_within",
    "var_across", "weighted"
  ))
  expect_true(all(is.na(a$policy_id)))
  expect_type(a$sim_year, "integer")
  expect_true(all(a$weighted))
  expect_setequal(a$scenario, c("Historical", "SSP2-4.5 / 2030-2050", "SSP5-8.5 / 2030-2050"))
  expect_setequal(a$metric, agg$methods)
  # 22 historical years, 21 years of 3 and 2 members.
  m <- a[a$metric == "mean", ]
  expect_identical(sum(m$scenario == "Historical"), 22L)
  expect_identical(sum(m$scenario == "SSP2-4.5 / 2030-2050"), 63L)
  expect_identical(sum(m$scenario == "SSP5-8.5 / 2030-2050"), 42L)
  expect_setequal(m$member[m$scenario == "SSP2-4.5 / 2030-2050"], paste0("model_", 1:3))
  expect_identical(unique(m$member[m$scenario == "Historical"]), "Historical")

  # The stored values are the unnested aggregation tables.
  tbl <- agg$scn[["SSP2-4.5 / 2030-2050"]]$mean
  one <- m[m$scenario == "SSP2-4.5 / 2030-2050" & m$sim_year == 2035L, ]
  k <- which(tbl$sim_year == 2035L)
  expect_identical(one$value, unname(tbl$value_all[[k]]))
  expect_identical(one$sd, unname(tbl$value_all_sd[[k]]))
  expect_identical(one$member, tbl$model_id[[k]])
  expect_true(all(one$var_within == tbl$var_within[[k]]))
  expect_true(all(one$var_across == tbl$var_across[[k]]))
  # The mean of the members is the year's value in the aggregation table.
  by_year <- tapply(m$value[m$scenario == "SSP2-4.5 / 2030-2050"],
    m$sim_year[m$scenario == "SSP2-4.5 / 2030-2050"], mean)
  expect_equal(as.numeric(by_year), tbl$value, tolerance = 1e-12)
  # Raw values: no coefficient gradients, nothing rounded.
  expect_false(any(grepl("F_agg", names(a))))
})

test_that("annual is empty-safe and deterministic", {
  hs <- step2_fixture_hist()
  hist_only <- step2_run_aggregates(hs, list(), skip_coef = FALSE)
  a <- step2_annual_table(hist_only)
  expect_identical(unique(a$scenario), "Historical")
  expect_identical(step2_annual_table(step2_fixture_agg()), step2_annual_table(step2_fixture_agg()))
  none <- step2_annual_table(list(hist = list(), scn = list()))
  expect_null(none)
})

# summary ----

test_that("summary holds the stored views of every metric", {
  agg <- step2_fixture_agg()
  hs <- step2_fixture_hist()
  sc <- step2_fixture_scenarios()
  s <- step2_summary_table(agg, hs, sc, step2_tables_weather())
  expect_identical(names(s), c(
    "policy_id", "scenario", "metric", "section", "measure", "group", "return_period", "estimate",
    "lo", "hi", "n", "text"
  ))
  expect_true(all(is.na(s$policy_id)))
  expect_setequal(s$section, c(
    "expected", "adverse_year", "adverse_dot", "uncertainty", "headline", "incidence"
  ))
  expect_setequal(s$metric[s$section != "incidence"], agg$methods)
  expect_true(all(is.na(s$metric[s$section == "incidence"])))

  views <- step2_method_views(agg, hs, sc, "mean", step2_tables_weather())
  # Expected outcome: the headline centre with the inter-annual and inter-model bands.
  e <- s[s$metric == "mean" & s$section == "expected" & s$group == "interannual", ]
  hb <- views$headline_bands
  expect_identical(e$scenario, hb$scenario)
  expect_identical(e$estimate, hb$value)
  expect_identical(e$lo, hb$interann_lo)
  expect_identical(e$hi, hb$interann_hi)
  expect_identical(e$n, as.numeric(hb$n_models))
  i <- s[s$metric == "mean" & s$section == "expected" & s$group == "intermodel", ]
  expect_identical(i$lo, hb$intermod_lo)
  # The ensemble band is stored, not collapsed to the median.
  fut <- i[i$scenario != "Historical", ]
  expect_true(all(fut$lo < fut$hi))

  # Adverse years: one coefficient band per return period, plus ensemble and
  # pooled bands for the scenarios.
  thr <- views$threshold
  a <- s[s$metric == "mean" & s$section == "adverse_year", ]
  h <- a[a$scenario == "Historical", ]
  expect_setequal(h$group, "coefficient")
  expect_setequal(h$return_period, thr$rp_name[thr$scenario == "Historical"])
  f <- a[a$scenario == "SSP2-4.5 / 2030-2050", ]
  expect_setequal(f$group, c("coefficient", "ensemble", "pooled"))
  rp <- f[f$return_period == "1:20", ]
  d <- thr[thr$scenario == "SSP2-4.5 / 2030-2050" & thr$rp_name == "1:20", ]
  at <- function(estimate) unname(d$absolute_value[d$Estimate == estimate])
  expect_identical(rp$estimate, rep(at("Equal-model mean"), 3L))
  expect_identical(rp$lo[rp$group == "coefficient"], at("Coef P10"))
  expect_identical(rp$hi[rp$group == "ensemble"], at("Ensemble P90"))

  # Uncertainty sources and the dot plot.
  u <- s[s$metric == "mean" & s$section == "uncertainty", ]
  expect_setequal(u$measure, c("var_coef", "var_resid", "var_within", "var_across"))
  expect_identical(u$estimate[u$measure == "var_coef"], views$variance$var_coef)
  dot <- s[s$metric == "mean" & s$section == "adverse_dot", ]
  expect_setequal(dot$measure, as.character(views$adverse_dot$rp_label))

  # Headline cards: the focus scenario is the first one; the simulation count
  # is a count, not a historical value.
  hl <- s[s$metric == "mean" & s$section == "headline", ]
  expect_identical(unique(hl$scenario), "SSP2-4.5 / 2030-2050")
  cards <- step2_headline_df(views$cards)
  expect_identical(
    hl$estimate[hl$measure == "Expected change" & hl$group == "difference"],
    cards$Difference_native[cards$Metric == "Expected change"]
  )
  expect_identical(
    hl$text[hl$measure == "Expected change" & hl$group == "focus"],
    cards$Value[cards$Metric == "Expected change"]
  )
  expect_identical(hl$group[hl$measure == "Simulation years"], "count")

  # Incidence by baseline decile, once per scenario.
  inc <- s[s$section == "incidence", ]
  expect_setequal(inc$group, paste0("decile_", 1:10))
  expect_setequal(inc$scenario, names(sc))
})

test_that("summary of a historical-only run has no scenario rows", {
  hs <- step2_fixture_hist()
  agg <- step2_run_aggregates(hs, list(), skip_coef = FALSE)
  s <- step2_summary_table(agg, hs, list(), NULL)
  expect_identical(unique(s$scenario), "Historical")
  expect_false("incidence" %in% s$section)
  expect_true("headline" %in% s$section)
  expect_true(all(s$group[s$section == "adverse_year"] == "coefficient"))
})

# sim_weather ----

test_that("sim_weather lists the scenarios, their members and the weather support", {
  sc <- step2_fixture_scenarios()
  w <- step2_sim_weather_table(sc)
  expect_identical(names(w), c("scenario", "section", "member", "variable", "statistic", "value", "text"))
  expect_setequal(w$section, c("scenario", "members", "support"))
  s <- w[w$scenario == "SSP5-8.5 / 2030-2050", ]
  expect_identical(s$value[s$statistic == "period_start"], 2030)
  expect_identical(s$value[s$statistic == "n_models"], 2)
  expect_setequal(s$member[s$section == "members"], c("model_1", "model_2"))

  # The support rows are the pooled summary the Diagnostics tab shows.
  mod <- NULL
  testServer(
    mod_2_03_diagnostics_server,
    args = list(
      id = "diagnostics", hist_sim = reactiveVal(step2_fixture_hist()),
      saved_scenarios = reactiveVal(sc), survey_weather = reactiveVal(NULL),
      selected_weather = reactiveVal(step2_tables_weather()), tabset_id = "step2_output_tabs"
    ),
    {
      session$setInputs(diag_weather_vars = "pr", diag_weather_scenario = "all")
      session$flushReact()
      mod <<- weather_support_data()
    }
  )
  expect_identical(nrow(mod), 2L)
  for (label in mod$scenario) {
    support <- w[w$section == "support" & w$scenario == label & w$variable == "pr", ]
    row <- mod[mod$scenario == label, ]
    for (f in c(
      "n_reference", "n_scenario", "robust_lo", "robust_hi", "outside_n", "outside_share",
      "n_members", "max_member_share"
    )) {
      expect_identical(support$value[support$statistic == f], as.numeric(row[[f]]), info = f)
    }
    expect_identical(support$value[support$statistic == "warning"], as.numeric(row$warning))
    expect_identical(support$text[support$statistic == "warning_rule"], row$warning_rule)
  }
  expect_null(step2_sim_weather_table(list()))
})

test_that("a run without scenario support still has its periods and members", {
  sc <- step2_fixture_scenarios()
  sc[[1]]$weather_support <- NULL
  w <- step2_sim_weather_table(sc)
  expect_false(any(w$section == "support" & w$scenario == names(sc)[1]))
  expect_true(any(w$section == "members" & w$scenario == names(sc)[1]))
})

test_that("step2_batch_tables builds the three tables of an annotated run", {
  res <- list(hist_sim_result = step2_fixture_hist(), new_scenarios = step2_fixture_scenarios())
  t <- step2_batch_tables(res, skip_coef = FALSE, selected_weather = step2_tables_weather())
  expect_named(t, c("annual", "summary", "sim_weather"))
  expect_identical(t$annual, step2_annual_table(step2_fixture_agg()))
  expect_identical(t, step2_batch_tables(res, FALSE, step2_tables_weather()))
})


# F2: the residual variance is its own component ----

f2_table <- function(resid = c(0.04, 0.09)) {
  F_mat <- rbind(c(0.3, 0.4), c(0, 0.5)) # coefficient variance 0.25 for both members
  tibble::tibble(
    sim_year = 2030L, value = 1, model_id = list(c("a", "b")), value_all = list(c(1, 2)),
    value_all_sd = list(sqrt(0.25 + resid)), var_resid_all = list(resid),
    F_agg_all = list(F_mat), var_within = 0, var_across = 0
  )
}

test_that("the breakdown separates the residual variance from the coefficient variance", {
  mm <- function(tbl) NULL
  b <- step2_variance_breakdown(list(Historical = f2_table()), mm)
  expect_equal(b$var_coef, 0.25)
  expect_equal(b$var_resid, mean(c(0.04, 0.09)))
  # Without the column the whole `value_all_sd` is coefficient variance, as before.
  old <- f2_table()
  old$var_resid_all <- NULL
  b0 <- step2_variance_breakdown(list(Historical = old), mm)
  expect_equal(b0$var_coef, mean(0.25 + c(0.04, 0.09)))
  expect_equal(b0$var_resid, 0)
})

test_that("a contrast replaces the coefficient part and keeps the stored residual variance", {
  tbl <- f2_table()
  out <- step2_contrast_sd(tbl, F_ref = c(0.3, 0.4))
  expect_equal(out$value_all_sd[[1]], sqrt(c(0, 0.09 + 0.01) + c(0.04, 0.09)))
  # The same result when the column is absent and the residual is derived.
  tbl$var_resid_all <- NULL
  expect_equal(step2_contrast_sd(tbl, F_ref = c(0.3, 0.4))$value_all_sd[[1]], out$value_all_sd[[1]])
})

test_that("the variance chart labels the coefficient bar by reference and adds a residual bar", {
  vb <- data.frame(
    scenario = "Historical", var_coef = 1, var_resid = 0.5, var_within = 4, var_across = 0,
    is_historical = TRUE
  )
  ch <- echart_variance_contribution(vb, reference = "mean")
  nm <- vapply(ch$x$opts$series, `[[`, "", "name")
  expect_true("Residual draws" %in% nm)
  expect_true("Coefficient uncertainty (difference from historical mean)" %in% nm)
  vb$var_resid <- 0
  nm0 <- vapply(echart_variance_contribution(vb)$x$opts$series, `[[`, "", "name")
  expect_false("Residual draws" %in% nm0)
  expect_true("Coefficient uncertainty (level)" %in% nm0)
})

test_that("a median reference adds its own residual variance to a contrast, the mean reference does not (F1)", {
  ht <- tibble::tibble(
    sim_year = 1991:1993, value = c(1, 2, 3),
    F_agg_all = list(matrix(c(0.1, 0.2), 1), matrix(c(0.3, 0.4), 1), matrix(c(0.5, 0.6), 1)),
    var_resid_all = list(0.01, 0.04, 0.09)
  )
  med <- step2_hist_f_ref(ht, "median")
  expect_equal(as.numeric(med), c(0.3, 0.4))
  expect_equal(attr(med, "var_resid"), 0.04)
  expect_null(attr(step2_hist_f_ref(ht, "mean"), "var_resid"))
  scen <- f2_table(resid = c(0.04, 0.09))
  by_median <- step2_contrast_sd(scen, med)$value_all_sd[[1]]
  by_median_wo <- step2_contrast_sd(scen, as.numeric(med))$value_all_sd[[1]]
  expect_equal(by_median^2 - by_median_wo^2, rep(0.04, 2))
})

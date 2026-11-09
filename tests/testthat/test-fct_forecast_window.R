window_fixture_scenario <- function() {
  members <- lapply(1:5, function(i) step2_fixture_pipe(300L + i, 2026L, 3.6 + 0.1 * i))
  names(members) <- paste0("member_", 0:4)
  reference <- lapply(1:6, function(i) step2_fixture_pipe(400L + i, 1990L + i, 3.8 + 0.05 * i))
  names(reference) <- paste0("refyear_", 1991:1996)
  list(
    so = step2_fixture_outcome(), pipelines = members, reference_pipelines = reference, n_models = 5L,
    forecast = list(
      forecast_months = as.Date(c("2026-11-01", "2026-12-01", "2027-01-01")), reference_years = 1991:1996
    )
  )
}
window_fixture_label <- "Seasonal forecast / Nov 2026 - Jan 2027 (October 2026 run)"

test_that("the window member label is a forecast colour but not a members-as-models forecast", {
  lab <- .step2_window_forecast_label(window_fixture_label)
  expect_identical(lab, "Forecast (Nov 2026 - Jan 2027)")
  expect_false(.step2_is_forecast_scenario(lab))
  expect_true(.step2_is_window_forecast(lab))
  expect_identical(.step2_is_forecast_like(c(lab, window_fixture_label, "SSP2-4.5 / 2030-2050")), c(TRUE, TRUE, FALSE))
  expect_identical(.step2_window_reference_label(window_fixture_scenario()), "Historical (Nov - Jan)")
})

test_that("window series lay out reference years and members as one sample each, as placement aggregates them", {
  sc <- window_fixture_scenario()
  so <- step2_fixture_outcome()
  w <- step2_window_series(sc, window_fixture_label, "mean", so, "none", TRUE, 3, seed = 123L)
  expect_identical(w$label, "Forecast (Nov 2026 - Jan 2027)")
  expect_identical(w$historical$sim_year, 1991:1996)
  expect_identical(unique(unlist(w$historical$model_id)), "Historical")
  expect_identical(w$members$sim_year, 1:5)
  expect_identical(unique(unlist(w$members$model_id)), w$label)
  expect_identical(w$member_ids, names(sc$pipelines))
  pl <- step2_forecast_placement(sc, "mean", so, "none", TRUE, 3, seed = 123L)
  expect_equal(w$historical$value, pl$reference$value[order(pl$reference$year)])
  expect_equal(w$members$value, pl$members$value)
  expect_identical(dim(by_model_matrix(w$historical)$vals), c(1L, 6L))
  expect_identical(dim(by_model_matrix(w$members)$vals), c(1L, 5L))
  # Members are one sample of units: the annual views give them a spread, not a member-as-model collapse.
  series <- stats::setNames(list(w$historical, w$members), c("Historical", w$label))
  bands <- step2_pointrange_bands(series, c(lo = 0.1, hi = 0.9))
  expect_true(all(is.finite(bands$interann_lo)) && all(bands$interann_hi > bands$interann_lo))
  curves <- step2_timeseries_curves(series)
  expect_identical(as.integer(table(curves$scenario)[c("Historical", w$label)]), c(6L, 5L))
  expect_null(step2_window_series(list(pipelines = sc$pipelines), window_fixture_label, "mean", so, "none", TRUE, 3))
})

test_that("placement read from the window series matches the placement of the pipelines", {
  sc <- window_fixture_scenario()
  so <- step2_fixture_outcome()
  pl <- step2_forecast_placement(sc, "mean", so, "none", TRUE, 3, seed = 123L)
  for (skip_coef in c(TRUE, FALSE)) {
    w <- step2_window_series(sc, window_fixture_label, "mean", so, "none", skip_coef, 3, seed = 123L)
    out <- step2_window_placement(w, "mean", so)
    expect_identical(out$summary, pl$summary)
    expect_identical(out$members, pl$members)
    expect_identical(out$n_reference, pl$n_reference)
    expect_equal(out$reference, pl$reference[order(pl$reference$year), ], ignore_attr = TRUE)
  }
})

test_that("headline cards in the window scope read the shift against the reference-year spread", {
  sc <- window_fixture_scenario()
  so <- step2_fixture_outcome()
  w <- step2_window_series(sc, window_fixture_label, "mean", so, "none", TRUE, 3, seed = 123L)
  series <- stats::setNames(list(w$historical, w$members), c("Historical", w$label))
  bands <- step2_headline_bands(step2_pointrange_bands(series, c(lo = 0.5, hi = 0.5)), series)
  cards <- step2_headline_cards(
    bands, hist_sim = list(so = so), saved_scenarios = stats::setNames(list(sc), w$label), method = "mean",
    timeseries_curves = step2_timeseries_curves(series)
  )
  expect_identical(cards[[1L]]$label, "Expected target-window outcome")
  expect_identical(cards[[3L]]$label, "Signal vs noise")
  ref <- w$historical$value
  expect_equal(cards[[3L]]$snr_native, abs(mean(w$members$value) - mean(ref)) / stats::sd(ref))
  expect_equal(cards[[3L]]$member_spread_ratio_native, stats::sd(w$members$value) / stats::sd(ref))
  expect_identical(cards[[4L]]$label, "Forecast member range")
  expect_equal(unname(cards[[4L]]$value_range_native), range(w$members$value))
  expect_identical(cards[[5L]]$value_native, 5)
})

test_that("relabelling names the Historical row by its target months in data, text and axis formatters", {
  ref <- "Historical (Nov - Jan)"
  x <- list(
    series = list(list(name = "Historical"), list(name = "Historical mean")),
    note = "Difference from historical median",
    formatter = htmlwidgets::JS('function(v){ var m = {"1":"Historical","2":"SSP"}; return m[v]; }'),
    df = data.frame(scenario = factor(c("Historical", "SSP")), Estimate = c("Single historical estimate", "x"))
  )
  out <- .step2_window_relabel(x, ref)
  expect_identical(out$series[[1L]]$name, ref)
  expect_identical(out$series[[2L]]$name, "Historical mean")
  expect_identical(out$note, "Difference from historical median")
  expect_s3_class(out$formatter, "JS_EVAL")
  expect_match(out$formatter, paste0('"1":"', ref, '"'), fixed = TRUE)
  expect_identical(levels(out$df$scenario), c(ref, "SSP"))
  expect_identical(out$df$Estimate, c("Central estimate", "x"))
  expect_s3_class(.step2_window_relabel(echart_blank("Historical"), ref), "htmlwidget")
})

test_that("the forecast position on the Historical exceedance curve uses the curve's plotting positions", {
  ref <- c(1, 2, 3, 4, 5)
  # Weibull positions m / (n + 1) = m / 6. Lower is worse: the most adverse year (1) sits at p = 1/6, the next at 2/6.
  pos <- .step2_window_exceedance_position(ref, c(2, 2, 2), "low")
  expect_equal(unname(pos$p), rep(2 / 6, 3L))
  expect_equal(c(pos$p_min, pos$p_max), c(1 / 6, 5 / 6))
  pos <- .step2_window_exceedance_position(ref, seq(1.5, 2.5, length.out = 11L), "low")
  expect_equal(pos$p[["mid"]], 2 / 6)
  expect_equal(pos$value[["mid"]], 2)
  # Higher is worse: 5 is the most adverse year.
  expect_equal(.step2_window_exceedance_position(ref, 5, "high")$p[["mid"]], 1 / 6)
  # Beyond the observed range: the end probability, flagged.
  beyond <- .step2_window_exceedance_position(ref, 0, "low")
  expect_equal(beyond$p[["mid"]], 1 / 6)
  expect_true(beyond$beyond)
  expect_false(.step2_window_exceedance_position(ref, 1, "low")$beyond)
  expect_null(.step2_window_exceedance_position(1, 2, "low"))
  e <- .step2_window_exceedance_overlay(echart_blank("x"), .step2_window_exceedance_position(ref, 4.9, "low"))
  over <- e$x$opts$series[[length(e$x$opts$series)]]
  expect_identical(over$name, "forecast__position")
  expect_match(over$markLine$data[[1L]]$label$formatter, "better than the median year")
  expect_equal(over$markLine$data[[1L]]$xAxis, 0.55)
})

test_that("the overlay labels the far tail by rank, not by an interpolated 1-in-X", {
  ref <- c(1, 2, 3, 4, 5)
  label <- function(member, tail = "low") {
    pos <- .step2_window_exceedance_position(ref, member, tail, band_q = NULL)
    over <- .step2_window_exceedance_overlay(echart_blank("x"), pos)$x$opts$series
    over[[length(over)]]$markLine$data[[1L]]$label$formatter
  }
  expect_match(label(0), "Forecast median: beyond every reference year (rarer than 1 in 6)", fixed = TRUE)
  expect_match(label(6, "high"), "beyond every reference year (rarer than 1 in 6)", fixed = TRUE)
  expect_match(label(1.5), "worse than 4 of 5 reference years", fixed = TRUE)
  expect_match(label(2), "about 1 in 3.0", fixed = TRUE)
})

test_that("the window adverse chart keeps the Historical levels and adds one Forecast row with the member band", {
  dot <- tibble::tibble(
    scenario = c("Historical", "Historical", "X"), is_historical = c(TRUE, TRUE, FALSE),
    rp_label = factor(c("Expected", "Adverse 1-in-10", "Expected"), levels = c("Adverse 1-in-10", "Expected")),
    value = c(4, 3.5, 4.2), intermod_lo = NA_real_, intermod_hi = NA_real_
  )
  out <- .step2_window_adverse_dots(dot, 1:11, "Forecast (Nov 2026 - Jan 2027)")
  expect_identical(levels(out$rp_label), c("Forecast", "Adverse 1-in-10", "Expected"))
  fc <- out[!out$is_historical, ]
  expect_identical(nrow(fc), 1L)
  expect_identical(as.character(fc$rp_label), "Forecast")
  expect_equal(c(fc$intermod_lo, fc$value, fc$intermod_hi), c(2, 6, 10))
  e <- echart_step2_adverse_dot(out, "Mean")
  expect_s3_class(e, "htmlwidget")
  # The Forecast row has no Expected-row marker, so its label sits on its own marker.
  labelled <- unlist(lapply(e$x$opts$series, function(s) {
    vapply(s$data, function(d) if (is.list(d) && isTRUE(d$label$show)) as.character(d$label$formatter) else NA_character_,
      character(1))
  }))
  expect_true("Forecast (Nov 2026 - Jan 2027)" %in% labelled)
})

test_that("the window views run the annual builders on the target-month samples with their own baseline", {
  sc <- window_fixture_scenario()
  so <- step2_fixture_outcome()
  w <- step2_window_series(sc, window_fixture_label, "mean", so, "none", TRUE, 3, seed = 123L)
  expect_identical(w$months_label, "Nov - Jan")
  expect_identical(w$scenario_label, window_fixture_label)
  v <- step2_window_views(w, "mean", so, scenario = sc, hist_sim = list(so = so))
  expect_identical(sort(unique(v$curves$scenario)), sort(c("Historical", w$label)))
  expect_identical(sum(v$dots$rp_label == "Forecast"), 1L)
  fc <- .step2_is_window_forecast(v$variance$scenario)
  expect_identical(v$variance$var_within[fc], 0)
  expect_gt(v$variance$var_across[fc], 0)
  expect_identical(nrow(v$exceedance), 6L)
  # Weibull: the least adverse of 6 reference years sits at 6 / 7
  expect_equal(max(v$exceedance$exceed_prob), 6 / 7)
  expect_identical(v$cards[[3L]]$label, "Signal vs noise")
  # Deviation: the Historical mean of the same months is the baseline of this group.
  d <- step2_window_views(w, "mean", so, deviation = "mean", scenario = sc, hist_sim = list(so = so))
  expect_equal(d$ref, mean(w$historical$value))
  expect_equal(mean(d$curves$value[d$curves$scenario == "Historical"]), 0)
  expect_null(step2_window_views(NULL, "mean", so))
})

test_that("the member band follows the ensemble-spread control and is off with no band", {
  ref <- c(1, 2, 3, 4, 5)
  pos <- .step2_window_exceedance_position(ref, 1:11, "low", band_q = NULL)
  expect_true(is.na(pos$p[["lo"]]) && is.na(pos$p[["hi"]]) && is.finite(pos$p[["mid"]]))
  over <- .step2_window_exceedance_overlay(echart_blank("x"), pos)$x$opts$series
  expect_null(over[[length(over)]]$markArea)
  full <- .step2_window_exceedance_position(ref, 1:11, "low", band_q = c(lo = 0, hi = 1))
  expect_equal(unname(full$value[c("lo", "hi")]), c(1, 11))
  dot <- tibble::tibble(
    scenario = "Historical", is_historical = TRUE, rp_label = factor("Expected"), value = 4,
    intermod_lo = NA_real_, intermod_hi = NA_real_
  )
  out <- .step2_window_adverse_dots(dot, 1:11, "Forecast (x)", band_q = NULL)
  expect_true(is.na(out$intermod_lo[!out$is_historical]))
  expect_equal(out$value[!out$is_historical], 6)
})

test_that("the Step 3 window views pair baseline and policy for Historical and the forecast", {
  sc <- window_fixture_scenario()
  pol <- sc
  shift <- function(p) {
    p$y_point <- p$y_point + 0.1
    p
  }
  pol$pipelines <- lapply(pol$pipelines, shift)
  pol$reference_pipelines <- lapply(pol$reference_pipelines, shift)
  so <- step2_fixture_outcome()
  wb <- step2_window_series(sc, window_fixture_label, "mean", so, "none", TRUE, 3, seed = 123L)
  wp <- step2_window_series(pol, window_fixture_label, "mean", so, "none", TRUE, 3, seed = 123L)
  v <- step3_window_views(wb, wp, "mean", so, band_adverse = c(lo = 0.1, hi = 0.9))
  expect_identical(sort(unique(v$curves$source)), c("Baseline", "Policy"))
  expect_identical(as.integer(table(v$curves$source)), c(11L, 11L))
  fc <- v$dots[!v$dots$is_historical, ]
  expect_identical(as.character(fc$rp_label), "Forecast")
  expect_gt(fc$policy_val, fc$baseline_val)
  expect_true(is.finite(fc$base_lo) && is.finite(fc$policy_hi))
  expect_true(all(v$dots$policy_val[v$dots$is_historical] > v$dots$baseline_val[v$dots$is_historical]))
  expect_gt(v$effect$member_median, 0)
  expect_gt(v$effect$reference_median, 0)
  expect_identical(nrow(v$exceedance), 6L)
  # Both arms' members are placed on the no-policy Historical curve.
  expect_true(v$position$policy$p[["mid"]] >= v$position$baseline$p[["mid"]])
  cards <- .step3_window_cards(v, metric_metadata("mean", so))
  expect_length(cards, 3L)
  # The fixture has 6 historical years and a 1-in-10 level needs 9, so the shares are not available
  expect_true(is.na(v$effect$share_worse_baseline) && is.na(v$effect$share_worse_policy))
  expect_match(cards[[3L]]$value, "n/a")
  expect_null(step3_window_views(wb, NULL, "mean", so))
})

test_that("merged charts order rows so that neighbours are the valid comparisons", {
  ref <- "Historical (Nov - Jan)"
  fc <- "Forecast (Nov 2026 - Jan 2027)"
  ssp <- "SSP2-4.5 / 2030-2050"
  expect_identical(.step2_scenario_order(c(ssp, "Historical", ref, fc)), c(fc, ref, "Historical", ssp))
  # Without the target-month Historical, the order is unchanged.
  expect_identical(.step2_scenario_order(c(ssp, "Historical", fc)), c("Historical", fc, ssp))
  expect_true(.step2_is_window_reference(ref))
  expect_false(any(.step2_is_window_reference(c("Historical", "Historical mean", fc, ssp))))
  expect_true(.step2_is_forecast_like(ref))
})

test_that("a merged chart keeps annual and target-month series apart, each on its own baseline", {
  sc <- window_fixture_scenario()
  so <- step2_fixture_outcome()
  w <- step2_window_series(sc, window_fixture_label, "mean", so, "none", TRUE, 3, seed = 123L)
  ref <- w$reference_label
  ssp <- "SSP2-4.5 / 2030-2050"
  v <- step2_window_views(w, "mean", so, deviation = "mean", scenario = sc, hist_sim = list(so = so))
  annual <- tibble::tibble(
    scenario = rep(c("Historical", ssp), each = 3L), model_id = rep(c("Historical", "m1"), each = 3L),
    sim_year = rep(1:3, 2L), value = c(-1, 0, 1, 2, 3, 4), is_historical = rep(c(TRUE, FALSE), each = 3L)
  )
  out <- .step2_window_merge(annual, v$curves, ref)
  expect_identical(unique(out$scenario), c(w$label, ref, "Historical", ssp))
  expect_identical(sum(out$is_historical), 3L)
  expect_false(any(out$is_historical[out$scenario == ref]))
  expect_equal(mean(out$value[out$scenario == ref]), 0)
  expect_equal(mean(out$value[out$scenario == "Historical"]), 0)
  expect_identical(.step2_window_merge(annual, NULL, ref), annual)
  e <- echart_annual_distribution(out)
  expect_s3_class(e, "htmlwidget")
  draws <- Filter(function(s) identical(s$type, "scatter") && identical(s$name, ref), e$x$opts$series)
  expect_identical(draws[[1L]]$itemStyle$color, .wise_forecast_reference)
  # The dashed reference line stays on the annual Historical mean, not pooled with the target-month series.
  relabelled <- .step2_window_relabel(e, .STEP2_ANNUAL_LABEL, text = character(0))
  names_out <- unlist(lapply(relabelled$x$opts$series, `[[`, "name"))
  expect_true(all(c(.STEP2_ANNUAL_LABEL, ref) %in% names_out))
  expect_false("Historical" %in% names_out)
})

test_that("the merged adverse chart shares return-period rows and keeps Forecast at the bottom", {
  ref <- "Historical (Nov - Jan)"
  fc <- "Forecast (Nov 2026 - Jan 2027)"
  lv <- c("Adverse 1-in-20", "Adverse 1-in-10", "Expected")
  annual <- tibble::tibble(
    scenario = rep(c("Historical", "SSP2-4.5 / 2030-2050"), each = 3L), is_historical = rep(c(TRUE, FALSE), each = 3L),
    rp_label = factor(rep(lv, 2L), levels = lv), value = c(3, 3.5, 4, 2.8, 3.3, 3.8),
    intermod_lo = NA_real_, intermod_hi = NA_real_
  )
  window <- .step2_window_adverse_dots(
    tibble::tibble(
      scenario = "Historical", is_historical = TRUE, rp_label = factor(lv[-1L], levels = lv[-1L]), value = c(3.2, 3.9),
      intermod_lo = NA_real_, intermod_hi = NA_real_
    ), 1:11, fc
  )
  out <- .step2_window_merge(annual, window, ref)
  expect_identical(levels(out$rp_label), c("Forecast", lv))
  expect_identical(as.character(out$rp_label[out$scenario == fc]), "Forecast")
  expect_identical(sum(out$scenario == ref), 2L)
  e <- echart_step2_adverse_dot(out, "Mean")
  series <- stats::setNames(e$x$opts$series, vapply(e$x$opts$series, `[[`, character(1L), "name"))
  expect_identical(series[[ref]]$itemStyle$color, .wise_forecast_reference)
  expect_identical(series[["Historical"]]$itemStyle$color, .wise_support)
})

test_that("the merged exceedance chart draws both Historical curves and anchors the forecast on its own", {
  ref <- "Historical (Nov - Jan)"
  annual <- tibble::tibble(
    scenario = "Historical", model_id = "Historical", rank = 1:3, welfare_val = c(1, 2, 3), coef_sd = 0.1,
    exceed_prob = c(0.1, 0.3, 0.5), is_historical = TRUE
  )
  window <- tibble::tibble(
    scenario = "Historical", model_id = "Historical", rank = 1:6, welfare_val = 2:7, coef_sd = 0.1,
    exceed_prob = rp_positions(6L), is_historical = TRUE
  )
  out <- .step2_window_merge(annual, window, ref)
  e <- echart_exceedance(out, "Mean", n_sim_years = 6, logit_x = TRUE, band_q = NULL,
    ensemble_band_q = c(lo = 0.1, hi = 0.9), p_max = 0.99)
  names_out <- vapply(e$x$opts$series, `[[`, character(1L), "name")
  expect_true(all(c("Historical", ref) %in% names_out))
  # One sample: no ensemble band for the target-month Historical.
  expect_false(any(grepl(paste0(ref, "__ensemble"), names_out, fixed = TRUE)))
  line <- e$x$opts$series[[match(ref, names_out)]]
  expect_identical(line$lineStyle$type, "dashed")
  expect_identical(line$lineStyle$color, .wise_forecast_reference)
  pos <- .step2_window_exceedance_position(2:7, c(3, 4, 5), "low", band_q = NULL)
  over <- .step2_window_exceedance_overlay(e, pos, x_max = 0.99)$x$opts$series
  point <- over[[length(over)]]$markPoint$data[[1L]]$coord
  expect_equal(c(point[[1L]], point[[2L]]), c(pos$p[["mid"]], pos$value[["mid"]]))
  expect_identical(over[[length(over)]]$markLine$data[[1L]]$label$position, "end")
  # Two lines on one chart (Step 3) stack their labels.
  stacked <- .step2_window_exceedance_overlay(e, pos, x_max = 0.99, label_offset = c(0, -13))$x$opts$series
  expect_identical(stacked[[length(stacked)]]$markLine$data[[1L]]$label$offset, c(0, -13))
})

test_that("the merged uncertainty chart lists the rows top-down in the merged order", {
  ref <- "Historical (Nov - Jan)"
  fc <- "Forecast (Nov 2026 - Jan 2027)"
  row <- function(scenario) {
    tibble::tibble(scenario = scenario, var_coef = 0.01, var_within = 0.04, var_across = 0.01)
  }
  out <- .step2_window_merge(rbind(row("Historical"), row("SSP2-4.5 / 2030-2050")), rbind(row("Historical"), row(fc)), ref)
  e <- echart_variance_contribution(out)
  expect_identical(unlist(e$x$opts$yAxis$data), rev(c(fc, ref, "Historical", "SSP2-4.5 / 2030-2050")))
  expect_identical(e$x$opts$series[[1L]]$name, "Inter-model / member spread")
})

test_that("the merged Step 3 charts keep baseline and policy of each series", {
  ref <- "Historical (Nov - Jan)"
  fc <- "Forecast (Nov 2026 - Jan 2027)"
  lv <- c("Adverse 1-in-10", "Expected")
  annual <- tibble::tibble(
    scenario = rep(c("Historical", "SSP2-4.5 / 2030-2050"), each = 2L), is_historical = rep(c(TRUE, FALSE), each = 2L),
    rp_label = factor(rep(lv, 2L), levels = lv), baseline_val = c(3, 4, 2.8, 3.8), policy_val = c(3.1, 4.1, 2.9, 3.9),
    base_lo = NA_real_, base_hi = NA_real_, policy_lo = NA_real_, policy_hi = NA_real_
  )
  window <- tibble::tibble(
    scenario = c("Historical", "Historical", fc), is_historical = c(TRUE, TRUE, FALSE),
    rp_label = factor(c(lv, "Forecast"), levels = c("Forecast", lv)), baseline_val = c(3.2, 4.2, 4.3),
    policy_val = c(3.3, 4.3, 4.4), base_lo = NA_real_, base_hi = NA_real_, policy_lo = NA_real_, policy_hi = NA_real_
  )
  out <- .step2_window_merge(annual, window, ref)
  e <- echart_step3_adverse_dot(out, "Mean")
  expect_s3_class(e, "htmlwidget")
  expect_identical(levels(out$rp_label), c("Forecast", lv))
  expect_identical(sum(out$is_historical), 2L)

  sc <- window_fixture_scenario()
  so <- step2_fixture_outcome()
  w <- step2_window_series(sc, window_fixture_label, "mean", so, "none", TRUE, 3, seed = 123L)
  v <- step3_window_views(w, w, "mean", so)
  expect_identical(unique(v$exceedance$source), "Baseline")
  merged <- .step2_window_merge(
    tibble::tibble(
      scenario = "Historical", source = c("Baseline", "Policy"), model_id = "Historical", rank = 1L, welfare_val = 1:2,
      coef_sd = 0.1, exceed_prob = 0.1, is_historical = TRUE
    ), v$exceedance, v$reference_label
  )
  chart <- echart_exceedance(merged, "Mean", n_sim_years = 6, band_q = NULL, p_max = 0.99)
  names_out <- vapply(chart$x$opts$series, `[[`, character(1L), "name")
  expect_true(paste(v$reference_label, "| Baseline") %in% names_out)
  labelled <- .step2_annual_relabel(chart)
  names_out <- vapply(labelled$x$opts$series, `[[`, character(1L), "name")
  expect_true("Historical (annual) | Baseline" %in% names_out)
  expect_false("Historical | Baseline" %in% names_out)
})

test_that("the annual relabel changes only the Historical label", {
  df <- data.frame(`Scenario / Period` = c("Historical", "SSP"), Estimate = "Single historical estimate", check.names = FALSE)
  out <- .step2_annual_relabel(df)
  expect_identical(out[["Scenario / Period"]], c("Historical (annual)", "SSP"))
  expect_identical(out$Estimate, rep("Single historical estimate", 2L))
  x <- list(mean = "Historical mean")
  expect_identical(.step2_annual_relabel(x)$mean, "Historical (annual) mean")
  expect_identical(.step2_annual_relabel(x, level = FALSE)$mean, "Historical mean")
})

test_that("window robustness data has one point per member and per reference year, on the deviation scale", {
  sc <- window_fixture_scenario()
  w <- step2_window_series(sc, window_fixture_label, "mean", step2_fixture_outcome(), "none", TRUE, 3, seed = 123L)
  out <- step2_window_robustness_data(w)
  expect_identical(sort(unique(out$scenario)), sort(c("Historical (Nov - Jan)", "Forecast (Nov 2026 - Jan 2027)")))
  expect_identical(sum(out$unit == "Forecast member"), 5L)
  expect_identical(sum(out$unit == "Reference year"), 6L)
  expect_true(all(is.na(out$n_weather_years)))
  expect_equal(sort(out$model_mean[out$unit == "Forecast member"]), sort(w$members$value))
  expect_equal(out$center[out$unit == "Reference year"][[1L]], mean(w$historical$value))

  dev <- step2_window_robustness_data(w, "mean")
  expect_equal(unique(dev$center[dev$unit == "Reference year"]), 0)
  expect_null(step2_window_robustness_data(NULL))
})

test_that("the robustness chart draws window rows in the forecast and history colours with a unit tooltip", {
  sc <- window_fixture_scenario()
  w <- step2_window_series(sc, window_fixture_label, "mean", step2_fixture_outcome(), "none", TRUE, 3, seed = 123L)
  ch <- echart_model_robustness(step2_window_robustness_data(w), "Mean welfare")
  pts <- ch$x$opts$series[[1L]]$data
  cols <- vapply(pts, function(p) p$itemStyle$color, character(1L))
  scen <- vapply(pts, `[[`, character(1L), "scenario")
  expect_identical(unique(cols[scen == "Forecast (Nov 2026 - Jan 2027)"]), .wise_forecast)
  expect_identical(unique(cols[scen == "Historical (Nov - Jan)"]), .wise_history)
  expect_null(pts[[1L]]$n_years)
  expect_match(paste(ch$x$opts$tooltip$formatter, collapse = " "), "d.unit", fixed = TRUE)
})

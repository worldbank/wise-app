

test_that("paired_effect_summary pools the coefficient error as the norm of the mean gradient", {
  eff <- tibble::tibble(
    sim_year = c(1L, 1L), model_id = c("a", "b"),
    baseline = 1, policy = 1.5, effect = 0.5, effect_sd = c(0.1, 0.1),
    effect_gradient = list(c(0.1, 0), c(-0.1, 0))
  )
  out <- paired_effect_summary(eff, center = "equal_model_mean")
  # Members' gradients point opposite ways: shared coefficient error cancels
  expect_equal(out$coef_sd, 0)
  same <- eff
  same$effect_gradient <- list(c(0.1, 0), c(0.1, 0))
  expect_equal(paired_effect_summary(same, center = "equal_model_mean")$coef_sd, 0.1)
})

test_that("scenario ordering keeps forecast between history and SSPs", {
  scenarios <- c("SSP5-8.5 / 2030-2050", "Seasonal forecast / Nov 2026 - Jan 2027 (2026-10 run)",
    "Historical", "SSP2-4.5 / 2030-2050")
  expect_identical(.step2_scenario_order(scenarios), c(
    "Historical", "Seasonal forecast / Nov 2026 - Jan 2027 (2026-10 run)",
    "SSP2-4.5 / 2030-2050", "SSP5-8.5 / 2030-2050"
  ))
})

test_that("forecast chart preparation uses its own key and forecast palette", {
  bands <- data.frame(
    scenario = c("Historical", "Seasonal forecast / Nov 2026 - Jan 2027 (2026-10 run)"),
    value = c(1, 2), interann_lo = c(0, NA), interann_hi = c(2, NA),
    intermod_lo = c(NA, 1.5), intermod_hi = c(NA, 2.5),
    coef_lo = c(0.5, 1.7), coef_hi = c(1.5, 2.3),
    is_historical = c(TRUE, FALSE), n_models = c(1L, 51L), stringsAsFactors = FALSE
  )
  prep <- .pointrange_prep(bands)
  expect_identical(prep$ordered_levels[1:2], c(
    "Historical", "Forecast\nNov 2026 - Jan 2027 (2026-10 run)"
  ))
  expect_identical(unname(prep$palette[["Forecast__Seasonal forecast / Nov 2026 - Jan 2027 (2026-10 run)"]]),
    .wise_forecast)
  forecast <- prep$df[prep$df$ssp_key == "Forecast", ]
  expect_true(is.na(forecast$interann_lo))
  expect_identical(forecast$intermod_lo, 1.5)
  expect_identical(forecast$coef_lo, 1.7)
  expect_no_error(cards <- step2_headline_cards(bands))
  expect_length(cards, 5L)
})

test_that("forecast headline cards read the member count without tibble warnings", {
  bands <- tibble::tibble(
    scenario = c("Historical", "Seasonal forecast / Nov 2026 - Jan 2027 (2026-10 run)"),
    value = c(1, 2), interann_lo = c(0, NA), interann_hi = c(2, NA),
    intermod_lo = c(NA, 1.5), intermod_hi = c(NA, 2.5),
    coef_lo = c(0.5, 1.7), coef_hi = c(1.5, 2.3),
    is_historical = c(TRUE, FALSE), n_models = c(1L, 51L)
  )
  expect_no_warning(cards <- step2_headline_cards(bands))
  expect_match(paste(unlist(cards), collapse = " "), "51 forecast members")
})

test_that("forecast cards compare with the same-window reference and show the placement", {
  bands <- tibble::tibble(
    scenario = c("Historical", "Seasonal forecast / Nov 2026 - Jan 2027 (2026-10 run)"),
    value = c(10, 8), interann_lo = c(8, NA), interann_hi = c(12, NA),
    intermod_lo = c(NA, 7), intermod_hi = c(NA, 9),
    coef_lo = c(9, 7.5), coef_hi = c(11, 8.5),
    is_historical = c(TRUE, FALSE), n_models = c(1L, 51L)
  )
  reference <- 1:20 / 2 + 3
  placement <- c(.forecast_placement_stats(c(4, 5, 6, 7, 8), reference, "low"),
    list(reference = data.frame(year = 1991:2010, value = reference), method = "mean", adverse_tail = "low"))
  expect_no_warning(cards <- step2_headline_cards(bands, forecast_placement = placement))
  # Comparator is the reference mean (8.25), not Historical (10).
  expect_equal(cards[[1L]]$value_native, c(mean(reference), 8))
  expect_equal(cards[[1L]]$change_native, 8 - mean(reference))
  expect_match(cards[[1L]]$note, "Same-window climatology")
  expect_false(grepl("Historical", cards[[1L]]$note))
  expect_identical(cards[[2L]]$label, "Placement in climatology")
  expect_match(cards[[2L]]$value, "% of members")
  expect_match(cards[[2L]]$info, "not a probability")
  # Without a placement, or in a deviation view, the cards keep the Historical comparator.
  plain <- step2_headline_cards(bands)
  expect_equal(plain[[1L]]$value_native, c(10, 8))
  dev <- step2_headline_cards(bands, forecast_placement = placement, deviation = "mean")
  expect_equal(dev[[1L]]$value_native, c(10, 8))
})

test_that("forecast cards warn when the target months are rare in the training data", {
  label <- "Seasonal forecast / Mar 2027 (2026-10 run)"
  bands <- tibble::tibble(
    scenario = c("Historical", label), value = c(10, 8), interann_lo = c(8, NA), interann_hi = c(12, NA),
    intermod_lo = c(NA, 7), intermod_hi = c(NA, 9), coef_lo = c(9, 7.5), coef_hi = c(11, 8.5),
    is_historical = c(TRUE, FALSE), n_models = c(1L, 51L)
  )
  rare <- setNames(list(list(training_months = list(share = 0, expected = 1 / 12))), label)
  common <- setNames(list(list(training_months = list(share = 0.09, expected = 1 / 12))), label)
  expect_match(step2_headline_cards(bands, saved_scenarios = rare)[[1L]]$basis_text,
    "0% of the model's training observations")
  expect_false(grepl("training observations",
    step2_headline_cards(bands, saved_scenarios = common)[[1L]]$basis_text))
})

test_that("the uncertainty-source chart names the member spread for forecast rows", {
  fc <- "Seasonal forecast / Nov 2026 - Jan 2027 (2026-10 run)"
  tbl <- data.frame(scenario = c("Historical", fc), var_within = c(1, 0), var_across = c(0, 0.5),
    var_coef = c(0.2, 0.3))
  names_of <- function(t) vapply(echart_variance_contribution(t)$x$opts$series, `[[`, "", "name")
  expect_true("Forecast member spread" %in% names_of(tbl))
  mixed <- rbind(tbl, data.frame(scenario = "SSP3-7.0 / 2025-2035", var_within = 1, var_across = 1, var_coef = 0.1))
  expect_true("Inter-model / member spread" %in% names_of(mixed))
  expect_true("Inter-model spread" %in% names_of(tbl[tbl$scenario == "Historical", ]))
})

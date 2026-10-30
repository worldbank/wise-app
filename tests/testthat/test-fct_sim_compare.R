

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

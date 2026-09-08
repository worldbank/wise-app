library(testthat)

test_that("metric metadata carries direction and adverse tail", {
  low <- wiseapp:::metric_metadata("headcount_ratio")
  high <- wiseapp:::metric_metadata("mean")
  expect_identical(low$direction, "lower_is_better")
  expect_identical(low$adverse_tail, "high")
  expect_identical(high$direction, "higher_is_better")
  expect_identical(high$adverse_tail, "low")
})

test_that("paired effects are zero for identical baseline and policy tables", {
  tbl <- tibble::tibble(
    sim_year = c(2020L, 2021L),
    model_id = list(c("m1"), c("m1")),
    value_all = list(1, 2),
    value_all_sd = list(0.1, 0.1),
    F_agg_all = list(matrix(1, nrow = 1L), matrix(1, nrow = 1L))
  )
  effects <- wiseapp:::paired_model_year_effects(tbl, tbl)
  expect_true(all(effects$effect == 0))
  expect_true(all(effects$effect_sd == 0))
  summary <- wiseapp:::paired_effect_summary(effects, scenario = "SSP2-4.5 / 2030-2040")
  expect_equal(summary$value, 0)
  expect_equal(summary$coef_lo, 0)
  expect_equal(summary$coef_hi, 0)
})

test_that("paired adverse effects use equal-probability arm quantiles", {
  effects <- tibble::tibble(
    model_id = rep(c("m1", "m2"), each = 4L),
    sim_year = rep(2018:2021, 2L),
    baseline = rep(c(1, 2, 3, 4), 2L),
    policy = rep(c(2, 3, 4, 5), 2L),
    effect = 1,
    effect_sd = 0
  )
  out <- wiseapp:::paired_equal_probability_effects(
    effects, c(`1-in-10` = 0.1, `1-in-5` = 0.2)
  )
  expect_true(all(abs(out$effect - 1) < 1e-12))
  expect_equal(sort(unique(out$probability)), c(0.1, 0.2))
})

test_that("variance display uses separate aligned bars", {
  p <- wiseapp:::plot_variance_contribution(tibble::tibble(
    scenario = "SSP2-4.5 / 2030-2040", var_coef = 1,
    var_within = 4, var_across = 9, is_historical = FALSE
  ))
  expect_s3_class(p, "ggplot")
  expect_true(any(vapply(p$layers, function(x) inherits(x$position, "PositionDodge"),
                         logical(1L))))
})

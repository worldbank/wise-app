test_that("members are placed in the reference years on the adverse side", {
  reference <- 1:20
  # Lower values are worse (adverse tail "low").
  out <- .forecast_placement_stats(c(1, 2, 10, 20, 25), reference, "low")
  expect_equal(out$members$p_adverse, c(1 / 20, 2 / 20, 10 / 20, 1, 1))
  expect_equal(out$members$return_period, c(NA, 10, 2, 1, 1))
  # 1-in-20 exceeds n / 2 = 10 years: beyond the observed range, not extrapolated.
  expect_identical(out$members$beyond, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(out$summary$n_beyond, 1L)
  expect_equal(out$summary$reference_median, 10.5)
  expect_equal(out$summary$member_median, 10)
  expect_equal(out$summary$reference_adverse_1in10, stats::quantile(reference, 0.1, names = FALSE))
  expect_equal(out$summary$share_worse_than_1in10, 0.4)
  expect_equal(out$summary$share_worse_than_median, 0.6)
  expect_equal(out$summary$median_member_return_period, 2)
  expect_equal(out$n_reference, 20L)
})

test_that("the high tail flips the adverse direction and a value past every year is beyond range", {
  out <- .forecast_placement_stats(c(0, 5, 100), 1:20, "high")
  expect_equal(out$members$p_adverse, c(1, 16 / 20, 0))
  expect_identical(out$members$beyond, c(FALSE, FALSE, TRUE))
  expect_true(is.na(out$members$return_period[[3L]]))
  expect_true(out$summary$median_member_beyond == FALSE)
})

test_that("non-finite members and an empty reference do not produce placements", {
  out <- .forecast_placement_stats(c(NA, 3), numeric(0), "low")
  expect_true(all(is.na(out$members$p_adverse)))
  expect_identical(out$n_reference, 0L)
  expect_true(is.na(out$summary$reference_median))
})

test_that("a scenario without reference pipelines gives no placement", {
  expect_null(step2_forecast_placement(list(pipelines = list(1)), "mean",
    list(type = "numeric", name = "welfare", transform = "none"), "none", TRUE, 3))
})

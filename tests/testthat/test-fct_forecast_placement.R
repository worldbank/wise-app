test_that("members are placed in the reference years on the adverse side", {
  reference <- 1:20
  # Lower values are worse (adverse tail "low"). Weibull positions: the value v of 1:20 has p = v / 21.
  out <- .forecast_placement_stats(c(0, 2, 10, 20, 25), reference, "low")
  expect_equal(out$members$p_adverse, c(1, 2, 10, 20, 20) / 21)
  # Resolved only from the second most adverse year (p >= 2 / 21); the member below every year is beyond the record.
  expect_equal(out$members$return_period, c(NA, 10.5, 2.1, 1.05, 1.05))
  expect_identical(out$members$beyond, c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_identical(out$summary$n_beyond, 1L)
  expect_equal(out$summary$reference_median, 10.5)
  expect_equal(out$summary$member_median, 10)
  # Type 6 at 0.1: adverse rank 21 / 10 = 2.1 of 20 years
  expect_equal(out$summary$reference_adverse_1in10, 2.1)
  expect_equal(out$summary$reference_adverse_1in10, stats::quantile(reference, 0.1, names = FALSE, type = 6))
  expect_equal(out$summary$share_worse_than_1in10, 0.4)
  expect_equal(out$summary$share_worse_than_median, 0.6)
  expect_equal(out$summary$median_member_return_period, 21 / 10)
  expect_equal(out$summary$median_member_p_adverse, 10 / 21)
  expect_equal(out$summary$median_member_n_worse, 10L)
  expect_equal(out$n_reference, 20L)
})

test_that("the high tail flips the adverse direction and a value past every year is beyond the record", {
  out <- .forecast_placement_stats(c(0, 5, 100), 1:20, "high")
  expect_equal(out$members$p_adverse, c(20, 16, 1) / 21)
  expect_identical(out$members$beyond, c(FALSE, FALSE, TRUE))
  expect_true(is.na(out$members$return_period[[3L]]))
  expect_true(out$summary$median_member_beyond == FALSE)
})

test_that("a record too short for a 1-in-10 level has no 1-in-10 share", {
  # The 1-in-10 level needs 9 years (adverse rank 0.1 (n + 1) >= 1)
  short <- .forecast_placement_stats(1:3, 1:8, "low")
  expect_true(is.na(short$summary$reference_adverse_1in10))
  expect_true(is.na(short$summary$share_worse_than_1in10))
  expect_identical(.forecast_placement_text(short)$value, "Not available")
  ok <- .forecast_placement_stats(1:3, 1:9, "low")
  expect_equal(ok$summary$reference_adverse_1in10, 1)
  expect_false(is.na(ok$summary$share_worse_than_1in10))
})

test_that("a member between the two most adverse years has a rank, not a return period", {
  out <- .forecast_placement_stats(c(19.5, 20), 1:20, "high")
  expect_equal(out$members$p_adverse, c(1.5, 1) / 21)
  expect_true(all(is.na(out$members$return_period)))
  expect_identical(out$members$beyond, c(FALSE, FALSE))
  expect_equal(out$summary$median_member_n_worse, 19L)
})

test_that("the median member text is a return period, a rank or beyond every year", {
  text <- function(members, tail = "high") {
    pl <- .forecast_placement_stats(members, 1:20, tail)
    .forecast_placement_text(pl)$median_text
  }
  expect_identical(text(rep(15.5, 5)), "Median member about a 1-in-4 outcome")
  expect_identical(text(rep(19.5, 5)), "Median member worse than 19 of 20 reference years")
  expect_identical(text(rep(25, 5)), "Median member beyond every reference year (rarer than 1 in 21)")
  expect_identical(text(rep(-3, 5), "low"), "Median member beyond every reference year (rarer than 1 in 21)")
  expect_identical(text(rep(2, 5)), "Median member better than the median year")
  # Two tied most adverse years: the member equals them and is worse than 18, not 19
  tied <- .forecast_placement_text(.forecast_placement_stats(rep(20, 5), c(1:18, 20, 20), "high"))$median_text
  expect_identical(tied, "Median member worse than 18 of 20 reference years")
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

test_that("the recent line reads the median member against the latest reference years", {
  # Warming reference: the same outcome is worse in later years; higher is worse.
  ref <- data.frame(year = 1991:2020, value = 1:30)
  pl <- .forecast_placement_stats(rep(25.5, 5), ref$value, "high")
  pl$reference <- ref
  pl$adverse_tail <- "high"
  expect_identical(.forecast_placement_recent(pl), "Median member worse than 5 of the last 10 years (2011-2020)")
  expect_identical(.forecast_placement_text(pl)$recent, .forecast_placement_recent(pl))
  low <- pl; low$adverse_tail <- "low"
  expect_identical(.forecast_placement_recent(low), "Median member worse than 5 of the last 10 years (2011-2020)")
  short <- pl; short$reference <- ref[1:10, ]
  expect_null(.forecast_placement_recent(short))
})

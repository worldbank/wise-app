library(testthat)

# R2-BUG-17: sample(idx, k) with a single candidate samples from 1:idx.

test_that("binary access flips only the single candidate row", {
  x <- c(1L, 1L, 1L, 1L, 1L, 1L, 0L, 1L)
  for (s in 1:20) {
    out <- withr::with_seed(s, .apply_binary_access(x, FALSE, 100))
    expect_identical(out, rep(1L, length(x)))
  }
  y <- c(0L, 0L, 0L, 0L, 0L, 0L, 1L, 0L)
  for (s in 1:20) {
    out <- withr::with_seed(s, .apply_binary_access(y, FALSE, -100))
    expect_identical(out, rep(0L, length(y)))
  }
})

test_that("employment change with one unemployed row moves that row", {
  svy <- data.frame(
    welfare = 1:8,
    employed = c(1L, 1L, 0L, 1L, 1L, 1L, 0L, 1L),
    selfemployed = c(0L, 0L, 1L, 0L, 0L, 0L, 0L, 0L),
    unemployed = c(0L, 0L, 0L, 0L, 0L, 0L, 1L, 0L)
  )
  for (s in 1:20) {
    out <- apply_policy_to_svy(
      svy, labor = list(employment_change_pp = 50), seed = s
    )
    expect_identical(out$unemployed, rep(0L, 8))
    expect_identical(out$employed[-7], svy$employed[-7])
    expect_identical(out$selfemployed[-7], svy$selfemployed[-7])
  }
})

# CR-BUG-04: ex-ante targeting quantile is weighted like the budget.
test_that("ex-ante poor targeting covers the weighted share of the population", {
  svy <- data.frame(
    welfare = 1:10,
    weight = c(rep(1, 8), 50, 50)
  )
  sp <- list(targeting = "exante_poor", targeting_threshold = 20)
  elig <- .determine_sp_eligibility(svy, sp, apply_errors = FALSE)
  # Unweighted 20% would pick 2 rows (<= 2.8) but they hold only ~8% of the
  # weighted population; the weighted 20% cut-off sits in the heavy rows.
  expect_gt(sum(svy$weight[elig]) / sum(svy$weight), 0.15)
  expect_true(all(elig[1:8]))
  # Without weights the old unweighted rule applies.
  elig0 <- .determine_sp_eligibility(svy[, "welfare", drop = FALSE], sp,
    apply_errors = FALSE)
  expect_identical(which(elig0), 1:2)
  # NA / zero weights are ignored in the quantile, not propagated.
  svy$weight[c(1, 2)] <- c(NA, 0)
  expect_false(anyNA(.determine_sp_eligibility(svy, sp, apply_errors = FALSE)))
})

test_that("SP inclusion error with one non-eligible row includes that row", {
  svy <- data.frame(welfare = c(1, 1, 1, 1, 1, 1, 9, 1))
  sp <- list(targeting = "exante_poor", targeting_threshold = 50,
             inclusion_error_pct = 100, exclusion_error_pct = 0)
  for (s in 1:20) {
    elig <- withr::with_seed(s, .determine_sp_eligibility(svy, sp))
    expect_true(all(elig))
  }
})

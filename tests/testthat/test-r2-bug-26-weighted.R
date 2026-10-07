test_that(".weighted_ecdf_at is weighted, tie-aware and equals ecdf() for unit weights", {
  y <- c(3, 1, 2, 2, 5)
  expect_equal(.weighted_ecdf_at(y), stats::ecdf(y)(y))
  expect_equal(.weighted_ecdf_at(y, rep(2, 5)), stats::ecdf(y)(y))
  # Heavy weight on the smallest value pushes it past the first decile cut.
  out <- .weighted_ecdf_at(c(1, 2, 3, 4), c(7, 1, 1, 1))
  expect_equal(out, c(0.7, 0.8, 0.9, 1))
  # Bad weights fall back to unweighted.
  expect_equal(.weighted_ecdf_at(c(1, 2), c(NA, 0)), c(0.5, 1))
})

test_that("policy_input_diagnostics uses survey weights when a weight column exists", {
  base <- data.frame(weight = c(9, 1), x = c(0, 10))
  pol <- base
  pol$x <- c(1, 10)
  d <- policy_input_diagnostics(base, pol, vars = "x")
  expect_equal(d$mean_baseline, 1)
  expect_equal(d$mean_policy, 1.9)
  expect_equal(d$delta_mean, 0.9)
  unw <- policy_input_diagnostics(base[, "x", drop = FALSE], pol[, "x", drop = FALSE], vars = "x")
  expect_equal(unw$mean_baseline, 5)
  # Unit weights reproduce the unweighted SD.
  u1 <- policy_input_diagnostics(
    data.frame(weight = c(1, 1, 1), x = c(1, 2, 4)),
    data.frame(weight = c(1, 1, 1), x = c(1, 2, 4)), vars = "x")
  expect_equal(u1$sd_baseline, stats::sd(c(1, 2, 4)))
})

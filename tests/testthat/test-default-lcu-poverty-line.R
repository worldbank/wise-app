# CR-PERF-12: the LCU default line (20th weighted percentile) no longer needs Hmisc.
test_that("default LCU poverty line is the rounded 20th weighted percentile", {
  set.seed(5)
  df <- data.frame(welfare = exp(rnorm(2000)), ppp2021 = 150, weight = runif(2000, .5, 3))
  line <- default_lcu_poverty_line(df)
  share_below <- sum(df$weight[df$welfare * 150 <= line]) / sum(df$weight)
  expect_equal(share_below, 0.2, tolerance = 0.01)
  # Unweighted fallback and NA tolerance.
  df$weight <- NULL
  df$welfare[1:5] <- NA
  expect_equal(default_lcu_poverty_line(df),
    round(stats::quantile(df$welfare * 150, .2, na.rm = TRUE), 2),
    ignore_attr = TRUE)
  # Missing columns fall back to 1.
  expect_identical(default_lcu_poverty_line(data.frame(x = 1)), 1.00)
})

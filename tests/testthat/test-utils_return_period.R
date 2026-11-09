# The Weibull rule p = m / (n + 1), quantile type 6 for levels (docs/32_metrics.md, Section 4).

test_that("rp_positions gives m / (n + 1): the worst of 30 years is 1 in 31", {
  p <- rp_positions(30L)
  expect_length(p, 30L)
  expect_equal(p[[1L]], 1 / 31)
  expect_equal(p[[30L]], 30 / 31)
  expect_equal(p, seq_len(30L) / 31)
  expect_identical(rp_positions(0L), numeric())
})

test_that("rp_quantile reads the adverse rank (n + 1) p, at both tails", {
  x <- as.numeric(1:30)
  # 1 in 10 of 30 years: adverse rank 31 / 10 = 3.1 from the adverse end
  expect_equal(rp_quantile(x, 0.1, "high"), 27.9)
  expect_equal(rp_quantile(x, 0.1, "low"), 3.1)
  # the worst year is exactly 1 in 31
  expect_equal(rp_quantile(x, 1 / 31, "high"), 30)
  expect_equal(rp_quantile(x, 1 / 31, "low"), 1)
  # the median year, with an even n: mean of the two middle values
  expect_equal(rp_quantile(x, 0.5, "high"), 15.5)
  # equals R's type 6 on the upper and lower tail
  expect_equal(
    rp_quantile(x, c(0.2, 0.1, 0.05), "high"),
    unname(stats::quantile(x, 1 - c(0.2, 0.1, 0.05), type = 6))
  )
  expect_equal(
    rp_quantile(x, c(0.2, 0.1, 0.05), "low"),
    unname(stats::quantile(x, c(0.2, 0.1, 0.05), type = 6))
  )
})

test_that("rp_quantile is NA beyond the support of the record", {
  x <- as.numeric(1:30)
  expect_true(is.na(rp_quantile(x, 1 / 50, "high")))
  expect_true(is.na(rp_quantile(x, 1 / 32, "low")))
  expect_true(is.na(rp_quantile(x, 0.99, "high")))
  expect_true(is.na(rp_quantile(numeric(), 0.1, "high")))
  # 1 in N exists from n = N - 1 years: 9 years give a 1-in-10, 8 do not
  expect_equal(rp_quantile(as.numeric(1:9), 0.1, "high"), 9)
  expect_true(is.na(rp_quantile(as.numeric(1:8), 0.1, "high")))
})

test_that("rp_quantile does not lose a rank to floating point", {
  # 30 * 0.1 is 3.0000000000000004 in floating point
  x <- as.numeric(1:29)
  expect_equal(rp_quantile(x, 0.1, "low"), 3)
  expect_equal(rp_quantile(x, 0.1, "high"), 27)
})

test_that("rp_quantile with ties interpolates between equal values", {
  x <- sort(c(1, 1, 1, 5, 5, 5, 9, 9, 9))
  expect_equal(rp_quantile(x, 0.1, "low"), 1)
  expect_equal(rp_quantile(x, 0.1, "high"), 9)
  expect_equal(rp_quantile(x, 0.5, "high"), 5)
})

test_that("rp_group_quantile equals rp_quantile in every group", {
  set.seed(1)
  g <- rep(1:3, c(30, 12, 5))
  x <- stats::rnorm(length(g))
  for (tail in c("high", "low")) {
    got <- rp_group_quantile(x, g, 4L, 0.1, tail)
    want <- vapply(1:3, function(i) rp_quantile(sort(x[g == i]), 0.1, tail), numeric(1L))
    expect_equal(got[1:3], want)
    expect_true(is.na(got[[4L]]))
  }
  # 12 years support a 1-in-10; 5 do not
  expect_false(is.na(rp_group_quantile(x, g, 4L, 0.1, "high")[[2L]]))
  expect_true(is.na(rp_group_quantile(x, g, 4L, 0.1, "high")[[3L]]))
})

test_that("rp_of_level places a level between reference years and flags the far tail", {
  ref <- as.numeric(1:30)
  # high values adverse
  at <- rp_of_level(ref, c(30.5, 30, 29.5, 29, 15.5, 0), "high")
  expect_equal(at$p, c(1, 1, 1.5, 2, 15.5, 30) / 31)
  expect_equal(at$beyond, c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(at$n_worse, c(30L, 29L, 29L, 28L, 15L, 0L))
  # low values adverse
  low <- rp_of_level(ref, c(0.5, 1, 1.5, 30.5), "low")
  expect_equal(low$p, c(1, 1, 1.5, 30) / 31)
  expect_equal(low$beyond, c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(low$n_worse, c(30L, 29L, 29L, 0L))
  # a level of the quantile returns its own probability
  expect_equal(rp_of_level(ref, rp_quantile(ref, 0.1, "high"), "high")$p, 0.1)
  expect_equal(rp_of_level(ref, rp_quantile(ref, 0.1, "low"), "low")$p, 0.1)
})

test_that("rp_of_level handles ties, missing values and short records", {
  ref <- c(1, 2, 2, 3)
  at <- rp_of_level(ref, 2, "high")
  expect_equal(at$p, 0.5)
  expect_equal(at$n_worse, 1L)
  na <- rp_of_level(c(ref, NA, Inf), c(NA, 2), "high")
  expect_true(is.na(na$p[[1L]]))
  expect_false(na$beyond[[1L]])
  expect_equal(na$p[[2L]], 0.5)
  expect_null(rp_of_level(1, 1, "high"))
})

test_that("rp_exceedance_rows puts the adverse half on the Weibull positions", {
  v <- matrix(as.numeric(1:30), nrow = 1L)
  mm <- list(vals = v, sds = v / 10, model_ids = "m1")
  hi <- rp_exceedance_rows(mm, "Historical", "high", 0, TRUE)
  expect_equal(hi$exceed_prob, seq_len(15L) / 31)
  expect_equal(hi$welfare_val[1:3], c(30, 29, 28))
  expect_equal(hi$coef_sd[1L], 3)
  lo <- rp_exceedance_rows(mm, "Historical", "low", 2, TRUE, source = "Baseline")
  expect_equal(names(lo), c("scenario", "source", "model_id", "rank", "welfare_val", "coef_sd", "exceed_prob", "is_historical"))
  expect_equal(lo$welfare_val[1:2], c(-1, 0))
  expect_true(all(lo$source == "Baseline"))
  # non-finite years are dropped before ranking
  v[1, 1:5] <- NA
  short <- rp_exceedance_rows(list(vals = v, sds = v, model_ids = "m1"), "H", "low", 0, TRUE)
  expect_equal(short$exceed_prob[[1L]], 1 / 26)
})

test_that("adverse_year_support and the threshold matrix use the same rule", {
  x <- as.numeric(1:30)
  s <- adverse_year_support(x, 2001:2030, 0.1, "high")
  expect_equal(s$status, "ok")
  expect_equal(s$baseline_value, 27.9)
  expect_equal(c(s$rank_lo, s$rank_hi), c(27L, 28L))
  expect_equal(s$weight_hi, 0.9)
  expect_equal(adverse_year_support(x, 2001:2030, 0.1, "low")$baseline_value, 3.1)
  # 1-in-50 is not available from 30 years
  expect_equal(adverse_year_support(x, 2001:2030, 0.02, "high")$status, "unavailable")
  m <- by_model_rp_matrix(rbind(x), rbind(x / 10), c(`1:10` = 0.1, `1:20` = 0.05), "high")
  expect_equal(m$rp[1, ], c(27.9, 29.45))
  expect_equal(m$sd[1, ], c(2.79, 2.945))
})

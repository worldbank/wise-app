# ============================================================================ #
# tests/testthat/test-outcome-summary.R                                        #
# PERF-41: outcome_summary_wide() computes the Outcome stats summary table     #
# for the pooled sample and every wave in one grouped pass; the wave pill      #
# re-slices it. Counts are raw row counts; the remaining statistics are        #
# sample-weighted with the weight column. Parity here is against direct        #
# computation on the same subsets.                                             #
# ============================================================================ #

library(testthat)

make_outcome_df <- function(n_per_wave = 20, seed = 1) {
  set.seed(seed)
  df <- data.frame(
    code     = "IRN",
    economy  = "Iran",
    year     = rep(c("2013", "2014"), each = n_per_wave),
    survname = "HEIS",
    y        = c(rnorm(n_per_wave, 5, 1), rnorm(n_per_wave, 7, 2)),
    weight   = rep(c(0.5, 1, 1.5, 2), length.out = 2 * n_per_wave),
    stringsAsFactors = FALSE
  )
  na_idx <- c(3, n_per_wave + 5)
  df$y[na_idx[na_idx <= nrow(df)]] <- NA
  df
}

# Weighted reference for one subset: the app-wide validity rule (finite,
# positive weight), weighted mean, the fsd(w=) sum(w) - 1 denominator, and
# collapse's weighted type-7 quantiles.
wref <- function(d) {
  ok <- !is.na(d$y) & is.finite(d$weight) & d$weight > 0
  v <- d$y[ok]
  w <- d$weight[ok]
  m <- sum(w * v) / sum(w)
  list(
    n_valid = length(v),
    mean = m,
    sd = if (length(v) > 1 && sum(w) > 1) {
      sqrt(sum(w * (v - m)^2) / (sum(w) - 1))
    } else NA_real_,
    min = min(v),
    max = max(v),
    q = as.numeric(collapse::fquantile(v, probs = seq(0.1, 0.9, 0.1),
                                       w = w, type = 7))
  )
}

test_that("outcome_summary_wide: weighted numeric stats match direct computation", {
  df <- make_outcome_df()
  s  <- outcome_summary_wide(df, "y", "numeric")

  waves <- c("all", "IRN|2013|HEIS", "IRN|2014|HEIS")
  expect_identical(s$waves, waves)
  expect_identical(rownames(s$mat), c(
    "n", "n_miss", "coverage", "mean", "sd", "min",
    paste0("p", seq(10, 90, 10)), "max"
  ))

  for (wv in waves) {
    d <- if (wv == "all") df else filter_by_wave(df, wv)
    r <- wref(d)
    # Counts stay raw row counts of outcome availability.
    expect_identical(unname(s$mat["n", wv]), as.numeric(nrow(d)))
    expect_identical(unname(s$mat["n_miss", wv]), as.numeric(sum(is.na(d$y))))
    expect_identical(unname(s$mat["coverage", wv]),
                     100 * sum(!is.na(d$y)) / max(nrow(d), 1))
    # The rest are weighted over validly weighted rows.
    expect_equal(unname(s$mat["mean", wv]), r$mean)
    expect_equal(unname(s$mat["sd", wv]), r$sd)
    expect_equal(unname(s$mat["min", wv]), r$min)
    expect_equal(unname(s$mat["max", wv]), r$max)
    expect_equal(unname(s$mat[paste0("p", seq(10, 90, 10)), wv]), r$q)
  }
})

test_that("outcome_summary_wide: invalid weights enter counts but not weighted stats", {
  df <- make_outcome_df()
  df$weight[c(5, 7, 9, 11)] <- c(0, NA, Inf, -1) # all in the 2013 wave
  s <- outcome_summary_wide(df, "y", "numeric")

  d13 <- filter_by_wave(df, "IRN|2013|HEIS")
  r <- wref(d13)
  # Counts include the invalid-weight rows (outcome availability).
  expect_identical(unname(s$mat["n", "IRN|2013|HEIS"]), as.numeric(nrow(d13)))
  expect_identical(unname(s$mat["coverage", "IRN|2013|HEIS"]),
                   100 * sum(!is.na(d13$y)) / nrow(d13))
  # Weighted stats exclude them.
  expect_equal(unname(s$mat["mean", "IRN|2013|HEIS"]), r$mean)
  expect_equal(unname(s$mat["sd", "IRN|2013|HEIS"]), r$sd)
  expect_equal(unname(s$mat[paste0("p", seq(10, 90, 10)), "IRN|2013|HEIS"]),
               r$q)
})

test_that("outcome_summary_wide: missing weight column falls back to unweighted", {
  df <- make_outcome_df()
  df$weight <- NULL
  s <- outcome_summary_wide(df, "y", "numeric")
  for (wv in c("all", "IRN|2013|HEIS", "IRN|2014|HEIS")) {
    d <- if (wv == "all") df else filter_by_wave(df, wv)
    v <- d$y[!is.na(d$y)]
    expect_equal(unname(s$mat["mean", wv]), mean(v))
    expect_equal(unname(s$mat[paste0("p", seq(10, 90, 10)), wv]),
                 as.numeric(quantile(v, seq(0.1, 0.9, 0.1), type = 7)))
  }
})

test_that("outcome_summary_wide: sd is NA when valid weights sum to at most 1", {
  df <- make_outcome_df(n_per_wave = 3)
  df$weight <- rep(c(0.2, 0.3, 0.2), length.out = nrow(df)) # 0.7 per wave
  s <- outcome_summary_wide(df, "y", "numeric")
  # Each wave's valid weights sum to 0.7 -> no SD; the pooled sample's sum
  # to 1.4 -> SD is computable.
  expect_true(all(is.na(s$mat["sd", c("IRN|2013|HEIS", "IRN|2014|HEIS")])))
  expect_false(is.na(s$mat["sd", "all"]))
  # Mean and deciles remain weighted-computable.
  expect_false(any(is.na(s$mat["mean", ])))
})

test_that("outcome_summary_wide: binary stats weight the share, counts stay raw", {
  df <- make_outcome_df()
  df$z <- as.integer(df$y > 5)
  b <- outcome_summary_wide(df, "z", "binary")

  expect_identical(rownames(b$mat), c(
    "n", "n_miss", "coverage", "n1", "n0", "share1"
  ))
  for (wv in c("all", "IRN|2013|HEIS", "IRN|2014|HEIS")) {
    d <- if (wv == "all") df else filter_by_wave(df, wv)
    zi <- as.integer(d$z)
    n1 <- sum(zi == 1L, na.rm = TRUE)
    n0 <- sum(zi == 0L, na.rm = TRUE)
    expect_identical(unname(b$mat["n1", wv]), as.numeric(n1))
    expect_identical(unname(b$mat["n0", wv]), as.numeric(n0))
    # Weighted share among validly weighted rows.
    ok <- !is.na(zi) & is.finite(d$weight) & d$weight > 0
    sw1 <- sum(d$weight[ok & zi == 1L])
    sw0 <- sum(d$weight[ok & zi == 0L])
    expect_equal(unname(b$mat["share1", wv]), sw1 / (sw1 + sw0))
  }
})

test_that("outcome_summary_wide: Inf values are kept, NaN dropped like NA", {
  df <- make_outcome_df()
  df$y[1] <- Inf
  df$y[2] <- NaN
  s <- outcome_summary_wide(df, "y", "numeric")
  # 2013: 20 rows, one NA (row 3), one NaN (row 2), Inf kept.
  expect_identical(unname(s$mat["n_miss", "IRN|2013|HEIS"]), 2)
  d <- filter_by_wave(df, "IRN|2013|HEIS")
  r <- wref(d)
  expect_equal(unname(s$mat["mean", "IRN|2013|HEIS"]), r$mean)
})

test_that("outcome_summary_wide: data without wave keys yields only the pooled column", {
  df <- make_outcome_df()[, c("y", "weight")]
  s <- outcome_summary_wide(df, "y", "numeric")
  expect_identical(s$waves, "all")
  expect_identical(ncol(s$mat), 1L)
  expect_equal(unname(s$mat["mean", "all"]),
               sum(df$y * df$weight, na.rm = TRUE) /
                 sum(df$weight[!is.na(df$y)]))
})

test_that("outcome_summary_wide: empty and degenerate inputs are handled", {
  s <- outcome_summary_wide(NULL, "y", "numeric")
  expect_identical(s$stat, character(0))

  df <- make_outcome_df()
  df$y <- NA_real_
  s <- outcome_summary_wide(df, "y", "numeric")
  expect_identical(unname(s$mat["coverage", "all"]), 0)
  expect_true(all(is.na(s$mat[c("mean", "sd", "min", "p50", "max"), ])))

  s <- outcome_summary_wide(df[, c("y", "weight")], "absent", "numeric")
  expect_identical(s$stat, character(0))
})

test_that("format_outcome_summary: counts, percent, decimals and dashes", {
  df <- make_outcome_df()
  df$y[1:5] <- NA # 2013: 15 available of 20
  s <- outcome_summary_wide(df, "y", "numeric")

  f13 <- .format_outcome_summary(s, "IRN|2013|HEIS")
  expect_identical(names(f13), c("Statistic", "Value"))
  expect_identical(f13$Value[[1]], "20")
  expect_identical(f13$Value[[2]], "5")
  expect_identical(f13$Value[[3]], "75%")
  r13 <- wref(filter_by_wave(df, "IRN|2013|HEIS"))
  expect_identical(f13$Value[[4]], as.character(round(r13$mean, 3)))
  expect_identical(f13$Statistic[11], "Median (P50)")

  # Unknown wave falls back to the first column; NA statistics become dashes.
  df$y <- NA_real_
  s2 <- outcome_summary_wide(df, "y", "numeric")
  f2 <- .format_outcome_summary(s2, "IRN|2013|HEIS")
  expect_true(all(f2$Value[c(4, 6, 7)] == "\u2013"))
  expect_identical(f2$Value[[1]], "20") # the wave's Observations row
})

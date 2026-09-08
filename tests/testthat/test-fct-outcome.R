# ============================================================================ #
# tests/testthat/test-fct-outcome.R                                            #
# Fast, histogram-first outcome distribution plots.                            #
# ============================================================================ #

library(testthat)

make_outcome_plot_df <- function(n = 1000L) {
  set.seed(17)
  data.frame(
    code        = "TST",
    countryyear = sample(c("TST, 2018", "TST, 2021"), n, replace = TRUE),
    welfare     = rgamma(n, shape = 2, rate = 0.4),
    poor        = rbinom(n, 1, 0.35),
    stringsAsFactors = FALSE
  )
}

test_that("ridge distribution data is bounded by fixed grid size", {
  df <- make_outcome_plot_df(5000L)
  out <- wiseapp:::build_ridge_distribution_data(
    df, "welfare", n_bins = 128L, n_grid = 96L, log_transform = TRUE
  )

  expect_type(out, "list")
  expect_setequal(out$groups, c("TST, 2018", "TST, 2021"))
  expect_equal(nrow(out$data), 2L * 96L)
  expect_true(all(is.finite(out$data$x)))
  expect_true(all(out$data$height >= 0 & out$data$height <= 1))
})

test_that("outcome distribution plots support continuous and binary outcomes", {
  skip_if_not_installed("ggplot2")

  df <- make_outcome_plot_df()
  p_cont <- plot_welfare_dist(
    df, outcome = "welfare", label = "Welfare", type = "numeric",
    poverty_lines = NULL
  )
  p_bin <- plot_welfare_dist(
    df, outcome = "poor", label = "Poor", type = "logical",
    poverty_lines = NULL
  )

  expect_s3_class(p_cont, "ggplot")
  expect_s3_class(p_bin, "ggplot")
  expect_setequal(
    unique(ggplot2::ggplot_build(p_cont)$data[[1]]$fill),
    c("#0071BC")
  )
  expect_true(any(vapply(p_bin$layers, function(x) {
    inherits(x$geom, "GeomRect")
  }, logical(1))))
  expect_true(any(vapply(p_bin$layers, function(x) {
    inherits(x$geom, "GeomText")
  }, logical(1))))
  bin_data <- ggplot2::ggplot_build(p_bin)$data[[1]]
  expect_setequal(unique(bin_data$fill), c("#D9EFF8", "#0071BC"))
  expect_equal(
    as.numeric(tapply(bin_data$ymax - bin_data$ymin, bin_data$x, sum)),
    c(1, 1)
  )
})

test_that("ridge distribution data rejects unusable inputs", {
  expect_null(wiseapp:::build_ridge_distribution_data(NULL, "welfare"))
  expect_null(wiseapp:::build_ridge_distribution_data(
    data.frame(welfare = 1), "welfare"
  ))
  expect_null(wiseapp:::build_ridge_distribution_data(
    data.frame(
      code = "TST", countryyear = "TST, 2021", welfare = NA_real_
    ),
    "welfare"
  ))
})

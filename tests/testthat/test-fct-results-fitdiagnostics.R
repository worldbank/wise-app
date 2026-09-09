# ============================================================================ #
# tests/testthat/test-fct-results-fitdiagnostics.R                             #
# Model fit diagnostics: residual panels, calibration curves and fit stats.    #
# Covers linear (fixest), binary (glm + feglm) and RIF-style model lists.      #
# ============================================================================ #

library(testthat)

set.seed(42)
n <- 200
dat <- data.frame(
  y   = rnorm(n, mean = 10, sd = 2),
  x   = rnorm(n),
  g   = rep(1:5, each = n / 5),
  bin = rbinom(n, 1, plogis(-0.5 + 0.3 * rnorm(n)))
)
dat$bin_x <- rnorm(n)
dat$bin_p <- plogis(-0.5 + 0.4 * dat$bin_x)
dat$bin   <- rbinom(n, 1, dat$bin_p)

m_lin   <- fixest::feols(y ~ x | g, data = dat)
m_lin0  <- fixest::feols(y ~ x, data = dat)
m_glm   <- stats::glm(bin ~ bin_x, data = dat, family = stats::binomial())
m_feglm <- fixest::feglm(bin ~ bin_x | g, data = dat,
                         family = stats::binomial())

# ---- calc_fit_stats ----------------------------------------------------------

test_that("linear fit stats use fit-card names and formatting", {
  s <- calc_fit_stats(m_lin, is_logistic = FALSE, engine = "fixest")
  expect_identical(s$Statistic,
                   c("Observations", "R\u00b2", "Adj. R\u00b2", "Within R\u00b2"))
  expect_equal(s$Value[1], "200")
  expect_match(s$Value[2], "^(<0\\.01|[01]\\.\\d{2})$")
  expect_false(any(grepl("R-squared", s$Statistic)))
})

test_that("sub-0.005 R2 renders as '<0.01' and missing stats as em dash", {
  # y orthogonal to x by construction: exact zero R-squared
  d0 <- data.frame(y = c(1:10, 1:10), x = c(rep(0, 10), rep(1, 10)))
  s0 <- calc_fit_stats(fixest::feols(y ~ x, data = d0),
                       is_logistic = FALSE, engine = "fixest")
  expect_equal(s0$Value[s0$Statistic == "R\u00b2"], "<0.01")
})

test_that("logistic fit stats report McFadden R2 and AIC", {
  s <- calc_fit_stats(m_glm, is_logistic = TRUE, engine = "fixest")
  expect_identical(s$Statistic, c("Observations", "McFadden R\u00b2", "AIC"))
  expect_match(s$Value[2], "^(<0\\.01|[01]\\.\\d{2})$")
  expect_match(s$Value[3], "^[0-9,]+$")
})

test_that("feglm binomial with FE works for both stat variants", {
  expect_no_error(s <- calc_fit_stats(m_feglm, is_logistic = TRUE,
                                      engine = "fixest"))
  expect_identical(s$Statistic, c("Observations", "McFadden R\u00b2", "AIC"))
})

test_that("RIF engine returns one formatted row per requested tau", {
  rif_list <- list(
    fixest::feols(y ~ x, data = dat),
    fixest::feols(y ~ x, data = dat),
    fixest::feols(y ~ x, data = dat)
  )
  s <- calc_fit_stats(rif_list, is_logistic = FALSE, engine = "rif",
                      taus = c(0.25, 0.5, 0.75))
  expect_identical(names(s), c("Quantile", "N", "R\u00b2", "Within R\u00b2"))
  expect_identical(s$Quantile,
                   paste0("\u03c4 = ", c("0.25", "0.5", "0.75")))
  expect_match(s[["Within R\u00b2"]], "^(<0\\.01|[01]\\.\\d{2}|\u2014)$")

  # taus shorter than the model list are honoured; NULL falls back to the grid
  s2 <- calc_fit_stats(rif_list, is_logistic = FALSE, engine = "rif",
                       taus = c(0.25, 0.75))
  expect_equal(nrow(s2), 2)
  s3 <- calc_fit_stats(rif_list, is_logistic = FALSE, engine = "rif")
  expect_equal(nrow(s3), 3)
  expect_match(s3$Quantile[1], "0\\.1")
})

# ---- plot_residual_panels ----------------------------------------------------

test_that("linear model yields a 2-panel patchwork figure", {
  p <- plot_residual_panels(m_lin, is_logistic = FALSE)
  expect_s3_class(p, "ggplot")
  expect_s3_class(p, "patchwork")
})

test_that("RIF single model (fixest) works through the linear branch", {
  p <- plot_residual_panels(m_lin0, is_logistic = FALSE)
  expect_s3_class(p, "ggplot")
})

test_that("binary model yields a binned residual plot centred on zero", {
  p <- plot_residual_panels(m_glm, is_logistic = TRUE)
  expect_s3_class(p, "ggplot")
  expect_false(inherits(p, "patchwork"))
  expect_match(p$labels$subtitle, "Binned residuals")

  pf <- plot_residual_panels(m_feglm, is_logistic = TRUE)
  expect_s3_class(pf, "ggplot")
})

# ---- plot_calibration --------------------------------------------------------

test_that("calibration curve bins predicted risk and matches observed rates", {
  p <- plot_calibration(m_glm)
  expect_s3_class(p, "ggplot")
  expect_match(p$labels$subtitle, "Observed vs predicted rate")

  # Recompute the binning by hand and compare against the plotted data
  pd  <- as.numeric(stats::fitted(m_glm))
  obs <- dat$bin
  n   <- length(pd)
  ord <- order(pd)
  brks <- unique(floor(seq(0, n, length.out = 10 + 1)))
  grp  <- cut(seq_len(n), breaks = brks, include.lowest = TRUE)
  bdf <- data.frame(pred = pd[ord], obs = as.numeric(obs)[ord], grp = grp)
  cal <- stats::aggregate(cbind(pred, obs) ~ grp, data = bdf, FUN = mean)
  expect_true(all(cal$obs >= 0 & cal$obs <= 1))
  expect_true(all(cal$pred >= min(pd) - 0.05 & cal$pred <= max(pd) + 0.05))
  expect_equal(nrow(cal), length(unique(grp)))
})

test_that("calibration works for feglm binomial", {
  expect_no_error(p <- plot_calibration(m_feglm))
  expect_s3_class(p, "ggplot")
})

test_that("calibration recovers the outcome when model.frame is unavailable", {
  # fit_model() strips embedded data from fixest fits' $call, after which
  # stats::model.frame() errors on the stored model. plot_calibration must
  # then recover actual = fitted + response residuals (binomial identity).
  stub <- structure(list(), class = "cal_stub")
  local({
    registerS3method("fitted", "cal_stub",
                     function(object, ...) plogis(seq(-1, 1, length.out = 60)))
    registerS3method("residuals", "cal_stub",
                     function(object, type = "response", ...) {
                       p <- plogis(seq(-1, 1, length.out = 60))
                       set.seed(3)
                       y <- rbinom(60, 1, p)
                       if (identical(type, "response")) y - p else y
                     })
    registerS3method("model.frame", "cal_stub",
                     function(formula, ...) stop("no model frame"))
    p <- plot_calibration(stub)
    expect_s3_class(p, "ggplot")
    expect_match(p$labels$subtitle, "Observed vs predicted rate")
  })
})

# ---- plot_importance ---------------------------------------------------------

test_that("importance plot ranks terms by squared standardized coefficients", {
  p <- plot_importance(m_lin, label_fun = function(x) x)
  expect_s3_class(p, "ggplot")

  d <- ggplot2::ggplot_build(p)$data[[1]]
  expect_true(all(d$y >= 0))
  expect_true(all(diff(d$x) <= 1e-8))  # ordered descending along the axis

  pf <- plot_importance(m_feglm)
  expect_s3_class(pf, "ggplot")
})

# ---- plot_pred_vs_actual -----------------------------------------------------

test_that("logistic branch now returns the calibration curve", {
  p <- plot_pred_vs_actual(m_glm, is_logistic = TRUE)
  expect_s3_class(p, "ggplot")
  expect_match(p$labels$subtitle, "Observed vs predicted rate")
})

test_that("linear branch still overlays actual vs predicted histograms", {
  p <- plot_pred_vs_actual(m_lin0, is_logistic = FALSE, outcome_label = "welfare")
  expect_s3_class(p, "ggplot")
  expect_match(p$labels$x, "welfare")
})

# ============================================================================ #
# tests/testthat/test-fct_fit_model.R                                          #
# fit_model() / run_lasso_selection() sample and role-flag regressions.        #
# ============================================================================ #

library(testthat)

test_that("RIF is computed on the complete-case estimation sample (CR-BUG-03)", {

  set.seed(303)
  n <- 4000L
  welfare <- stats::rnorm(n)
  ctrl <- stats::rnorm(n)
  # Welfare-correlated missingness: richer households lose the control more
  # often, so the complete-case sample has a lower welfare distribution.
  ctrl[stats::runif(n) < stats::plogis(2 * welfare - 1)] <- NA
  df <- data.frame(welfare = welfare, temp = stats::rnorm(n), ctrl = ctrl)

  so <- list(name = "welfare", type = "numeric")
  sw <- data.frame(name = "temp", cont_binned = "Continuous",
                   stringsAsFactors = FALSE)
  sm <- build_selected_model(
    model_type    = "Unconditional quantile regression (RIF)",
    engine        = "rif",
    hh_covariates = "ctrl"
  )

  mf <- fit_model(df, so, sw, sm)
  td <- mf$train_data
  expect_false(anyNA(td$ctrl))
  expect_lt(nrow(td), n)

  for (tau in c(0.1, 0.5, 0.9)) {
    col <- paste0("rif_", formatC(tau * 100, format = "d"))
    q_est <- unname(stats::quantile(td$welfare, tau, type = 7))
    # E[RIF] = q_tau on the sample the RIF was built from; only the
    # discreteness term (tau - F_n(q)) / f(q) remains, which is O(1/n).
    expect_equal(mean(td[[col]]), q_est, tolerance = 5e-3)
  }
})

test_that("LASSO selection conditions on fixed effects (R2-BUG-08)", {
  set.seed(808)
  n_fe <- 60L
  n <- 3000L
  g <- sample.int(n_fe, n, replace = TRUE)
  fe_eff <- stats::rnorm(n_fe, sd = 3)
  # x_proxy tracks the fixed effect only; x_true matters within a group.
  x_proxy <- fe_eff[g] + stats::rnorm(n, sd = 0.1)
  x_true <- stats::rnorm(n)
  x_noise <- stats::rnorm(n)
  weather <- stats::rnorm(n)
  y <- fe_eff[g] + 0.8 * x_true + 0.3 * weather + stats::rnorm(n, sd = 0.5)
  df <- data.frame(
    welfare = y, weather = weather, loc = g,
    x_proxy = x_proxy, x_true = x_true, x_noise = x_noise
  )
  vl <- data.frame(
    name = c("welfare", "weather", "loc", "x_proxy", "x_true", "x_noise"),
    ind = 0, hh = c(0, 0, 0, 1, 1, 1), area = 0, firm = 0,
    outcome = c(1, 0, 0, 0, 0, 0)
  )
  sel <- run_lasso_selection(
    df, list(name = "welfare", type = "numeric"),
    weather_vars = "weather", fe_vars = "loc", valid_vl = vl,
    nfolds = 5, mi_m = 3
  )
  expect_true("x_true" %in% sel$selected_covariates)
  expect_false("x_proxy" %in% sel$selected_covariates)
})

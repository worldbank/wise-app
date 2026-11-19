# R2-PERF-02: the worker snapshot carries a slim model fit.
test_that("step2_slim_model_fit drops unused fields and fit environments without changing results", {
  set.seed(11)
  n <- 3000
  d <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n),
                  g = sample(letters, n, TRUE), cl = sample(1:40, n, TRUE))
  fit_in_function <- function(dd) {
    ballast <- rnorm(5e5)  # captured by the fitting frame
    fixest::feols(y ~ x1 + x2 | g, dd, cluster = ~cl)
  }
  fit <- fit_in_function(d)
  mf <- list(
    engine = "fixest", weather_terms = c("x1", "x2"), interaction_terms = character(0),
    fe_terms = "g", fit1 = fit, fit2 = fit, fit3 = fit, train_data = d,
    formulas = list(f = y ~ x1), y_var = "y", model_type = "Linear regression",
    .snap = list(model = list(a = 1), survey_weather = d[rep(1:n, 3), ]), .sig = "sig"
  )
  slim <- step2_slim_model_fit(mf)

  expect_false(any(c("fit1", "fit2") %in% names(slim)))
  expect_identical(names(slim$.snap), "model")
  expect_identical(slim$.sig, "sig")
  size <- function(x) length(serialize(x, NULL))
  expect_lt(size(slim), 0.3 * size(mf))
  nd <- d[1:100, ]
  expect_identical(predict(slim$fit3, nd), predict(fit, nd))
  expect_identical(stats::fitted(slim$fit3), stats::fitted(fit))
  expect_identical(stats::resid(slim$fit3), stats::resid(fit))
  expect_identical(stats::vcov(slim$fit3), stats::vcov(fit))
  expect_identical(stats::coef(slim$fit3), stats::coef(fit))
  # The live model is untouched (its environment is still attached).
  expect_false(identical(fit$call_env, globalenv()))
  expect_true(!is.null(mf$fit1))
})

test_that("step2_slim_model_fit leaves non-fixest fits alone", {
  mf <- list(engine = "ranger", fit3 = structure(list(a = 1), class = "ranger"),
             train_data = data.frame(y = 1), fit1 = 1)
  slim <- step2_slim_model_fit(mf)
  expect_identical(slim$fit3, mf$fit3)
  expect_null(slim$fit1)
})

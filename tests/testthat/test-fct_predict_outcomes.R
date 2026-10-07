# Tests for predict_outcome() (R/fct_predict_outcomes.R): fitted values per
# model family, and the four residual modes.

make_po_data <- function(n = 40, seed = 11) {
  withr::with_seed(seed, {
    d <- data.frame(
      id = seq_len(n),
      x = rnorm(n),
      g = factor(rep(c("a", "b", "c", "d"), length.out = n))
    )
    d$y <- 1 + 2 * d$x + as.integer(d$g) * 0.5 + rnorm(n, sd = 0.3)
    d$z <- stats::rbinom(n, 1, stats::plogis(0.8 * d$x))
  })
  d
}

test_that("bare lm: residuals = 'none' returns fitted values and NA residuals", {
  tr <- make_po_data()
  fit <- lm(y ~ x, data = tr)
  nd <- data.frame(id = 1:5, x = c(-1, 0, 1, 2, 3))
  out <- predict_outcome(fit, nd)

  expect_equal(out$.fitted, unname(predict(fit, nd)))
  expect_equal(out$predicted, out$.fitted)
  expect_true(all(is.na(out$.residual)))
  expect_equal(nrow(out), 5L)
  expect_equal(names(predict_outcome(fit, nd, outcome = "welfare"))[ncol(out)], "welfare")
})

test_that("bare lm: 'original' matches residuals by id and fills unmatched ids", {
  tr <- make_po_data()
  fit <- lm(y ~ x, data = tr)
  nd <- tr[c(3, 7, 9), c("id", "x")]
  out <- predict_outcome(fit, nd,
    residuals = "original", id = "id", train_data = tr
  )
  expect_equal(out$.residual, unname(residuals(fit))[c(3, 7, 9)])
  expect_equal(out$predicted, out$.fitted + out$.residual)

  nd_new <- data.frame(id = c(1, 999), x = c(0, 0))
  expect_warning(
    out2 <- predict_outcome(fit, nd_new,
      residuals = "original", id = "id", train_data = tr
    ),
    "not in training data"
  )
  expect_equal(out2$.residual[[1]], unname(residuals(fit))[[1]])
  expect_true(any(abs(out2$.residual[[2]] - unname(residuals(fit))) < 1e-10))
})

test_that("bare lm: 'original' without id recycles by position", {
  tr <- make_po_data(n = 10)
  fit <- lm(y ~ x, data = tr)
  nd <- tr[1:20 %% 10 + 1, c("id", "x")]
  out <- predict_outcome(fit, nd, residuals = "original", train_data = tr)
  expect_equal(out$.residual, rep(unname(residuals(fit)), 2))

  nd7 <- tr[1:7, c("id", "x")]
  expect_warning(
    out7 <- predict_outcome(fit, nd7, residuals = "original", train_data = tr),
    "repeating training residuals"
  )
  expect_equal(out7$.residual, unname(residuals(fit))[1:7])
})

test_that("'normal' and 'resample' are seeded and drawn from training residuals", {
  tr <- make_po_data()
  fit <- lm(y ~ x, data = tr)
  nd <- data.frame(id = 1:200, x = 0)
  res <- unname(residuals(fit))

  n1 <- predict_outcome(fit, nd, residuals = "normal", train_data = tr, seed = 5)
  n2 <- predict_outcome(fit, nd, residuals = "normal", train_data = tr, seed = 5)
  n3 <- predict_outcome(fit, nd, residuals = "normal", train_data = tr, seed = 6)
  expect_identical(n1$.residual, n2$.residual)
  expect_false(identical(n1$.residual, n3$.residual))
  expect_equal(sd(n1$.residual), sd(res), tolerance = 0.2)
  expect_equal(n1$predicted, n1$.fitted + n1$.residual)

  r1 <- predict_outcome(fit, nd, residuals = "resample", train_data = tr, seed = 5)
  r2 <- predict_outcome(fit, nd, residuals = "resample", train_data = tr, seed = 5)
  expect_identical(r1$.residual, r2$.residual)
  in_train <- vapply(r1$.residual, function(r) any(abs(r - res) < 1e-10), logical(1))
  expect_true(all(in_train))
})

test_that("argument validation", {
  tr <- make_po_data()
  fit <- lm(y ~ x, data = tr)
  nd <- tr[1:3, c("id", "x")]
  expect_error(predict_outcome(fit, nd, residuals = character(0)), "length 0")
  expect_error(predict_outcome(fit, nd, residuals = "bogus"))
  expect_error(
    predict_outcome(fit, nd, residuals = "normal"),
    "train_data"
  )
  expect_error(
    predict_outcome(fit, nd,
      residuals = "original", id = "nope", train_data = tr
    ),
    "`id` column not found in training"
  )
  # A vector of modes uses the first (default "none")
  expect_true(all(is.na(predict_outcome(fit, nd, residuals = c("none", "normal"))$.residual)))
})

test_that("fixest feols: fitted values and response residuals", {
  tr <- make_po_data()
  fit <- fixest::feols(y ~ x | g, data = tr, notes = FALSE)
  nd <- tr[1:6, c("id", "x", "g")]
  out <- predict_outcome(fit, nd)
  expect_equal(out$.fitted, as.numeric(predict(fit, nd)))

  o2 <- predict_outcome(fit, nd, residuals = "original", id = "id", train_data = tr)
  expect_equal(o2$.residual, as.numeric(residuals(fit))[1:6])
  expect_equal(o2$predicted, tr$y[1:6], tolerance = 1e-8)
})

test_that("fixest: unseen FE level keeps its row with NA prediction", {
  tr <- make_po_data()
  fit <- fixest::feols(y ~ x | g, data = tr, notes = FALSE)
  nd <- data.frame(id = 1:2, x = c(0, 0), g = factor(c("a", "zzz")))
  out <- predict_outcome(fit, nd)
  expect_equal(nrow(out), 2L)
  expect_false(is.na(out$.fitted[[1]]))
  expect_true(is.na(out$.fitted[[2]]))
})

test_that("fixest feglm: probabilities, response residuals, explicit engine", {
  tr <- make_po_data()
  fit <- fixest::feglm(z ~ x | g, data = tr, family = "binomial", notes = FALSE)
  nd <- tr[1:6, c("id", "x", "g")]
  out <- predict_outcome(fit, nd, engine = "fixest")
  expect_equal(out$.fitted, as.numeric(predict(fit, nd, type = "response")))
  expect_true(all(out$.fitted > 0 & out$.fitted < 1))

  o2 <- predict_outcome(fit, nd, residuals = "original", id = "id", train_data = tr)
  # Response residuals (observed - probability), the scale added to .fitted.
  expect_equal(o2$.residual, tr$z[1:6] - out$.fitted)
})

test_that("parsnip linear: .pred becomes .fitted, residuals are observed - fitted", {
  skip_if_not_installed("parsnip")
  tr <- make_po_data()
  fit <- parsnip::fit(parsnip::linear_reg(), y ~ x, data = tr)
  nd <- tr[1:6, c("id", "x")]
  out <- predict_outcome(fit, nd)
  expect_equal(out$.fitted, unname(predict(lm(y ~ x, tr), nd)))

  o2 <- predict_outcome(fit, nd, residuals = "original", id = "id", train_data = tr)
  expect_equal(o2$.residual, unname(residuals(lm(y ~ x, tr)))[1:6])
  expect_equal(o2$predicted, tr$y[1:6], tolerance = 1e-8)
})

test_that("parsnip logistic: .pred_1 is the probability and a residual draw is made", {
  skip_if_not_installed("parsnip")
  tr <- make_po_data()
  tr$zf <- factor(tr$z, levels = c(0, 1))
  fit <- parsnip::fit(parsnip::logistic_reg(), zf ~ x, data = tr)
  nd <- tr[1:6, c("id", "x")]
  out <- predict_outcome(fit, nd)
  p <- unname(predict(glm(z ~ x, binomial, tr), nd, type = "response"))
  expect_equal(out$.fitted, p)

  # Only outcome + predictors in train_data, so the observed-minus-fitted
  # residual branch (not the centred-fitted proxy) is used.
  o2 <- predict_outcome(fit, nd,
    residuals = "normal", train_data = tr[c("id", "x", "zf")]
  )
  expect_equal(nrow(o2), 6L)
  expect_false(anyNA(o2$.residual))

  # Residual is observed 0/1 minus probability, not factor codes (1/2) minus it.
  o3 <- predict_outcome(fit, tr[c("id", "x")],
    residuals = "original", id = "id", train_data = tr[c("id", "x", "zf")]
  )
  p_all <- unname(predict(glm(z ~ x, binomial, tr), tr, type = "response"))
  expect_equal(o3$.residual, tr$z - p_all, tolerance = 1e-8)
  expect_true(all(abs(o3$.residual) < 1))
})

test_that("parsnip logistic with several non-newdata columns falls back to centred-fitted residuals", {
  skip_if_not_installed("parsnip")
  tr <- make_po_data()
  tr$zf <- factor(tr$z, levels = c(0, 1))
  fit <- parsnip::fit(parsnip::logistic_reg(), zf ~ x, data = tr)
  nd <- tr[1:6, c("id", "x")]
  expect_warning(
    out <- predict_outcome(fit, nd, residuals = "normal", train_data = tr),
    "centred fitted values"
  )
  expect_equal(nrow(out), 6L)
  expect_false(anyNA(out$.residual))
})

test_that("bare glm returns response-scale probabilities by default", {
  tr <- make_po_data()
  fit <- glm(z ~ x, binomial, data = tr)
  nd <- data.frame(id = 1:4, x = c(-1, 0, 1, 2))
  out <- predict_outcome(fit, nd)
  expect_equal(out$.fitted, unname(predict(fit, nd, type = "response")), tolerance = 1e-8)
  expect_true(all(out$.fitted > 0 & out$.fitted < 1))
})

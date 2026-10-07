# prepare_outcome_df: currency handling (LCU back-conversion, poverty lines) --

make_prep_df <- function() {
  data.frame(
    welfare = c(1, 2, 10, 4),
    ppp2021 = c(500, 500, 500, 250),  # two economies
    urban   = c(0, 1, 0, 1)
  )
}

sel <- function(name, units = "PPP", type = "numeric", povline = NA_real_) {
  data.frame(name = name, label = name, units = units, type = type,
             transform = if (identical(type, "numeric")) "log" else NA_character_,
             direction = "higher_is_better", povline = povline)
}

test_that("continuous outcome in LCU mode is back-converted by ppp2021 before log", {
  df <- prepare_outcome_df(make_prep_df(), sel("welfare", units = "LCU"))
  expect_equal(df$welfare, log(c(500, 1000, 5000, 1000)))
})

test_that("continuous outcome in PPP mode is only logged", {
  df <- prepare_outcome_df(make_prep_df(), sel("welfare", units = "PPP"))
  expect_equal(df$welfare, log(c(1, 2, 10, 4)))
})

test_that("LCU and PPP log outcomes differ only by a per-economy constant", {
  lcu <- prepare_outcome_df(make_prep_df(), sel("welfare", units = "LCU"))
  ppp <- prepare_outcome_df(make_prep_df(), sel("welfare", units = "PPP"))
  expect_equal(lcu$welfare - ppp$welfare, log(make_prep_df()$ppp2021))
})

test_that("poor outcome with a PPP line compares stored welfare directly", {
  df <- prepare_outcome_df(make_prep_df(), sel("poor", units = "PPP", type = "logical", povline = 2.0))
  expect_equal(df$poor, c(1, 0, 0, 0))
})

test_that("poor outcome with an LCU line is scaled to PPP before comparison", {
  df <- prepare_outcome_df(make_prep_df(), sel("poor", units = "LCU", type = "logical", povline = 1000))
  # LCU 1000/day = 2.0 PPP in economy A (ppp2021 = 500) and 4.0 PPP in economy B (250)
  expect_equal(df$poor, as.numeric(c(1, 2, 10, 4) < c(2, 2, 2, 4)))
})

test_that("poor outcome with an LCU line does not crash when the column is absent", {
  expect_no_error(df <- prepare_outcome_df(make_prep_df(), sel("poor", units = "LCU", type = "logical", povline = 1000)))
  expect_setequal(unique(df$poor), c(0, 1))
})

test_that("poor outcome with an LCU line falls back to direct comparison without ppp2021", {
  d <- make_prep_df()
  d$welfare <- d$welfare * d$ppp2021  # raw LCU world: no load-time conversion
  d$ppp2021 <- NULL
  df <- prepare_outcome_df(d, sel("poor", units = "LCU", type = "logical", povline = 1000))
  expect_equal(df$poor, as.numeric(c(500, 1000, 5000, 1000) < 1000))
})

test_that("ensure_outcome_column derives poor without applying transforms", {
  d <- make_prep_df()
  d$poor <- NULL
  out <- ensure_outcome_column(
    d,
    sel("poor", units = "LCU", type = "logical", povline = 1000)
  )
  expect_equal(out$poor, as.numeric(d$welfare < c(2, 2, 2, 4)))
  expect_equal(out$welfare, d$welfare)
})

test_that("ensure_outcome_column is safe for missing or unavailable metadata", {
  d <- make_prep_df()
  d$poor <- NULL
  expect_identical(ensure_outcome_column(d, sel("poor")), d)
  expect_identical(ensure_outcome_column(d, sel("other")), d)
  expect_identical(ensure_outcome_column(d, NULL), d)
})

test_that("poor indicator is not back-converted when the column already exists", {
  d <- make_prep_df()
  d$poor <- c(1, 0, 0, 0)
  df <- prepare_outcome_df(d, sel("poor", units = "LCU", type = "logical", povline = 1000))
  expect_equal(df$poor, as.numeric(c(1, 2, 10, 4) < c(2, 2, 2, 4)))
})

test_that("non-numeric LCU outcome column is left alone", {
  d <- make_prep_df()
  d$dummy <- c(1, 0, 1, 0)
  df <- prepare_outcome_df(d, sel("dummy", units = "LCU", type = "binary", povline = NA))
  expect_equal(df$dummy, c(1, 0, 1, 0))
})

# .povline_to_ppp: shared poverty-line scaling helper -------------------------

test_that("povline_to_ppp scales LCU lines per observation and passes PPP through", {
  d <- make_prep_df()
  expect_equal(.povline_to_ppp(1000, d, TRUE), c(2, 2, 2, 4))
  expect_equal(.povline_to_ppp(2, d, FALSE), 2)
  expect_equal(.povline_to_ppp(2, d, NA), 2)
  d$ppp2021 <- NULL
  expect_equal(.povline_to_ppp(1000, d, TRUE), 1000)
})

# build_selected_outcome: currency tagging ------------------------------------

test_that("poor outcome inherits the selected currency and keeps the line", {
  info <- data.frame(name = "poor", label = "p", units = "", type = "logical")
  so <- build_selected_outcome(info, currency = "LCU", poverty_line = 1200)
  expect_equal(so$units, "LCU")
  expect_equal(so$povline, 1200)
  expect_true(is.na(so$transform))
})

test_that("welfare outcome defaults to the $3.00 PPP line", {
  info <- data.frame(name = "welfare", label = "w", units = "LCU", type = "numeric")
  so <- build_selected_outcome(info, currency = "PPP", poverty_line = NULL)
  expect_equal(so$units, "PPP")
  expect_equal(so$povline, 3.00)
  expect_equal(so$transform, "log")
})

# R2-BUG-19: RIF polynomial coefficient SE uses the full VCV ------------------

test_that("R2-BUG-19: RIF coefplot combines polynomial SEs with their covariance", {
  set.seed(19)
  n <- 800
  df <- data.frame(temp = stats::rnorm(n, 3, 1))
  df$welfare <- 1 + 0.5 * df$temp - 0.1 * df$temp^2 + stats::rnorm(n)
  sm <- build_selected_model(
    model_type = "Unconditional quantile regression (RIF)", engine = "rif"
  )
  sw <- data.frame(name = "temp", cont_binned = "Continuous",
                   stringsAsFactors = FALSE)
  sw$polynomial <- list("2")
  mf <- fit_model(df, list(name = "welfare", type = "numeric"), sw, sm)

  ch <- echart_make_coefplot(
    mf$fit1, mf$fit2, mf$fit3, "temp", character(0),
    engine = "rif", rif_grid = mf$rif_grid, pred_var = "temp", tau = 0.5,
    train_data = mf$train_data
  )
  pt <- ch$x$opts$series[[3]]$data[[1]]
  est <- unlist(pt$value)[1]

  # Manual delta method on the median sub-fit of spec 3: w' V w.
  sub <- mf$fit3[[5]]
  b <- stats::coef(sub)
  V <- stats::vcov(sub)
  sq <- setdiff(names(b), c("(Intercept)", "temp"))
  expect_length(sq, 1L)
  w <- c(1, 2 * mean(mf$train_data$temp))
  terms <- c("temp", sq)
  se <- sqrt(as.numeric(t(w) %*% V[terms, terms] %*% w))
  se_diag <- sqrt(sum((w * sqrt(diag(V)[terms]))^2))
  expect_equal(est, sum(w * b[terms]))
  expect_equal(pt$confLow, est - 1.96 * se)
  expect_equal(pt$confHigh, est + 1.96 * se)
  # The covariance term matters here, so the old formula is distinguishable.
  expect_gt(abs(se - se_diag) / se, 0.05)
})

test_that("R2-BUG-19: .rif_combined_se falls back without a VCV", {
  expect_equal(
    .rif_combined_se(NULL, c("a", "b"), c(1, 2), c(0.3, 0.4)),
    sqrt(0.3^2 + 0.8^2)
  )
})

# make_regtable_df: tidy export table behind the regression CSV (UI-45) ------

test_that("make_regtable_df returns one row per specification and term", {
  set.seed(42)
  d <- data.frame(y = rnorm(200), x1 = rnorm(200), x2 = rnorm(200),
                  g = factor(sample(1:5, 200, TRUE)))
  f1 <- fixest::feols(y ~ x1, data = d)
  f2 <- fixest::feols(y ~ x1 | g, data = d)
  f3 <- fixest::feols(y ~ x1 + x2 | g, data = d)

  df <- make_regtable_df(f1, f2, f3, engine = "fixest")
  expect_s3_class(df, "data.frame")
  expect_true(all(c("Model", "Variable", "Estimate", "Std. error", "p value")
                  %in% names(df)))
  expect_setequal(unique(df$Model),
                  c("(1) No FE", "(2) FE", "(3) FE + Controls"))
  # x2 only enters the third specification.
  expect_equal(unique(df$Model[df$Term == "x2"]), "(3) FE + Controls")
  # Estimates are numeric, not the starred display strings.
  expect_type(df$Estimate, "double")
  expect_equal(
    df$Estimate[df$Model == "(1) No FE" & df$Term == "x1"],
    unname(stats::coef(f1)["x1"])
  )
})

test_that("make_regtable_df labels terms via label_fun", {
  set.seed(1)
  d <- data.frame(y = rnorm(100), x1 = rnorm(100))
  f <- fixest::feols(y ~ x1, data = d)
  df <- make_regtable_df(f, f, f, engine = "fixest",
                         label_fun = function(x) ifelse(x == "x1",
                                                        "Rainfall (mm)", x))
  expect_true("Rainfall (mm)" %in% df$Variable)
  # The raw term is kept alongside the label.
  expect_true("x1" %in% df$Term)
})

test_that("make_regtable_df reads the RIF grid with matching column names", {
  grid <- data.frame(
    model     = c(1L, 3L, 3L, 3L, 3L),
    term      = c("x1", "x1", "x1", "x2", "x2"),
    tau       = c(0.5, 0.25, 0.75, 0.25, 0.75),
    estimate  = c(99, 1, 2, 3, 4),
    std.error = c(9, 0.1, 0.2, 0.3, 0.4),
    p.value   = c(0.9, 0.01, 0.02, 0.03, 0.04)
  )
  df <- make_regtable_df(NULL, NULL, NULL, engine = "rif", rif_grid = grid)

  # Only the full specification (model 3) is reported.
  expect_equal(nrow(df), 4L)
  expect_false(99 %in% df$Estimate)
  expect_equal(names(df)[1:3], c("Model", "Variable", "Quantile"))
  expect_true(all(c("Estimate", "Std. error", "p value") %in% names(df)))
})

test_that("make_regtable_df returns NULL when there is nothing to export", {
  expect_null(make_regtable_df(NULL, NULL, NULL))
  expect_null(make_regtable_df(NULL, NULL, NULL, engine = "rif",
                               rif_grid = data.frame(model = 1L, term = "x",
                                                     tau = 0.5, estimate = 1)))
})

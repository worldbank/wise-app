test_that("policy arm loading carries the policy coefficients' uncertainty (DOC-12)", {
  skip_if_not_installed("fixest")
  set.seed(1212)
  n <- 80L
  baseline <- data.frame(
    code = "BFA", year = "2018", survname = "w", loc_id = seq_len(n), int_month = 1L,
    temp = rnorm(n, 25, 2), electricity = rbinom(n, 1, 0.4), weight = 1
  )
  baseline$welfare <- exp(1 + 0.05 * baseline$temp + 0.4 * baseline$electricity -
    0.02 * baseline$temp * baseline$electricity + rnorm(n, 0, 0.3))
  policy <- baseline
  policy$electricity <- 1L
  fit <- fixest::feols(log(welfare) ~ temp * electricity, data = baseline)
  so <- list(name = "welfare", transform = "log")
  model_fit <- list(engine = "fixest", fit3 = fit, weather_terms = "temp",
    train_data = baseline)

  # Two years of weather per household
  ids <- rep(seq_len(n), 2L)
  sim_year <- rep(c(2030L, 2031L), each = n)
  weather <- baseline$temp[ids] + rep(c(1, 3), each = n)
  pipeline <- list(y_point = rep(0, 2L * n), svy_row_id = ids, sim_year = sim_year,
    weight = NULL, id_vec = ids)
  pipeline <- .policy_test_attach_exposure(pipeline, baseline, list(temp = weather))

  # The baseline loading of Step 2: active block (temp and its interaction)
  chol <- compute_chol_vcov(fit)
  chol <- suppressMessages(attach_active_mask(chol, baseline, baseline, "temp",
    "original", svy_reference = baseline, outcome_col = "welfare"))
  frame <- baseline[ids, ]
  frame$temp <- weather
  X <- stats::model.matrix(fit, data = frame, type = "rhs")
  pipeline$F_loading <- compute_factor_loading(X, chol)
  k_base <- ncol(pipeline$F_loading)
  expect_equal(k_base, 2L)

  run_identity <- "loading"
  context <- .build_decomposition_context(baseline, policy, model_fit, so,
    skip_coef = FALSE, run_identity = run_identity)
  annual <- .prepare_policy_annual_channels(context, run_identity)
  out <- apply_policy_delta_to_baseline(
    baseline, policy, model_fit, so, list(pipeline = pipeline, weather_raw = NULL),
    decomp_context = context, run_identity = run_identity,
    annual_channels = annual, chunk_size = 50L
  )
  F_pol <- out$hist_sim$pipeline$F_loading
  # electricity is outside the active block: one extra column
  expect_equal(dim(F_pol), c(2L * n, k_base + 1L))

  # The loading difference reproduces the exact variance of the policy
  # correction: d = (electricity: dD, temp:electricity: dD * temp)
  dD <- (policy$electricity - baseline$electricity)[ids]
  d <- cbind(dD, dD * weather)
  V <- stats::vcov(fit)[c("electricity", "temp:electricity"),
    c("electricity", "temp:electricity")]
  expected <- rowSums((d %*% V) * d)
  diff <- F_pol - cbind(pipeline$F_loading, 0)
  expect_equal(rowSums(diff^2), expected, tolerance = 1e-8)

  # Households whose electricity does not change keep their baseline loading
  same <- dD == 0
  expect_equal(unname(F_pol[same, seq_len(k_base)]), unname(pipeline$F_loading[same, ]),
    tolerance = 1e-12)
  expect_true(all(F_pol[same, k_base + 1L] == 0))
})

test_that("a run without a covariate lever keeps the baseline loading", {
  skip_if_not_installed("fixest")
  set.seed(5)
  n <- 40L
  baseline <- data.frame(
    code = "BFA", year = "2018", survname = "w", loc_id = seq_len(n), int_month = 1L,
    temp = rnorm(n, 25, 2), electricity = rbinom(n, 1, 0.4), weight = 1
  )
  baseline$welfare <- exp(1 + 0.05 * baseline$temp + rnorm(n, 0, 0.3))
  policy <- baseline
  fit <- fixest::feols(log(welfare) ~ temp + electricity, data = baseline)
  so <- list(name = "welfare", transform = "log")
  model_fit <- list(engine = "fixest", fit3 = fit, weather_terms = "temp",
    train_data = baseline)
  ids <- seq_len(n)
  pipeline <- list(y_point = rep(0, n), svy_row_id = ids, sim_year = rep(2030L, n),
    weight = NULL, id_vec = ids, F_loading = matrix(rnorm(n), n, 1L))
  pipeline <- .policy_test_attach_exposure(pipeline, baseline, list(temp = baseline$temp))
  context <- .build_decomposition_context(baseline, policy, model_fit, so,
    skip_coef = FALSE, run_identity = "x")
  annual <- .prepare_policy_annual_channels(context, "x")
  loading <- .policy_arm_loading(pipeline, annual,
    pipeline$weather_exposure, 20L)
  expect_null(loading)
})

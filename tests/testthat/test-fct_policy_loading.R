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

test_that("quantile policy arm loading reproduces the correction's response to the coefficients", {
  skip_if_not_installed("fixest")
  set.seed(77)
  n <- 300L
  baseline <- data.frame(
    code = "BFA", year = "2018", survname = "w", loc_id = seq_len(n), int_month = 1L,
    temp = rnorm(n, 3, 1), electricity = rbinom(n, 1, 0.4), weight = 1
  )
  baseline$welfare <- exp(1 - 0.1 * baseline$temp + 0.4 * baseline$electricity -
    0.05 * baseline$temp * baseline$electricity + rnorm(n, 0, 0.4))
  policy <- baseline
  policy$electricity <- 1L
  sm <- build_selected_model(model_type = "Unconditional quantile regression (RIF)",
    engine = "rif", interactions = "electricity", hh_covariates = "electricity",
    cluster = "loc_id")
  sw <- data.frame(name = "temp", cont_binned = "Continuous", stringsAsFactors = FALSE)
  so <- list(name = "welfare", type = "numeric", transform = "log")
  mf <- fit_model(baseline, so, sw, sm)

  ids <- rep(seq_len(n), 2L)
  weather <- baseline$temp[ids] + rep(c(0.5, 2), each = n)
  pipeline <- list(y_point = rep(0, 2L * n), svy_row_id = ids,
    sim_year = rep(c(2030L, 2031L), each = n), weight = NULL, id_vec = ids)
  pipeline <- .policy_test_attach_exposure(pipeline, baseline, list(temp = weather))
  run_identity <- "loading-rif"
  context <- .build_decomposition_context(baseline, policy, mf, so,
    skip_coef = FALSE, run_identity = run_identity)
  # temp and temp:electricity in each of the quantile equations (joint factor)
  k_base <- 2L * length(context$taus)
  pipeline$F_loading <- matrix(0, 2L * n, k_base)
  prepared <- .prepare_policy_annual_channels(context, run_identity)
  exposure <- .validate_policy_annual_exposure(pipeline, context)
  F_pol <- .policy_arm_loading_rif(pipeline, prepared, exposure, chunk_size = 200L)
  expect_false(is.null(F_pol))
  recipe <- prepared$loading_terms
  extra <- ncol(F_pol) - k_base
  # electricity is outside the active block, in each quantile equation
  expect_equal(extra, length(context$taus))

  # Move every grid coefficient along a shared draw z of the Cholesky basis
  # and compare the response of the correction with F z
  rows_by_k <- .policy_loading_rows_rif(context, k_base, recipe$names)
  z <- rnorm(ncol(F_pol))
  eps <- 1e-3
  values <- as.list(context, all.names = TRUE)
  index <- values$rif_curve_index
  for (term in recipe$names) {
    grid_k <- match(round(index[[term]]$tau, 8), round(values$taus, 8))
    index[[term]]$estimate <- index[[term]]$estimate +
      eps * vapply(grid_k, function(k) sum(rows_by_k[[k]][term, ] * z), 0)
  }
  values$rif_curve_index <- index
  values$delta_main <- NULL
  values$beta_at <- function(term, tau) {
    curve <- index[[term]]
    if (is.null(curve)) return(rep(0, length(tau)))
    stats::approx(curve$tau, curve$estimate, xout = tau, rule = 2)$y
  }
  moved <- .finalize_decomposition_context(list2env(values, parent = emptyenv()))
  prepared2 <- .prepare_policy_annual_channels(moved, run_identity)
  base <- .policy_annual_channels(pipeline, prepared, run_identity)
  after <- .policy_annual_channels(pipeline, prepared2, run_identity)
  response <- (after$delta_total - base$delta_total) / eps
  expect_gt(max(abs(response)), 1e-3)
  expect_equal(as.numeric(F_pol %*% z), response, tolerance = 1e-4)
})

test_that("a RIF fit records the fallback to independent equations, and only then", {
  skip_if_not_installed("fixest")
  set.seed(78)
  n <- 300L
  baseline <- data.frame(
    code = "BFA", year = "2018", survname = "w", loc_id = seq_len(n), int_month = 1L,
    temp = rnorm(n, 3, 1), weight = 1
  )
  baseline$welfare <- exp(1 - 0.1 * baseline$temp + rnorm(n, 0, 0.4))
  so <- list(name = "welfare", type = "numeric", transform = "log")
  sw <- data.frame(name = "temp", cont_binned = "Continuous", stringsAsFactors = FALSE)
  fit_with <- function(cluster) {
    sm <- build_selected_model(model_type = "Unconditional quantile regression (RIF)",
      engine = "rif", cluster = cluster)
    suppressWarnings(fit_model(baseline, so, sw, sm))
  }
  kinds <- function(mf) vapply(mf$fallbacks, function(x) x$kind, "")
  # clustered: the joint covariance is built and stored, no fallback
  clustered <- fit_with("loc_id")
  expect_false("rif_joint_covariance" %in% kinds(clustered))
  expect_false(is.null(attr(clustered$fit3, "wise_joint_vcov")))
  # no clustering: the stacked sandwich cannot match the fit's covariance
  plain <- fit_with(NULL)
  expect_true("rif_joint_covariance" %in% kinds(plain))
  expect_null(attr(plain$fit3, "wise_joint_vcov"))
  expect_true(any(grepl("independent quantile equations", model_fit_table(plain)$text, fixed = TRUE)))
})

test_that("quantile policy effect and loading do not depend on the level of the weather (MR-12)", {
  skip_if_not_installed("fixest")
  set.seed(79)
  n <- 300L
  baseline <- data.frame(
    code = "BFA", year = "2018", survname = "w", loc_id = seq_len(n), int_month = 1L,
    temp = rnorm(n, 3, 1), weight = 1
  )
  baseline$welfare <- exp(1 - 0.1 * baseline$temp + rnorm(n, 0, 0.5))
  poor <- baseline$welfare <= stats::quantile(baseline$welfare, 0.3)
  policy <- baseline
  policy[[SP_TRANSFER_COL]] <- ifelse(poor, 0.5 * stats::median(baseline$welfare), 0)
  sm <- build_selected_model(model_type = "Unconditional quantile regression (RIF)",
    engine = "rif", cluster = "loc_id")
  sw <- data.frame(name = "temp", cont_binned = "Continuous", stringsAsFactors = FALSE)
  so <- list(name = "welfare", type = "numeric", transform = "log")
  fit_df <- baseline
  fit_df$welfare <- log(baseline$welfare)  # Step 1 fits on the model scale
  mf <- suppressWarnings(fit_model(fit_df, so, sw, sm))
  ids <- rep(seq_len(n), 2L)
  change <- rep(c(0.5, 2), each = n)

  # The same households and the same weather change, recoded as temp + shift
  run <- function(shift) {
    svy <- baseline
    svy$temp <- svy$temp + shift
    pol <- policy
    pol$temp <- pol$temp + shift
    pipeline <- list(y_point = rep(0, 2L * n), svy_row_id = ids,
      sim_year = rep(c(2030L, 2031L), each = n), weight = NULL, id_vec = ids)
    pipeline <- .policy_test_attach_exposure(pipeline, svy, list(temp = svy$temp[ids] + change))
    run_identity <- "level-invariance"
    context <- .build_decomposition_context(svy, pol, mf, so,
      skip_coef = FALSE, run_identity = run_identity)
    pipeline$F_loading <- matrix(0, 2L * n, length(context$taus))
    prepared <- .prepare_policy_annual_channels(context, run_identity)
    exposure <- .validate_policy_annual_exposure(pipeline, context)
    list(
      channels = .policy_annual_channels(pipeline, prepared, run_identity),
      loading = .policy_arm_loading_rif(pipeline, prepared, exposure, chunk_size = 200L)
    )
  }
  ref <- run(0)
  shifted <- run(50)
  expect_gt(max(abs(ref$channels$delta_res1)), 1e-6)
  expect_equal(shifted$channels$delta_total, ref$channels$delta_total, tolerance = 1e-10)
  expect_equal(shifted$channels$delta_main, ref$channels$delta_main, tolerance = 1e-10)
  expect_equal(shifted$channels$delta_res1, ref$channels$delta_res1, tolerance = 1e-10)
  expect_false(is.null(ref$loading))
  expect_equal(shifted$loading, ref$loading, tolerance = 1e-10)
})

test_that("quantile policy arm without a policy has no repositioning and keeps the baseline loading (MR-12)", {
  skip_if_not_installed("fixest")
  set.seed(80)
  n <- 200L
  baseline <- data.frame(
    code = "BFA", year = "2018", survname = "w", loc_id = seq_len(n), int_month = 1L,
    temp = rnorm(n, 3, 1), weight = 1
  )
  baseline$welfare <- exp(1 - 0.1 * baseline$temp + rnorm(n, 0, 0.5))
  policy <- baseline
  policy[[SP_TRANSFER_COL]] <- 0
  sm <- build_selected_model(model_type = "Unconditional quantile regression (RIF)",
    engine = "rif", cluster = "loc_id")
  sw <- data.frame(name = "temp", cont_binned = "Continuous", stringsAsFactors = FALSE)
  so <- list(name = "welfare", type = "numeric", transform = "log")
  fit_df <- baseline
  fit_df$welfare <- log(baseline$welfare)  # Step 1 fits on the model scale
  mf <- suppressWarnings(fit_model(fit_df, so, sw, sm))
  ids <- rep(seq_len(n), 2L)
  pipeline <- list(y_point = rep(0, 2L * n), svy_row_id = ids,
    sim_year = rep(c(2030L, 2031L), each = n), weight = NULL, id_vec = ids)
  pipeline <- .policy_test_attach_exposure(pipeline, baseline,
    list(temp = baseline$temp[ids] + rep(c(0.5, 2), each = n)))
  context <- .build_decomposition_context(baseline, policy, mf, so,
    skip_coef = FALSE, run_identity = "no-policy")
  pipeline$F_loading <- matrix(0, 2L * n, length(context$taus))
  prepared <- .prepare_policy_annual_channels(context, "no-policy")
  ch <- .policy_annual_channels(pipeline, prepared, "no-policy")
  expect_equal(ch$delta_main, rep(0, 2L * n))
  expect_equal(ch$delta_total, rep(0, 2L * n))
  exposure <- .validate_policy_annual_exposure(pipeline, context)
  expect_null(.policy_arm_loading_rif(pipeline, prepared, exposure, chunk_size = 200L))
})

# Development-only helpers for the opt-in Step 3 benchmark path.

.bench_step3_policy_fixtures <- function(labels = c(
  "covariate", "targeted_sp", "combined"
)) {
  infra <- list(elec_universal = FALSE, elec_access_change_pct = 30)
  sp <- list(
    budget_mode = "transfer_first",
    transfer_n_payments = 4L,
    transfer_amount_usd = 30,
    targeting = "exante_poor",
    targeting_threshold = 30,
    inclusion_error_pct = 10,
    exclusion_error_pct = 10
  )
  fixtures <- list(
    covariate = list(infra = infra),
    targeted_sp = list(sp = sp),
    combined = list(infra = infra, sp = sp)
  )
  unknown <- setdiff(labels, names(fixtures))
  if (length(unknown)) {
    stop("Unknown Step 3 policy fixture(s): ", paste(unknown, collapse = ", "),
         call. = FALSE)
  }
  fixtures[labels]
}

.bench_step3_model_terms <- function(model_fit) {
  if (identical(model_fit$engine, "rif")) {
    return(unique(as.character(model_fit$rif_grid$term)))
  }
  names(tryCatch(stats::coef(model_fit$fit3), error = function(e) numeric(0)))
}

.bench_step3_changed_columns <- function(baseline, policy) {
  columns <- union(names(baseline), names(policy))
  columns[vapply(columns, function(column) {
    !column %in% names(baseline) || !column %in% names(policy) ||
      !identical(baseline[[column]], policy[[column]])
  }, logical(1))]
}

.bench_step3_pipelines <- function(hist_sim, saved_scenarios) {
  out <- list(historical = hist_sim$pipeline)
  for (scenario_name in names(saved_scenarios)) {
    scenario <- saved_scenarios[[scenario_name]]
    for (member_name in names(scenario$pipelines)) {
      out[[paste(scenario_name, member_name, sep = " / ")]] <-
        scenario$pipelines[[member_name]]
    }
  }
  out
}

.bench_step3_aggregate <- function(policy_result, methods, residuals,
                                   skip_coef, is_log, seed) {
  hist_sim <- policy_result$hist_sim
  pipes <- list(historical = list(
    pipe = hist_sim$pipeline,
    shared_context = hist_sim$shared_context %||% NULL
  ))
  for (scenario_name in names(policy_result$saved_scenarios)) {
    scenario <- policy_result$saved_scenarios[[scenario_name]]
    for (member_name in names(scenario$pipelines)) {
      pipes[[paste(scenario_name, member_name, sep = " / ")]] <- list(
        pipe = scenario$pipelines[[member_name]],
        shared_context = scenario$shared_context %||% NULL
      )
    }
  }
  out <- list()
  for (method in methods) {
    poverty_line <- if (method %in% c("headcount_ratio", "gap", "fgt2")) 3 else NULL
    out[[method]] <- .bench_aggregate_pipelines(
      pipelines = pipes,
      method = method,
      weighted = TRUE,
      pov_line = poverty_line,
      residuals = residuals,
      is_log = is_log,
      skip_coef = skip_coef,
      seed = seed
    )
  }
  out
}

.bench_step3_decompose_future <- function(policy_result, svy_baseline,
                                          svy_policy, model_fit, so,
                                          skip_coef, deltas, F_hat) {
  rows <- list()
  for (scenario_name in names(policy_result$saved_scenarios)) {
    scenario <- policy_result$saved_scenarios[[scenario_name]]
    weather <- step2_resolve_weather(scenario$weather_raw, scenario)
    if (is.null(weather)) next
    if ("timestamp" %in% names(weather)) {
      weather_year <- as.integer(format(weather$timestamp, "%Y"))
      years <- sort(unique(weather_year))
    } else {
      weather_year <- NULL
      years <- NA_integer_
    }
    for (year in years) {
      weather_slice <- if (is.na(year)) weather else weather[weather_year == year, ]
      value <- decompose_policy_effect(
        svy_baseline = svy_baseline,
        svy_policy = svy_policy,
        model_fit = model_fit,
        so = so,
        weather_raw = weather_slice,
        skip_coef = skip_coef,
        deltas = deltas,
        F_hat = F_hat
      )
      if (is.null(value)) {
        stop("Future effect decomposition produced no results.", call. = FALSE)
      }
      value$scenario <- scenario_name
      value$sim_year <- year
      value$year_start <- scenario$year_range[[1L]] %||% NA_integer_
      value$year_end <- scenario$year_range[[2L]] %||% NA_integer_
      rows[[length(rows) + 1L]] <- value
    }
  }
  if (!length(rows)) return(data.frame())
  dplyr::bind_rows(rows)
}

.bench_step3_fingerprint <- function(svy_baseline, svy_policy, policy_result,
                                     historical_decomposition,
                                     future_decomposition, aggregations) {
  changed <- .bench_step3_changed_columns(svy_baseline, svy_policy)
  pipes <- .bench_step3_pipelines(
    policy_result$hist_sim, policy_result$saved_scenarios
  )
  decomp_columns <- c(
    "id", "decile", "sp_eligible", "delta_main", "delta_res1", "delta_res2",
    "delta_total", "sd_total", "scenario", "sim_year"
  )
  canonical <- list(
    changed_columns = changed,
    policy_values = svy_policy[intersect(changed, names(svy_policy))],
    pipeline_y_point = lapply(pipes, function(pipe) pipe$y_point),
    historical_decomposition = historical_decomposition[
      intersect(decomp_columns, names(historical_decomposition))
    ],
    future_decomposition = future_decomposition[
      intersect(decomp_columns, names(future_decomposition))
    ],
    aggregations = aggregations
  )
  digest::digest(canonical, algo = "sha256", serialize = TRUE)
}

.bench_step3_empty_sizes <- function() {
  list(object_bytes = NA_real_, serialized_bytes = NA_real_,
       deduplicated_bytes = NA_real_)
}

.bench_run_step3 <- function(baseline_result, input, model_label, policy_label,
                             policy_fixture, identity, config, size_fn,
                             rss_state_fn, rss_sample_fn) {
  started_total <- proc.time()[["elapsed"]]
  rss_state <- rss_state_fn()
  rss_sample_fn(rss_state)
  model_fit <- input$models[[model_label]]
  hist_sim <- baseline_result$hist_sim_result
  saved_scenarios <- baseline_result$new_scenarios %||% list()
  svy_baseline <- input$svy
  so <- input$so
  skip_coef <- identical(identity$uncertainty, "disabled")
  status <- "ok"
  error_text <- ""
  policy_application_seconds <- NA_real_
  analytic_delta_seconds <- NA_real_
  historical_decomposition_seconds <- NA_real_
  future_decomposition_seconds <- NA_real_
  results_aggregation_seconds <- NA_real_
  svy_policy <- policy_result <- historical_decomposition <- NULL
  future_decomposition <- data.frame()
  aggregations <- list()

  tryCatch({
    t0 <- proc.time()[["elapsed"]]
    svy_policy <- do.call(
      apply_policy_to_svy,
      c(list(
        svy = svy_baseline,
        model_vars = .bench_step3_model_terms(model_fit),
        analysis_unit = config$unit,
        seed = config$seed
      ), policy_fixture)
    )
    policy_application_seconds <- proc.time()[["elapsed"]] - t0
    changed_columns <- .bench_step3_changed_columns(svy_baseline, svy_policy)
    if (!length(changed_columns)) {
      stop("The policy fixture did not change the benchmark survey.", call. = FALSE)
    }
    if (!is.null(policy_fixture$infra) &&
        !"electricity" %in% changed_columns) {
      stop(
        "The covariate fixture requires a non-universal electricity column ",
        "present in the fitted model.", call. = FALSE
      )
    }
    if (!is.null(policy_fixture$sp)) {
      transfer <- svy_policy[[SP_TRANSFER_COL]]
      if (is.null(transfer) || !any(is.finite(transfer) & transfer != 0)) {
        stop("The social-protection fixture produced no transfer.", call. = FALSE)
      }
    }
    rss_sample_fn(rss_state)

    deltas <- .compute_policy_deltas(
      svy_baseline, svy_policy, so$name, model_fit$weather_terms
    )
    F_hat <- if (identical(model_fit$engine, "rif") &&
                 !is.null(model_fit$train_data) &&
                 so$name %in% names(model_fit$train_data)) {
      stats::ecdf(model_fit$train_data[[so$name]])
    } else NULL

    t0 <- proc.time()[["elapsed"]]
    policy_result <- apply_policy_delta_to_baseline(
      svy_baseline = svy_baseline,
      svy_policy = svy_policy,
      model_fit = model_fit,
      so = so,
      hist_sim_baseline = hist_sim,
      saved_scenarios_baseline = saved_scenarios,
      skip_coef = skip_coef,
      deltas = deltas,
      F_hat = F_hat
    )
    analytic_delta_seconds <- proc.time()[["elapsed"]] - t0
    if (is.null(policy_result)) {
      stop("Policy delta application produced no results.", call. = FALSE)
    }
    rss_sample_fn(rss_state)

    t0 <- proc.time()[["elapsed"]]
    historical_decomposition <- decompose_policy_effect(
      svy_baseline = svy_baseline,
      svy_policy = svy_policy,
      model_fit = model_fit,
      so = so,
      weather_raw = step2_resolve_weather(hist_sim$weather_raw, hist_sim),
      skip_coef = skip_coef,
      deltas = deltas,
      F_hat = F_hat
    )
    historical_decomposition_seconds <- proc.time()[["elapsed"]] - t0
    if (is.null(historical_decomposition)) {
      stop("Historical effect decomposition produced no results.", call. = FALSE)
    }
    rss_sample_fn(rss_state)

    t0 <- proc.time()[["elapsed"]]
    future_decomposition <- .bench_step3_decompose_future(
      policy_result, svy_baseline, svy_policy, model_fit, so, skip_coef,
      deltas, F_hat
    )
    future_decomposition_seconds <- proc.time()[["elapsed"]] - t0
    rss_sample_fn(rss_state)

    t0 <- proc.time()[["elapsed"]]
    aggregations <- .bench_step3_aggregate(
      policy_result, config$aggregation,
      hist_sim$residuals %||% "original", skip_coef,
      identical(so$transform, "log"), config$seed
    )
    results_aggregation_seconds <- proc.time()[["elapsed"]] - t0
    rss_sample_fn(rss_state)
  }, error = function(e) {
    status <<- "error"
    error_text <<- conditionMessage(e)
  })

  sizes <- list(
    policy_survey = if (is.null(svy_policy)) .bench_step3_empty_sizes() else size_fn(svy_policy),
    policy_result = if (is.null(policy_result)) .bench_step3_empty_sizes() else size_fn(policy_result),
    historical_decomposition = if (is.null(historical_decomposition)) {
      .bench_step3_empty_sizes()
    } else size_fn(historical_decomposition),
    future_decomposition = size_fn(future_decomposition),
    retained = if (identical(status, "ok")) size_fn(list(
      policy_survey = svy_policy,
      policy_result = policy_result,
      historical_decomposition = historical_decomposition,
      future_decomposition = future_decomposition,
      aggregations = aggregations
    )) else .bench_step3_empty_sizes()
  )
  fingerprint <- if (identical(status, "ok")) {
    .bench_step3_fingerprint(
      svy_baseline, svy_policy, policy_result, historical_decomposition,
      future_decomposition, aggregations
    )
  } else NA_character_
  rss_sample_fn(rss_state)

  data.frame(
    country = identity$country,
    model = model_label,
    workload = identity$workload,
    payload_mode = identity$payload_mode,
    weather_storage = identity$weather_storage,
    weather_collect = identity$weather_collect,
    join_cache = identity$join_cache,
    direct_rif_predictions = identity$direct_rif_predictions,
    uncertainty = identity$uncertainty,
    cache = identity$cache,
    repetition = identity$repetition,
    fixture_mode = identity$fixture_mode,
    evidence_class = identity$evidence_class,
    runtime_options_executed = !identical(
      identity$evidence_class, "smoke_only_not_production_evidence"
    ),
    policy_fixture = policy_label,
    seed = config$seed,
    status = status,
    error = error_text,
    elapsed_seconds = proc.time()[["elapsed"]] - started_total,
    policy_seconds = policy_application_seconds + analytic_delta_seconds,
    policy_application_seconds = policy_application_seconds,
    analytic_delta_seconds = analytic_delta_seconds,
    decomposition_seconds = historical_decomposition_seconds +
      future_decomposition_seconds,
    historical_decomposition_seconds = historical_decomposition_seconds,
    future_decomposition_seconds = future_decomposition_seconds,
    results_aggregation_seconds = results_aggregation_seconds,
    parent_peak_rss_kb_sampled = rss_state$rss_parent_peak_kb,
    process_tree_peak_rss_kb_sampled = rss_state$rss_tree_peak_kb,
    policy_survey_object_bytes = sizes$policy_survey$object_bytes,
    policy_survey_serialized_bytes = sizes$policy_survey$serialized_bytes,
    policy_result_object_bytes = sizes$policy_result$object_bytes,
    policy_result_serialized_bytes = sizes$policy_result$serialized_bytes,
    historical_decomposition_object_bytes = sizes$historical_decomposition$object_bytes,
    historical_decomposition_serialized_bytes = sizes$historical_decomposition$serialized_bytes,
    future_decomposition_object_bytes = sizes$future_decomposition$object_bytes,
    future_decomposition_serialized_bytes = sizes$future_decomposition$serialized_bytes,
    retained_object_bytes = sizes$retained$object_bytes,
    retained_serialized_bytes = sizes$retained$serialized_bytes,
    retained_deduplicated_bytes = sizes$retained$deduplicated_bytes,
    n_survey_rows = nrow(svy_baseline),
    n_changed_columns = if (is.null(svy_policy)) NA_integer_ else
      length(.bench_step3_changed_columns(svy_baseline, svy_policy)),
    n_future_scenarios = length(saved_scenarios),
    n_future_members = sum(vapply(saved_scenarios, function(x) {
      length(x$pipelines %||% list())
    }, integer(1))),
    n_historical_decomposition_rows = if (is.null(historical_decomposition)) {
      NA_integer_
    } else nrow(historical_decomposition),
    n_future_decomposition_rows = nrow(future_decomposition),
    output_fingerprint_sha256 = fingerprint,
    stringsAsFactors = FALSE
  )
}

.bench_small_step3_input <- function(country = "fixture", n = 120L,
                                     seed = 123L) {
  withr::with_seed(seed, {
    svy <- data.frame(
      hhid = seq_len(n),
      loc_id = rep(seq_len(6L), length.out = n),
      year = 2020L,
      welfare = exp(0.8 + seq(-0.4, 0.4, length.out = n) +
                      stats::rnorm(n, sd = 0.08)),
      hhsize = rep(2:5, length.out = n),
      weight = seq(0.8, 1.2, length.out = n),
      temp = seq(20, 30, length.out = n),
      electricity = rep(c(0L, 1L, 0L), length.out = n),
      stringsAsFactors = FALSE
    )
  })
  ols_fit <- stats::lm(log(welfare) ~ temp * electricity, data = svy)
  taus <- seq(0.1, 0.9, by = 0.1)
  rif_grid <- expand.grid(
    model = 3L,
    term = c("(Intercept)", "temp", "electricity", "temp:electricity"),
    tau = taus,
    stringsAsFactors = FALSE
  )
  term_base <- c(
    "(Intercept)" = 0.8, temp = 0.015, electricity = 0.12,
    "temp:electricity" = 0.004
  )
  rif_grid$estimate <- unname(term_base[rif_grid$term]) * (0.8 + 0.4 * rif_grid$tau)
  rif_grid$std.error <- abs(rif_grid$estimate) * 0.1 + 0.001
  models <- list(
    ols = list(
      engine = "fixest", fit3 = ols_fit, weather_terms = "temp",
      train_data = svy
    ),
    rif = list(
      engine = "rif", fit3 = NULL, weather_terms = "temp",
      train_data = svy, rif_grid = rif_grid, taus = taus
    )
  )
  list(
    country = country,
    sw = data.frame(name = "temp", units = "deg C", stringsAsFactors = FALSE),
    so = list(name = "welfare", transform = "log"),
    svy = svy,
    ss = data.frame(code = country, year = 2020L),
    cp = list(),
    models = models,
    sim_dates = c("2019-01-01", "2020-12-31"),
    stored_breaks = NULL,
    fixture_mode = "smoke",
    metadata = list(
      n_survey_rows = n,
      source = "deterministic in-memory fixture",
      evidence_class = "smoke_only_not_production_evidence"
    )
  )
}

.bench_small_step2_result <- function(input, model_label, workload) {
  model_fit <- input$models[[model_label]]
  svy <- input$svy
  years <- 2019:2020
  make_weather <- function(year_values, offset = 0) {
    grid <- expand.grid(
      loc_id = sort(unique(svy$loc_id)),
      year = year_values,
      KEEP.OUT.ATTRS = FALSE
    )
    grid$timestamp <- as.Date(paste0(grid$year, "-07-01"))
    grid$temp <- 22 + grid$loc_id * 0.5 + (grid$year - min(grid$year)) * 0.1 + offset
    grid
  }
  make_pipeline <- function(year_values, weather, member_offset = 0) {
    row_id <- rep(seq_len(nrow(svy)), times = length(year_values))
    sim_year <- rep(year_values, each = nrow(svy))
    hazard <- mean(weather$temp) + member_offset
    y_base <- if (identical(model_label, "rif")) {
      log(svy$welfare) + 0.01 * (hazard - mean(svy$temp))
    } else {
      as.numeric(stats::predict(model_fit$fit3, newdata = svy)) +
        0.01 * (hazard - mean(svy$temp))
    }
    list(
      y_point = rep(y_base, times = length(year_values)),
      F_loading = NULL,
      sim_year = sim_year,
      weight = rep(svy$weight, times = length(year_values)),
      id_vec = rep(svy$hhid, times = length(year_values)),
      id_col = "hhid",
      svy_row_id = row_id,
      train_aug = if (identical(model_label, "rif")) NULL else
        transform(svy, .resid = stats::residuals(model_fit$fit3)),
      weather_raw = weather
    )
  }
  historical_weather <- make_weather(years)
  historical <- list(
    pipeline = make_pipeline(years, historical_weather),
    weather_raw = historical_weather,
    so = input$so,
    svy = svy,
    train_data = model_fit$train_data,
    residuals = if (identical(model_label, "rif")) "none" else "original"
  )
  scenarios <- list()
  if (!identical(workload, "historical")) {
    future_years <- if (identical(workload, "one_ssp_one_period")) 2030:2031 else 2030:2032
    future_weather <- make_weather(future_years, offset = 1.5)
    member_count <- if (identical(workload, "one_ssp_one_period")) 1L else 3L
    members <- setNames(lapply(seq_len(member_count), function(i) {
      make_pipeline(future_years, future_weather, member_offset = (i - 1L) * 0.2)
    }), paste0("member_", seq_len(member_count)))
    scenarios[["SSP2-4.5 / fixture"]] <- list(
      pipelines = members,
      weather_raw = future_weather,
      year_range = range(future_years),
      residuals = historical$residuals
    )
  }
  list(
    hist_sim_result = historical,
    new_scenarios = scenarios,
    chol_obj = NULL,
    n_keys = 1L + sum(vapply(scenarios, function(x) length(x$pipelines), integer(1))),
    total_runs = length(years),
    t_elapsed = 0,
    failures = list(),
    n_keys_ok = 1L + sum(vapply(scenarios, function(x) length(x$pipelines), integer(1)))
  )
}

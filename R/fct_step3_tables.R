# Step 3 results views ----
# The Shiny-free views behind the Step 3 Results pane: the annual series and
# threshold rows of the baseline and policy arms, the paired policy-minus-baseline
# effects and the threshold table with the baseline-anchored tails. The Results
# pane (`.wire_results_pane()`) calls them from its reactives; the batch tables
# call them with the same arguments, so a stored table equals what the pane shows.

# Matrix transform of one aggregation table; the pane passes a caching version.
#' @noRd
.step3_mm <- function(matrix_transform) {
  if (is.function(matrix_transform)) {
    matrix_transform
  } else {
    function(tbl, source, scenario) by_model_matrix(tbl)
  }
}

#' Annual series of one arm, one row per member and year
#'
#' @param agg_hist,agg_scn Aggregation of the historical run (`list(out = )`) and
#'   of each scenario.
#' @param hist_ref Deviation reference subtracted from the values.
#' @param source_label `"Baseline"` or `"Policy"`.
#' @param scenarios Names of the scenarios to include.
#' @param matrix_transform Optional `function(tbl, source, scenario)` giving
#'   `by_model_matrix(tbl)` (the pane caches it).
#' @return A tibble.
#' @noRd
step3_timeseries_rows <- function(agg_hist, agg_scn, hist_ref, source_label, scenarios,
                                  matrix_transform = NULL) {
  mm_fn <- .step3_mm(matrix_transform)
  one <- function(tbl, scenario_label, is_hist) {
    if (is.null(tbl) || nrow(tbl) == 0L) {
      return(NULL)
    }
    mm <- mm_fn(
      tbl, source_label,
      if (is_hist) "Historical" else scenario_label
    )
    if (is.null(mm)) {
      return(NULL)
    }
    vals <- mm$vals
    dplyr::bind_rows(lapply(seq_len(nrow(vals)), function(i) {
      tibble::tibble(
        scenario      = scenario_label,
        source        = source_label,
        model_id      = mm$model_ids[[i]],
        sim_year      = as.integer(mm$sim_years),
        value         = vals[i, ] - hist_ref,
        is_historical = is_hist
      )
    }))
  }
  rows <- list(one(agg_hist$out, "Historical", TRUE))
  if (!is.null(agg_scn)) {
    for (dk in names(agg_scn)) {
      if (!dk %in% scenarios) next
      rows[[length(rows) + 1L]] <- one(agg_scn[[dk]]$out, dk, FALSE)
    }
  }
  dplyr::bind_rows(Filter(Negate(is.null), rows))
}

#' Return-period rows of one arm
#'
#' The adverse-year values of each scenario with the coefficient, ensemble and
#' pooled bands, per return period the arm's years support.
#'
#' @inheritParams step3_timeseries_rows
#' @param bq_coef,bq_ens Quantile pairs of the coefficient and ensemble bands.
#' @param method Aggregation metric.
#' @param so Selected outcome.
#' @return A tibble.
#' @noRd
step3_threshold_rows <- function(agg_hist, agg_scn, hist_ref, source_label, bq_coef, bq_ens,
                                 method, so, scenarios, matrix_transform = NULL) {
  mm_fn <- .step3_mm(matrix_transform)
  z_lo <- stats::qnorm(bq_coef[["lo"]])
  z_hi <- stats::qnorm(bq_coef[["hi"]])
  adverse_tail <- metric_metadata(method, so)$adverse_tail
  RPs <- c(RP_LOW, c("1:1" = 0.5), RP_HIGH)
  one <- function(tbl, scenario_label, is_hist) {
    if (is.null(tbl) || nrow(tbl) == 0L) {
      return(NULL)
    }
    mm <- mm_fn(
      tbl, source_label,
      if (is_hist) "Historical" else scenario_label
    )
    if (is.null(mm)) {
      return(NULL)
    }
    vals <- mm$vals
    sds <- mm$sds
    n_yrs <- ncol(vals)
    n_pts <- if (is_hist) sum(is.finite(as.numeric(vals))) else n_yrs
    rp_ok <- vapply(RPs, function(p) {
      all(vapply(seq_len(nrow(vals)), function(i) {
        adverse_year_support(vals[i, ], suppressWarnings(as.numeric(mm$sim_years)),
          p, adverse_tail)$status == "ok"
      }, logical(1)))
    }, logical(1))
    RPs_keep <- RPs[rp_ok]
    if (length(RPs_keep) == 0L) {
      return(NULL)
    }
    # Per-model rank-interp at each kept RP (matrix: model * RP) - shape
    # guaranteed by the helper (see by_model_rp_matrix()).
    per_model_rp <- matrix(NA_real_, nrow(vals), length(RPs_keep),
      dimnames = list(mm$model_ids, names(RPs_keep)))
    per_model_sd_at_rp <- per_model_rp
    support_records <- list()
    for (i in seq_len(nrow(vals))) for (j in seq_along(RPs_keep)) {
      support <- adverse_year_support(vals[i, ], suppressWarnings(as.numeric(mm$sim_years)),
        RPs_keep[[j]], adverse_tail)
      support_records[[length(support_records) + 1L]] <- data.frame(
        scenario = scenario_label, model_id = mm$model_ids[[i]],
        probability = RPs_keep[[j]], as.list(support), stringsAsFactors = FALSE)
      if (identical(support$status, "ok")) {
        per_model_rp[i, j] <- apply_adverse_year_support(vals[i, ],
          suppressWarnings(as.numeric(mm$sim_years)), support)$value
        per_model_sd_at_rp[i, j] <- apply_adverse_year_support(sds[i, ],
          suppressWarnings(as.numeric(mm$sim_years)), support)$value
      }
    }
    central_vec <- vapply(seq_len(ncol(per_model_rp)), function(j) {
      if (!all(is.finite(per_model_rp[, j]))) NA_real_ else mean(per_model_rp[, j])
    }, numeric(1))
    coef_sd_vec <- if (is_hist) {
      per_model_sd_at_rp[1L, ]
    } else {
      apply(per_model_sd_at_rp, 2L, stats::median, na.rm = TRUE)
    }
    coef_lo_vec <- central_vec + z_lo * coef_sd_vec
    coef_hi_vec <- central_vec + z_hi * coef_sd_vec
    intermod_lo_vec <- if (is_hist) {
      rep(NA_real_, length(RPs_keep))
    } else {
      apply(per_model_rp, 2L, stats::quantile, probs = bq_ens[["lo"]], na.rm = TRUE)
    }
    intermod_hi_vec <- if (is_hist) {
      rep(NA_real_, length(RPs_keep))
    } else {
      apply(per_model_rp, 2L, stats::quantile, probs = bq_ens[["hi"]], na.rm = TRUE)
    }
    var_across_at_rp <- if (is_hist) {
      rep(0, length(RPs_keep))
    } else {
      apply(per_model_rp, 2L, stats::var, na.rm = TRUE)
    }
    var_across_at_rp[is.na(var_across_at_rp)] <- 0
    sd_total_vec <- sqrt(pmax(coef_sd_vec^2 + var_across_at_rp, 0, na.rm = FALSE))
    total_lo_vec <- central_vec + z_lo * sd_total_vec
    total_hi_vec <- central_vec + z_hi * sd_total_vec
    make_row <- function(estimate, vec) {
      tibble::tibble(
        scenario      = scenario_label,
        source        = source_label,
        Estimate      = estimate,
        rp_name       = names(RPs_keep),
        rp_label      = names(RPs_keep),
        value         = vec - hist_ref,
        n_obs         = n_pts,
        is_historical = is_hist
      )
    }
    coef_lo_lbl <- paste0("Coef ", pct_label(bq_coef[["lo"]]))
    coef_hi_lbl <- paste0("Coef ", pct_label(bq_coef[["hi"]]))
    ens_lo_lbl <- paste0("Ensemble ", pct_label(bq_ens[["lo"]], use_minmax = TRUE))
    ens_hi_lbl <- paste0("Ensemble ", pct_label(bq_ens[["hi"]], use_minmax = TRUE))
    pooled_lo_lbl <- paste0("Pooled ", pct_label(bq_coef[["lo"]]))
    pooled_hi_lbl <- paste0("Pooled ", pct_label(bq_coef[["hi"]]))
    rows <- list(
      make_row(if (is_hist) "Single historical estimate" else "Equal-model mean", central_vec),
      make_row(coef_lo_lbl, coef_lo_vec),
      make_row(coef_hi_lbl, coef_hi_vec)
    )
    if (!is_hist) {
      ensemble_rows <- if (identical(ens_lo_lbl, ens_hi_lbl)) {
        list(make_row(ens_lo_lbl, central_vec))
      } else {
        list(
          make_row(ens_lo_lbl, intermod_lo_vec),
          make_row(ens_hi_lbl, intermod_hi_vec)
        )
      }
      rows <- c(rows, ensemble_rows, list(
        make_row(pooled_lo_lbl, total_lo_vec),
        make_row(pooled_hi_lbl, total_hi_vec)
      ))
    }
    out <- dplyr::bind_rows(rows)
    attr(out, "adverse_support") <- dplyr::bind_rows(support_records)
    out
  }
  rows <- list(one(agg_hist$out, "Historical", TRUE))
  if (!is.null(agg_scn)) {
    for (dk in names(agg_scn)) {
      if (!dk %in% scenarios) next
      rows[[length(rows) + 1L]] <- one(agg_scn[[dk]]$out, dk, FALSE)
    }
  }
  dplyr::bind_rows(Filter(Negate(is.null), rows))
}

#' The threshold table of a Step 3 run
#'
#' Baseline and policy return-period rows, with the central rows of the
#' return periods replaced by the baseline-anchored tails of the metric
#' decomposition.
#'
#' @param base_hist,base_scn,pol_hist,pol_scn Aggregations of the baseline and
#'   policy arms (`list(out = )` each; scenarios as a named list).
#' @param hist_ref Deviation reference.
#' @param bq_coef,bq_ens Quantile pairs of the coefficient and ensemble bands.
#' @param method,so Metric and selected outcome.
#' @param scenarios Names of the scenarios to include.
#' @param tails The `return_period` table of the metric decomposition.
#' @param matrix_transform Optional cached `by_model_matrix()` accessor.
#' @return A tibble.
#' @noRd
step3_threshold_table <- function(base_hist, base_scn, pol_hist, pol_scn, hist_ref,
                                  bq_coef, bq_ens, method, so, scenarios, tails,
                                  matrix_transform = NULL) {
  hr <- hist_ref
  out <- dplyr::bind_rows(
    step3_threshold_rows(base_hist, base_scn, hr, "Baseline", bq_coef, bq_ens, method, so,
      scenarios, matrix_transform),
    step3_threshold_rows(pol_hist, pol_scn, hr, "Policy", bq_coef, bq_ens, method, so,
      scenarios, matrix_transform)
  )
  if (nrow(out)) {
    central_label <- function(x) x %in% c("Equal-model mean", "Single historical estimate", "Central (P50)")
    for (i in which(central_label(out$Estimate))) {
      scenario <- out$scenario[[i]]
      probability <- unname(c(RP_LOW, RP_HIGH, "1:1" = 0.5)[out$rp_name[[i]]])
      if (!is.finite(probability) || !probability %in% RP_LOW) next
      tail <- if (is.data.frame(tails) && nrow(tails)) {
        tails[tails$scenario == scenario & abs(tails$probability - probability) < 1e-8, , drop = FALSE]
      } else {
        data.frame()
      }
      state <- if (identical(out$source[[i]], "Baseline")) "baseline" else "policy"
      available <- nrow(tail) && identical(tail$status[[1L]], "ok") && is.finite(tail[[state]][[1L]])
      out$value[[i]] <- if (available) tail[[state]][[1L]] - hr else NA_real_
      if (!"absolute_value" %in% names(out)) out$absolute_value <- rep(NA_real_, nrow(out))
      out$absolute_value[[i]] <- if (available) tail[[state]][[1L]] else NA_real_
      if (!"adverse_basis" %in% names(out)) out$adverse_basis <- rep(NA_character_, nrow(out))
      if (!"scope" %in% names(out)) out$scope <- rep(NA_character_, nrow(out))
      if (!"center_method" %in% names(out)) out$center_method <- rep(NA_character_, nrow(out))
      if (!"status" %in% names(out)) out$status <- rep(NA_character_, nrow(out))
      if (!"reason" %in% names(out)) out$reason <- rep(NA_character_, nrow(out))
      out$adverse_basis[[i]] <- "baseline_selected_metric"
      out$scope[[i]] <- "baseline_anchored"
      out$center_method[[i]] <- if (nrow(tail)) tail$center_method[[1L]] else ""
      out$status[[i]] <- if (nrow(tail)) tail$status[[1L]] else "unavailable"
      out$reason[[i]] <- if (nrow(tail)) tail$reason[[1L]] else "Baseline-anchored adverse support unavailable."
    }
  }
  out
}

#' Paired policy-minus-baseline effect of each matched scenario
#'
#' @param b,p Series of the baseline and policy arms: named lists (historical
#'   label and scenarios) of `list(out = <aggregation table>)`.
#' @return A named list of paired model-year effect tables (`list()` when an
#'   arm has no series).
#' @noRd
step3_paired_data <- function(b, p) {
  if (!length(b) || !length(p)) {
    return(list())
  }
  common <- intersect(names(b), names(p))
  stats::setNames(lapply(common, function(nm) {
    paired_model_year_effects(b[[nm]]$out, p[[nm]]$out) |>
      dplyr::mutate(scenario = nm)
  }), common)
}

#' Expected paired effect per scenario
#'
#' @param dat Result of `step3_paired_data()`.
#' @param ensemble_band Band of the model spread (`"none"`, `"p10_p90"`, ...).
#' @return A tibble.
#' @noRd
step3_paired_summary <- function(dat, ensemble_band = "none") {
  if (!length(dat)) {
    return(tibble::tibble())
  }
  bq <- if (identical(ensemble_band, "none")) {
    c(lo = 0.5, hi = 0.5)
  } else {
    resolve_band_q(ensemble_band)
  }
  dplyr::bind_rows(lapply(names(dat), function(nm) {
    paired_effect_summary(dat[[nm]], band_q = bq, scenario = nm,
      center = "equal_model_mean")
  }))
}

# Headline robustness is a factual model range, independent of the
# ensemble-spread setting used to tune individual plots.
#' @noRd
step3_headline_paired_summary <- function(dat) {
  if (!length(dat)) {
    return(tibble::tibble())
  }
  dplyr::bind_rows(lapply(names(dat), function(nm) {
    paired_effect_summary(dat[[nm]], band_q = c(lo = 0, hi = 1), scenario = nm,
      center = "equal_model_mean")
  }))
}

#' Paired annual effect per scenario, member and year
#' @noRd
step3_paired_annual <- function(dat) {
  if (!length(dat)) {
    return(tibble::tibble())
  }
  dplyr::bind_rows(lapply(names(dat), function(nm) {
    x <- dat[[nm]]
    if (is.null(x) || !nrow(x)) {
      return(NULL)
    }
    x[, c("scenario", "sim_year", "model_id", "effect", "effect_sd")]
  })) |>
    dplyr::rename(value = effect)
}

#' Series of one arm for one metric
#'
#' @param agg Result of `step2_run_aggregates()`.
#' @param method Aggregation metric.
#' @param hist_label Label of the historical scenario.
#' @param scenarios Names of the scenarios to include.
#' @return A list: `hist` and `scn` (`list(out = <aggregation table>)` each, as
#'   the Results pane holds them) and `all`, the historical arm under
#'   `hist_label` followed by the scenarios.
#' @noRd
step3_series <- function(agg, method, hist_label, scenarios = names(agg$scn)) {
  hist <- list(out = agg$hist[[method]])
  scn <- lapply(agg$scn, function(tbl) if (is.null(tbl)) NULL else list(out = tbl[[method]]))
  list(
    hist = hist, scn = scn,
    all = c(stats::setNames(list(hist), hist_label), scn[intersect(scenarios, names(scn))])
  )
}

# Metrics that read the poverty line.
STEP3_POVERTY_METHODS <- c("headcount_ratio", "gap", "fgt2")

#' Poverty line of the Step 3 Results pane
#'
#' The run's own line when it has one, else 3.00 per day (the initial value of
#' the pane's control).
#' @param hs Step 2 historical result.
#' @noRd
step3_pov_line <- function(hs) {
  x <- suppressWarnings(as.numeric(hs$pov_line)[1L])
  if (length(x) && is.finite(x) && x > 0) x else 3
}

#' The Results metric context of the Step 3 pane for one metric
#'
#' @param method Aggregation metric.
#' @param hs Step 2 historical result (the baseline arm).
#' @param pov_line Poverty line (used by the poverty metrics only).
#' @param analysis_unit Analysis unit.
#' @param focus Focus scenario.
#' @param run_identity Identity of the policy run (`decomp_context$run_identity`).
#' @param requested_residuals Residual rule of the baseline run.
#' @param status Result of `.policy_endpoint_status()`.
#' @noRd
step3_metric_context <- function(method, hs, pov_line, analysis_unit, focus, run_identity,
                                 requested_residuals, status) {
  spec <- metric_metadata(method, hs$so,
    pov_line = if (method %in% STEP3_POVERTY_METHODS) pov_line else NULL,
    analysis_unit = analysis_unit, weighted = !is.null(hs$pipeline$weight)
  )
  spec$scenario <- focus
  spec$run_identity <- run_identity
  spec$requested_residuals <- requested_residuals
  spec$availability <- status$status
  spec$reason <- status$reason
  spec
}

#' The survey frame a Step 3 run publishes as its policy frame
#'
#' A shock program has no static transfer; for reach and diagnostics the frame
#' marks households paid in at least one historical year.
#' @param svy_mod Policy-adjusted survey frame of `step3_compute()`.
#' @param shock `pol_out$shock`, or `NULL` for a regular program.
#' @noRd
step3_published_policy_svy <- function(svy_mod, shock) {
  if (is.null(shock)) {
    return(svy_mod)
  }
  published <- svy_mod
  published[[SP_TRANSFER_COL]] <- shock$per_household * shock$paid_historical
  published
}

#' Cost and targeting effectiveness of the cash transfer of a run
#'
#' @param d Diagnostics snapshot of the run (`diagnostic_summary`).
#' @param sp Social protection scenario.
#' @param base,pol Baseline survey frame and published policy frame.
#' @param shock_summary `pol_out$shock`, or `NULL`.
#' @param poverty_line Poverty line, or `NULL`.
#' @return The result of `sp_effectiveness()`, or `NULL`.
#' @noRd
step3_sp_effectiveness <- function(d, sp, base, pol, shock_summary = NULL, poverty_line = NULL) {
  if (is.null(d) || (is.list(d) && !is.null(d$status))) {
    return(NULL)
  }
  shock <- identical(sp$sp_type, "shock")
  if (is.null(base) || is.null(pol)) {
    return(NULL)
  }
  # A shock program pays no transfer every year. Its design figures use the
  # per-household amount paid in an activated year; realised annual cost is
  # in the shock-responsive table below and the cost-effectiveness tab.
  if (shock) {
    amount <- shock_summary$per_household
    if (length(amount) != nrow(pol)) {
      return(NULL)
    }
    pol[[SP_TRANSFER_COL]] <- .sp_shock_design_transfer(
      amount, pol[[SP_ELIGIBLE_COL]], pol[["weight"]]
    )
  }
  ideal <- tryCatch(
    if (!is.null(sp)) .determine_sp_eligibility(base, sp, apply_errors = FALSE),
    error = function(e) NULL
  )
  sp_effectiveness(
    base, pol,
    poverty_line = poverty_line,
    analysis_unit = d$analysis_unit %||% "hh",
    currency = d$transfer_currency %||% "PPP",
    admin_share = d$admin_share %||% 0,
    eligibility = ideal,
    shock = shock
  )
}

#' Before and after summary of the variables a policy changed
#'
#' @param d Diagnostics snapshot of the run.
#' @return The summary with the count of changed units after the variable
#'   column, or `NULL`. `.policy_input_table_raw()` names its columns.
#' @noRd
step3_input_summary_frame <- function(d) {
  if (is.null(d) || !is.null(d$status)) {
    return(NULL)
  }
  df <- d$input_summary
  if (is.null(df) || nrow(df) == 0) {
    return(NULL)
  }
  counts <- d$changed_counts
  count_label <- if (identical(d$analysis_unit, "hh")) "Sample households changed" else "Sample observations changed"
  df[[count_label]] <- unname(counts[df$variable])
  df[, c("variable", count_label, setdiff(names(df), c("variable", count_label))), drop = FALSE]
}

#' Cost-effectiveness of the cash transfer for the Results metric
#'
#' @param sp,infra,digital,labor,education Lever scenarios of the run.
#' @param metric_context Metric context (`step3_metric_context()`).
#' @param effect_summary Expected paired effect per scenario (headline summary).
#' @param decomp Metric decomposition of the metric.
#' @param shock_summary `pol_out$shock`, or `NULL`.
#' @param annual_effects Paired annual effects (`step3_paired_annual()`).
#' @param policy_svy,baseline_svy Survey frames of the run.
#' @param hist_label Label of the historical scenario.
#' @param analysis_unit Analysis unit.
#' @param poverty_line Poverty line of the metric, or `NULL`.
#' @return A list with `status`; for `"ok"` also `res`, `currency`, `admin`,
#'   `shock`, `method`, `label`, `line` and `uses_line`.
#' @noRd
step3_cost_effectiveness <- function(sp, infra, digital, labor, education, metric_context,
                                     effect_summary, decomp, shock_summary, annual_effects,
                                     policy_svy, baseline_svy, hist_label, analysis_unit,
                                     poverty_line) {
  if (!has_sp_change(sp)) {
    return(list(status = "no_sp"))
  }
  mc <- metric_context
  eff <- effect_summary
  if (is.null(mc) || !is.data.frame(eff) || !nrow(eff)) {
    return(list(status = "no_effect"))
  }
  if (!identical(mc$availability %||% "ok", "ok")) {
    return(list(status = "no_effect", reason = mc$reason))
  }
  au <- analysis_unit %||% "hh"
  currency <- .sp_currency(sp$currency)
  admin <- .sp_admin_share(sp)
  shock <- identical(sp$sp_type, "shock")
  effects <- sp_effect_by_scenario(eff, decomp$return_period)

  costs <- if (shock) {
    ae <- annual_effects
    matched <- if (is.data.frame(ae)) ae[is.finite(ae$value), , drop = FALSE]
    sp_shock_cost_by_scenario(
      shock_summary$rows, matched = matched, supports = decomp$adverse_support,
      historical = hist_label, probability = 0.05
    )
  } else {
    total <- .sp_transfer_totals(policy_svy, au, currency, admin)$total_cost
    data.frame(
      scenario = effects$scenario, cost_avg = total, cost_tail = total,
      stringsAsFactors = FALSE
    )
  }
  other_levers <- has_infra_change(infra) ||
    has_digital_change(digital) ||
    has_labor_change(labor) ||
    has_education_change(education)
  line <- poverty_line
  res <- sp_cost_effectiveness(
    effects, costs, mc$method,
    pop = .sp_ce_population(baseline_svy, au),
    poverty_line = line, level_unit = mc$level_unit, sp_only = !other_levers
  )
  list(
    status = "ok", res = res, currency = currency, admin = admin, shock = shock,
    method = mc$method, label = mc$label, line = line,
    uses_line = mc$method %in% c("headcount_ratio", "gap")
  )
}

#' Baseline-anchored adverse-year effects (5, 10, 20 and 50-year)
#'
#' @param tails The `return_period` table of the metric decomposition.
#' @return A tibble.
#' @noRd
step3_paired_adverse_table <- function(tails) {
  empty <- tibble::tibble(period = character(), baseline = numeric(), policy = numeric(),
    effect = numeric(), ensemble_lo = numeric(), ensemble_hi = numeric(), scenario = character(),
    center_method = character(), scope = character(), adverse_basis = character(),
    status = character(), reason = character())
  if (is.data.frame(tails) && nrow(tails)) {
    return(dplyr::bind_rows(lapply(unique(tails$scenario), function(nm) {
      x <- tails[tails$scenario == nm & tails$scope == "baseline_anchored" &
        tails$return_period %in% c(5, 10, 20, 50), , drop = FALSE]
      if (!nrow(x)) return(NULL)
      dplyr::transmute(x,
        period = paste0("Adverse 1-in-", round(.data$return_period)),
        baseline = .data$baseline, policy = .data$policy, effect = .data$total,
        ensemble_lo = NA_real_, ensemble_hi = NA_real_, scenario = .data$scenario,
        center_method = .data$center_method, scope = .data$scope,
        adverse_basis = .data$adverse_basis, status = .data$status, reason = .data$reason)
    })))
  }
  empty
}

# Batch tables ----

# Ensemble band the policy `summary` rows are stored at (as for Step 2).
STEP3_SUMMARY_ENSEMBLE_BAND <- STEP2_SUMMARY_ENSEMBLE_BAND

# One `summary` row, as in `step2_summary_table()`.
#' @noRd
.s3_summary_row <- function(scenario, metric, section, measure, group = NA_character_,
                            return_period = NA_character_, estimate = NA_real_, lo = NA_real_,
                            hi = NA_real_, n = NA_real_, text = NA_character_) {
  k <- max(lengths(list(scenario, measure, group, return_period, estimate, lo, hi, n, text)))
  data.frame(
    scenario = rep_len(as.character(scenario), k), metric = rep_len(as.character(metric), k),
    section = section, measure = rep_len(as.character(measure), k),
    group = rep_len(as.character(group), k), return_period = rep_len(as.character(return_period), k),
    estimate = rep_len(as.numeric(estimate), k), lo = rep_len(as.numeric(lo), k),
    hi = rep_len(as.numeric(hi), k), n = rep_len(as.numeric(n), k),
    text = rep_len(as.character(text), k), stringsAsFactors = FALSE
  )
}

# One `policy_measures` row.
#' @noRd
.s3_measure_row <- function(section, measure, group = NA_character_, value = NA_real_,
                            text = NA_character_, scenario = NA_character_, metric = NA_character_) {
  k <- max(lengths(list(measure, group, value, text, scenario, metric)))
  data.frame(
    section = section, scenario = rep_len(as.character(scenario), k),
    metric = rep_len(as.character(metric), k), measure = rep_len(as.character(measure), k),
    group = rep_len(as.character(group), k), value = rep_len(as.numeric(value), k),
    text = rep_len(as.character(text), k), stringsAsFactors = FALSE
  )
}

# The numeric columns of a table as measure rows: `measure` is the column,
# `group` the labels of the row (`id_cols` pasted).
#' @noRd
.s3_measures_long <- function(df, section, id_cols, scenario_col = NULL, metric = NA_character_) {
  if (!is.data.frame(df) || !nrow(df)) {
    return(NULL)
  }
  num <- setdiff(names(df)[vapply(df, is.numeric, logical(1))], id_cols)
  group <- if (length(id_cols)) {
    do.call(paste, c(lapply(id_cols, function(f) as.character(df[[f]])), sep = " / "))
  } else {
    rep(NA_character_, nrow(df))
  }
  scenario <- if (is.null(scenario_col)) NA_character_ else as.character(df[[scenario_col]])
  dplyr::bind_rows(lapply(num, function(f) {
    .s3_measure_row(section, f, group, df[[f]], scenario = scenario, metric = metric)
  }))
}

# Summary rows of one metric: the Step 3 views at the stored defaults.
#' @noRd
.s3_method_summary <- function(m, v) {
  row <- .s3_summary_row
  out <- list()
  ps <- v$paired_summary
  if (is.data.frame(ps) && nrow(ps)) {
    z <- stats::qnorm(resolve_band_q(STEP3_SUMMARY_ENSEMBLE_BAND))
    out[[length(out) + 1L]] <- rbind(
      row(ps$scenario, m, "policy_expected", "effect", "intermodel", NA, ps$value, ps$intermod_lo,
        ps$intermod_hi, ps$n_models),
      row(ps$scenario, m, "policy_expected", "effect", "coefficient", NA, ps$value, ps$coef_lo,
        ps$coef_hi, ps$n_models),
      row(ps$scenario, m, "policy_expected", "effect", "interannual", NA, ps$value, ps$interann_lo,
        ps$interann_hi, ps$n_models),
      row(ps$scenario, m, "policy_expected", "baseline", "level", NA, ps$baseline, n = ps$n_models),
      row(ps$scenario, m, "policy_expected", "policy", "level", NA, ps$policy, n = ps$n_models)
    )
  }
  hp <- v$headline_paired
  if (is.data.frame(hp) && nrow(hp)) {
    out[[length(out) + 1L]] <- row(hp$scenario, m, "policy_expected", "effect", "range", NA, hp$value,
      hp$intermod_lo, hp$intermod_hi, hp$n_models)
  }
  adv <- v$adverse_table
  if (is.data.frame(adv) && nrow(adv)) {
    rp <- sub("^Adverse 1-in-", "", adv$period)
    note <- ifelse(adv$status == "ok", NA_character_, adv$reason)
    out[[length(out) + 1L]] <- rbind(
      row(adv$scenario, m, "policy_adverse", adv$period, "effect", rp, adv$effect, text = note),
      row(adv$scenario, m, "policy_adverse", adv$period, "baseline", rp, adv$baseline, text = note),
      row(adv$scenario, m, "policy_adverse", adv$period, "policy", rp, adv$policy, text = note)
    )
  }
  thr <- v$threshold
  if (is.data.frame(thr) && nrow(thr)) {
    out[[length(out) + 1L]] <- row(
      thr$scenario, m, "policy_threshold", thr$Estimate, thr$source, thr$rp_name, thr$value,
      n = thr$n_obs, text = if ("status" %in% names(thr)) thr$status else NA_character_
    )
  }
  dot <- v$adverse_dot
  if (is.data.frame(dot) && nrow(dot)) {
    lbl <- as.character(dot$rp_label)
    out[[length(out) + 1L]] <- rbind(
      row(dot$scenario, m, "policy_adverse_dot", lbl, "baseline", dot$rp_name, dot$baseline_val,
        dot$base_lo, dot$base_hi),
      row(dot$scenario, m, "policy_adverse_dot", lbl, "policy", dot$rp_name, dot$policy_val,
        dot$policy_lo, dot$policy_hi),
      row(dot$scenario, m, "policy_adverse_dot", lbl, "effect", dot$rp_name, dot$effect)
    )
  }
  cards <- v$cards
  hl <- step3_headline_df(cards)
  if (nrow(hl)) {
    scenario <- if (is.data.frame(hp) && nrow(hp)) {
      fut <- hp$scenario[!grepl("^Historical", as.character(hp$scenario))]
      if (length(fut)) fut[[1L]] else hp$scenario[[1L]]
    } else {
      NA_character_
    }
    ci <- cards[[1L]]$effect_ci_native %||% c(NA_real_, NA_real_)
    out[[length(out) + 1L]] <- rbind(
      row(scenario, m, "policy_headline", hl$label, paste0("card_", hl$card, "_value"), NA, NA,
        lo = c(ci[[1L]], rep(NA_real_, nrow(hl) - 1L)), hi = c(ci[[2L]], rep(NA_real_, nrow(hl) - 1L)),
        n = hl$households_represented, text = hl$value),
      row(scenario, m, "policy_headline", hl$label, paste0("card_", hl$card, "_note"), NA, NA,
        n = hl$prediction_count_native, text = hl$note)
    )
  }
  if (length(out)) dplyr::bind_rows(out) else NULL
}

# The `decomposition` rows of the compact per-year channels (D5): channel sums
# and weights by scenario, member, year and baseline decile.
#' @noRd
step3_compact_decomposition <- function(compact) {
  if (!.is_compact_decomp_scenarios(compact)) {
    return(NULL)
  }
  one <- function(tbl, decile) {
    if (!is.data.frame(tbl) || !nrow(tbl)) {
      return(NULL)
    }
    sums <- grep("^sum_", names(tbl), value = TRUE)
    channels <- sub("^sum_", "", sums)
    group <- if (decile) paste0("decile_", tbl$decile) else rep("all", nrow(tbl))
    n_units <- if (decile) tbl$weighted_population else rep(NA_real_, nrow(tbl))
    dplyr::bind_rows(lapply(channels, function(ch) {
      s <- tbl[[paste0("sum_", ch)]]
      w <- tbl[[paste0("weight_", ch)]]
      data.frame(
        source = "compact", scenario = as.character(tbl$scenario), member = as.character(tbl$member),
        sim_year = as.integer(tbl$sim_year), metric = NA_character_, group = group, channel = ch,
        value = ifelse(is.finite(w) & w > 0, s / w, NA_real_), sum = s, weight = w,
        n_units = n_units, stringsAsFactors = FALSE
      )
    }))
  }
  dplyr::bind_rows(one(compact$channel_summary, FALSE), one(compact$decile_summary, TRUE))
}

# The `decomposition` rows of one metric decomposition: the states and
# contributions of every member and year, whole sample and by decile.
#' @noRd
step3_metric_decomposition_rows <- function(decomp, metric) {
  one <- function(tbl, decile) {
    if (!is.data.frame(tbl) || !nrow(tbl)) {
      return(NULL)
    }
    group <- if (decile) paste0("decile_", tbl$decile) else rep("all", nrow(tbl))
    n_units <- if (decile) tbl$n_retained_rows else tbl$n_retained_rows
    dplyr::bind_rows(lapply(.policy_metric_fields, function(ch) {
      data.frame(
        source = "metric", scenario = as.character(tbl$scenario), member = as.character(tbl$member),
        sim_year = as.integer(tbl$sim_year), metric = metric, group = group, channel = ch,
        value = as.numeric(tbl[[ch]]), sum = NA_real_, weight = NA_real_,
        n_units = as.numeric(n_units), stringsAsFactors = FALSE
      )
    }))
  }
  dplyr::bind_rows(one(decomp$annual, FALSE), one(decomp$decile_annual, TRUE))
}

# Rows of `annual` for the shock-responsive program: the per member-year rows
# of the run as metrics `shock_<column>`.
#' @noRd
step3_shock_annual_rows <- function(shock, hist_label) {
  rows <- shock$rows
  if (!is.data.frame(rows) || !nrow(rows)) {
    return(NULL)
  }
  cols <- c(
    "activated", "exposed_share", "transfer_cost", "admin_cost", "total_cost",
    "pop_tp", "pop_fp", "pop_fn", "pop_tn", "spend_total", "spend_no_event",
    "loss_value", "paid_value"
  )
  cols <- intersect(cols, names(rows))
  scenario <- as.character(rows$scenario)
  scenario[as.character(rows$member) == "Historical"] <- hist_label
  dplyr::bind_rows(lapply(cols, function(f) {
    data.frame(
      scenario = scenario, metric = paste0("shock_", f), member = as.character(rows$member),
      sim_year = as.integer(rows$sim_year), value = as.numeric(rows[[f]]), sd = NA_real_,
      var_within = NA_real_, var_across = NA_real_, weighted = NA, stringsAsFactors = FALSE
    )
  }))
}

#' All batch tables of one Step 3 policy run
#'
#' The policy arm of `annual` and `summary` (the Step 3 views at the stored
#' defaults, for every metric), the `decomposition` (compact per-year channels and
#' the metric-aware states) and `policy_measures` (transfer summary, targeting
#' effectiveness, reach, components, treatment matrix, input diagnostics,
#' cost-effectiveness and the shock-responsive program). The baseline arm is the
#' Step 2 result and is stored with the simulation.
#'
#' @param run Result of `step3_compute()`.
#' @param hs,ss The Step 2 historical result and scenarios the run started from
#'   (annotated: `hist_label`, `sim_summary`).
#' @param svy Baseline survey frame of the run.
#' @param levers Named list of the lever scenarios (`sp`, `infra`, `digital`,
#'   `labor`, `education`; `NULL` for a lever that is not part of the run).
#' @param skip_coef Coefficient uncertainty was skipped in the Step 2 run.
#' @param analysis_unit Analysis unit.
#' @return A list: `status` (`"ok"` or the `.policy_endpoint_status()` verdict),
#'   `tables` (`annual`, `summary`, `decomposition`, `policy_measures`) and
#'   `partial` (metrics whose views failed, as text).
#' @noRd
step3_batch_tables <- function(run, hs, ss, svy, levers, skip_coef, analysis_unit = "hh") {
  status <- .policy_endpoint_status(hs$so, run$decomp_context)
  if (!identical(status$status, "ok")) {
    return(list(status = status, tables = list(), partial = character(0)))
  }
  pol_out <- run$pol_out
  base_hs <- run$baseline_out
  base_ss <- run$baseline_scenarios_out
  so <- hs$so
  hist_label <- hs$hist_label %||% "Historical"
  scenarios <- names(base_ss)
  focus <- if (length(scenarios)) scenarios[[1L]] else hist_label
  pov_line <- step3_pov_line(hs)
  requested <- base_hs$residuals %||% "original"
  sp <- levers$sp

  # The policy arm aggregates with the residual rule and the seed of the
  # baseline run, as the pane does.
  pol_hs <- pol_out$hist_sim
  pol_hs$so <- pol_hs$so %||% so
  pol_hs$residuals <- pol_hs$residuals %||% base_hs$residuals
  pol_hs$seed <- .step2_run_seed(base_hs)
  pol_ss <- pol_out$saved_scenarios %||% list()
  agg_b <- step2_run_aggregates(base_hs, base_ss, skip_coef, pov_line)
  agg_p <- step2_run_aggregates(pol_hs, pol_ss, skip_coef, pov_line)

  pub_svy <- step3_published_policy_svy(run$svy_mod, pol_out$shock)
  shock <- pol_out$shock
  bq_coef <- resolve_band_q("p10_p90")
  bq_ens <- resolve_band_q(STEP3_SUMMARY_ENSEMBLE_BAND)
  validation_cache <- new.env(parent = emptyenv())
  partial <- character(0)

  annual <- step2_annual_table(agg_p)
  shock_rows <- if (!is.null(shock)) step3_shock_annual_rows(shock, hist_label)
  annual <- dplyr::bind_rows(annual, shock_rows)

  summaries <- list()
  decomps <- list(step3_compact_decomposition(pol_out$decomp_scenarios))
  ce_rows <- list()
  for (m in agg_b$methods) {
    res <- tryCatch(
      {
        b <- step3_series(agg_b, m, hist_label, scenarios)
        p <- step3_series(agg_p, m, hist_label, scenarios)
        dat <- step3_paired_data(b$all, p$all)
        mc_pov <- if (m %in% STEP3_POVERTY_METHODS) pov_line else NULL
        decomp <- .policy_metric_decomposition(
          baseline_hist = base_hs, policy_hist = pol_out$hist_sim,
          baseline_scenarios = base_ss, policy_scenarios = pol_ss,
          prepared = pol_out$annual_channels, method = m, pov_line = mc_pov,
          requested_residuals = requested, endpoint_series_baseline = b$all,
          endpoint_series_policy = p$all, focus_scenario = focus,
          analysis_unit = analysis_unit, validation_cache = validation_cache
        )
        mc <- step3_metric_context(
          m, base_hs, pov_line, analysis_unit, focus, run$decomp_context$run_identity,
          requested, status
        )
        hp <- step3_headline_paired_summary(dat)
        thr <- step3_threshold_table(
          b$hist, b$scn, p$hist, p$scn, 0, bq_coef, bq_ens, m, so, scenarios, decomp$return_period
        )
        ts <- dplyr::bind_rows(
          step3_timeseries_rows(b$hist, b$scn, 0, "Baseline", scenarios),
          step3_timeseries_rows(p$hist, p$scn, 0, "Policy", scenarios)
        )
        cards <- step3_headline_cards(
          paired_summary = hp, threshold_tbl = thr, baseline_agg = b$scn, policy_agg = p$scn,
          policy_svy = pub_svy, sp_scenario = sp, timeseries_curves = ts, method = m, so = so,
          baseline_svy = svy, analysis_unit = analysis_unit, metric_context = mc,
          metric_decomposition = decomp, endpoint_status = status
        )
        views <- list(
          paired_summary = step3_paired_summary(dat, STEP3_SUMMARY_ENSEMBLE_BAND),
          headline_paired = hp, adverse_table = step3_paired_adverse_table(decomp$return_period),
          threshold = thr, adverse_dot = step3_adverse_dot_data(thr, m, so), cards = cards
        )
        ce <- if (has_sp_change(sp)) {
          step3_cost_effectiveness(
            sp, levers$infra, levers$digital, levers$labor, levers$education, mc, hp, decomp,
            shock, step3_paired_annual(dat), pub_svy, svy, hist_label, analysis_unit, mc_pov
          )
        }
        list(
          summary = .s3_method_summary(m, views),
          decomposition = step3_metric_decomposition_rows(decomp, m),
          ce = if (!is.null(ce) && identical(ce$status, "ok")) {
            cbind(
              ce$res,
              metric = ce$method, poverty_line = suppressWarnings(as.numeric(ce$line)[1L]),
              admin_share = ce$admin, currency = ce$currency,
              program = if (ce$shock) "shock-responsive" else "regular"
            )
          }
        )
      },
      error = function(e) e
    )
    if (inherits(res, "error")) {
      partial <- c(partial, sprintf("metric %s: %s", m, conditionMessage(res)))
      next
    }
    summaries[[length(summaries) + 1L]] <- res$summary
    decomps[[length(decomps) + 1L]] <- res$decomposition
    if (!is.null(res$ce)) ce_rows[[length(ce_rows) + 1L]] <- cbind(res$ce, metric_label = m)
  }

  # Incidence by baseline decile (line-free; from the compact channels).
  inc <- step3_incidence_by_decile(pol_out$decomp_scenarios, so)
  if (nrow(inc)) {
    summaries[[length(summaries) + 1L]] <- .s3_summary_row(
      inc$scenario, NA_character_, "policy_incidence", "household_effect", paste0("decile_", inc$decile),
      inc$basis, inc$effect, n = inc$n_models
    )
  }

  # Policy measures.
  d <- run$diagnostic_summary
  measures <- list()
  if (!is.null(d) && is.null(d$status)) {
    tr <- .policy_transfer_summary_rows(d)
    measures[[length(measures) + 1L]] <- .s3_measure_row("transfer", tr$Type, value = tr$Value)
    line_d <- {
      pl <- .sp_default_pov_line(so)
      if (is.na(pl)) pov_line else pl
    }
    eff <- step3_sp_effectiveness(d, sp, svy, pub_svy, shock, poverty_line = line_d)
    if (!is.null(eff) && nrow(eff$metrics)) {
      measures[[length(measures) + 1L]] <- .s3_measure_row(
        "sp_effectiveness", eff$metrics$metric, group = eff$metrics$kind, value = eff$metrics$value,
        text = eff$metrics$note
      )
    }
    reach <- d$reach
    if (is.list(reach)) {
      nums <- reach[vapply(reach, function(x) is.numeric(x) && length(x) == 1L, logical(1))]
      if (length(nums)) {
        measures[[length(measures) + 1L]] <- .s3_measure_row(
          "reach", names(nums), value = unlist(nums, use.names = FALSE)
        )
      }
    }
    measures[[length(measures) + 1L]] <- .s3_measures_long(
      .policy_component_table_raw(d$component_matrix, analysis_unit), "components",
      "Policy component"
    )
    measures[[length(measures) + 1L]] <- .s3_measures_long(
      .policy_treatment_table_raw(d$treatment_matrix, analysis_unit), "treatment", "Coverage status"
    )
    inp <- step3_input_summary_frame(d)
    if (!is.null(inp)) {
      measures[[length(measures) + 1L]] <- .s3_measures_long(
        .policy_input_table_raw(inp), "input_diagnostics", "Variable"
      )
    }
  }
  if (length(ce_rows)) {
    ce_all <- dplyr::bind_rows(ce_rows)
    num <- c("cost", "amount", "value", "lo", "hi", "poverty_line", "admin_share")
    ce_all$group <- paste(ce_all$basis, ce_all$measure, sep = " / ")
    for (f in num) {
      measures[[length(measures) + 1L]] <- .s3_measure_row(
        "cost_effectiveness", f, group = ce_all$group, value = ce_all[[f]],
        text = ce_all$status, scenario = ce_all$scenario, metric = ce_all$metric_label
      )
    }
  }
  if (!is.null(shock)) {
    scored <- sp_shock_rescore(shock, sp$loss_event_pct)
    measures[[length(measures) + 1L]] <- .s3_measures_long(
      scored$summary, "shock_summary", character(0), scenario_col = "scenario"
    )
    climate <- sp_shock_climate_cost(scored$summary, reference = hist_label)
    measures[[length(measures) + 1L]] <- .s3_measures_long(
      climate, "shock_climate_cost", character(0), scenario_col = "scenario"
    )
    reach_line <- {
      pl <- .sp_default_pov_line(so)
      if (is.na(pl)) pov_line else pl
    }
    affected <- sp_shock_reach(shock$reach, svy, reach_line, .sp_currency(sp$currency), analysis_unit)
    measures[[length(measures) + 1L]] <- .s3_measures_long(
      affected, "shock_affected_poor", character(0), scenario_col = "scenario"
    )
  }

  # The historical arm is called `Historical` in every table, whatever the run
  # labelled it (the label carries the years, which are columns of `runs`).
  plain <- function(x) {
    if (is.data.frame(x) && "scenario" %in% names(x)) {
      x$scenario[x$scenario %in% hist_label] <- "Historical"
    }
    x
  }
  list(
    status = status,
    tables = lapply(list(
      annual = annual,
      summary = dplyr::bind_rows(summaries),
      decomposition = dplyr::bind_rows(decomps),
      policy_measures = dplyr::bind_rows(measures)
    ), plain),
    partial = partial
  )
}

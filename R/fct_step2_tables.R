# Step 2 result views and batch tables ----
# The views of the Step 2 Results pane (expected outcome bands, annual curves,
# uncertainty sources, return-period thresholds, adverse-year dots, headline
# cards, distributional incidence) as pure functions of the aggregation
# tables of one metric. The Results module (mod_2_02) calls them from its
# reactives; batch calls the same functions and stores the results as the
# tables `annual`, `summary` and `sim_weather` (reference in
# batch/docs/tables.md). Shiny-free.
#
# A "series" is a named list of aggregation tables of the selected metric: the
# historical run first (named "Historical"), then one table per scenario, with
# the paired-contrast SDs already applied when a deviation is active. A NULL or
# empty table is left out of every view.

# Reference and contrast ----

#' Historical reference the deviation modes subtract
#' @param hist_tbl Historical aggregation table.
#' @param deviation `"none"`, `"mean"` or `"median"` year.
#' @noRd
step2_hist_ref <- function(hist_tbl, deviation = "none") {
  if (identical(deviation, "none")) {
    return(0)
  }
  raw_vals <- hist_tbl$value
  if (identical(deviation, "mean")) {
    mean(raw_vals, na.rm = TRUE)
  } else {
    stats::median(raw_vals, na.rm = TRUE)
  }
}

#' Per-coefficient gradient of the historical reference
#'
#' When deviation = mean: average of per-year F_agg across historical years.
#' When deviation = median: F_agg at the historical year closest to the
#' median. Used by `step2_contrast_sd()` to switch the coefficient SE from
#' level-CI (||F_s||) to contrast-CI (||F_s - F_ref||), the correct SE for
#' paired counterfactual analysis on the same population.
#' @noRd
step2_hist_f_ref <- function(ht, deviation = "none") {
  if (identical(deviation, "none")) {
    return(NULL)
  }
  if (is.null(ht) || nrow(ht) == 0L || !"F_agg_all" %in% names(ht)) {
    return(NULL)
  }
  # Historical has one "model" so each F_agg_all row is a 1 x K matrix.
  F_list <- lapply(ht$F_agg_all, function(m) {
    if (is.null(m) || !is.matrix(m) || nrow(m) == 0L) {
      NULL
    } else {
      as.numeric(m[1L, ])
    }
  })
  F_list <- Filter(Negate(is.null), F_list)
  if (length(F_list) == 0L) {
    return(NULL)
  }
  if (identical(deviation, "mean")) {
    Reduce(`+`, F_list) / length(F_list)
  } else {
    vals <- ht$value
    med_v <- stats::median(vals, na.rm = TRUE)
    med_idx <- which.min(abs(vals - med_v))
    if (length(med_idx) == 0L) {
      Reduce(`+`, F_list) / length(F_list)
    } else {
      F_list[[med_idx]]
    }
  }
}

#' Replace per-(model, year) coefficient SDs with paired-contrast SDs
#'
#' By overwriting `value_all_sd`, every downstream view automatically uses the
#' tightened contrast variance.
#' @noRd
step2_contrast_sd <- function(tbl, F_ref) {
  if (is.null(F_ref) || is.null(tbl) || nrow(tbl) == 0L) {
    return(tbl)
  }
  if (!"F_agg_all" %in% names(tbl) || !"value_all_sd" %in% names(tbl)) {
    return(tbl)
  }
  for (k in seq_len(nrow(tbl))) {
    F_mat <- tbl$F_agg_all[[k]]
    if (is.null(F_mat) || !is.matrix(F_mat) || ncol(F_mat) != length(F_ref)) {
      next
    }
    F_diff <- sweep(F_mat, 2L, F_ref, "-")
    # value_all_sd is sqrt(var_coef + var_resid). The contrast replaces
    # only the coefficient part; residual variance of the scenario stays.
    sd_level <- as.numeric(tbl$value_all_sd[[k]])
    var_resid <- if (length(sd_level) == nrow(F_mat)) {
      pmax(sd_level^2 - rowSums(F_mat * F_mat), 0)
    } else {
      0
    }
    tbl$value_all_sd[[k]] <- sqrt(rowSums(F_diff * F_diff) + var_resid)
  }
  tbl
}

#' Ensemble band as a quantile pair (`"none"` collapses to the median)
#' @noRd
step2_ensemble_band_q <- function(band_key = "none") {
  if (identical(band_key %||% "none", "none")) {
    c(lo = 0.5, hi = 0.5)
  } else {
    resolve_band_q(band_key)
  }
}

# Views of one metric ----

#' One row per scenario, three nested bands (expected outcome)
#'
#' @param series Named list of aggregation tables (see the file header).
#' @param bq_ens Ensemble band as a quantile pair.
#' @param hist_ref Reference subtracted from every value.
#' @param mm_fn Function reshaping a table into its model-by-year matrices.
#' @noRd
step2_pointrange_bands <- function(series, bq_ens, hist_ref = 0, mm_fn = by_model_matrix) {
  one_scenario <- function(tbl, scenario_label, is_hist) {
    if (is.null(tbl) || nrow(tbl) == 0L) {
      return(NULL)
    }
    mm <- mm_fn(tbl)
    if (is.null(mm)) {
      return(NULL)
    }
    vals <- mm$vals

    # Inter-model spread: per-model mean across years, then quantile across models.
    model_means <- rowMeans(vals, na.rm = TRUE)
    intermod <- if (is_hist || length(model_means) <= 1L) {
      mean_v <- mean(model_means, na.rm = TRUE)
      c(lo = mean_v, hi = mean_v)
    } else {
      c(
        lo = unname(stats::quantile(model_means, bq_ens[["lo"]], na.rm = TRUE)),
        hi = unname(stats::quantile(model_means, bq_ens[["hi"]], na.rm = TRUE))
      )
    }

    # Inter-annual variability: for each model take the band_q quantile
    # across years, then average across models.
    if (is_hist) {
      v_flat <- as.numeric(vals)
      interann <- c(
        lo = unname(stats::quantile(v_flat, bq_ens[["lo"]], na.rm = TRUE)),
        hi = unname(stats::quantile(v_flat, bq_ens[["hi"]], na.rm = TRUE))
      )
    } else {
      per_mod_lo <- apply(vals, 1L, stats::quantile,
        probs = bq_ens[["lo"]], na.rm = TRUE
      )
      per_mod_hi <- apply(vals, 1L, stats::quantile,
        probs = bq_ens[["hi"]], na.rm = TRUE
      )
      interann <- c(
        lo = mean(per_mod_lo, na.rm = TRUE),
        hi = mean(per_mod_hi, na.rm = TRUE)
      )
    }

    # Retained chart center: summarise each model across its weather years,
    # then take the equal-weight mean across models (the headline centre).
    ens_mean <- if (is_hist) {
      mean(as.numeric(vals), na.rm = TRUE)
    } else {
      mean(model_means, na.rm = TRUE)
    }

    tibble::tibble(
      scenario = scenario_label,
      value = ens_mean - hist_ref,
      interann_lo = unname(interann[["lo"]]) - hist_ref,
      interann_hi = unname(interann[["hi"]]) - hist_ref,
      intermod_lo = unname(intermod[["lo"]]) - hist_ref,
      intermod_hi = unname(intermod[["hi"]]) - hist_ref,
      is_historical = is_hist,
      n_models = length(mm$model_ids)
    )
  }

  rows <- lapply(seq_along(series), function(i) {
    label <- names(series)[[i]]
    one_scenario(series[[i]], label, identical(label, "Historical"))
  })
  support_tables <- lapply(Filter(Negate(is.null), rows), attr, which = "adverse_support")
  out <- dplyr::bind_rows(Filter(Negate(is.null), rows))
  attr(out, "adverse_support") <- dplyr::bind_rows(Filter(Negate(is.null), support_tables))
  out
}

#' Pointrange bands with the equal-model-mean centre of the headline
#'
#' Only the expected headline changes center; the chart and threshold views
#' retain their median ensemble convention.
#' @param bands Result of `step2_pointrange_bands()`.
#' @inheritParams step2_pointrange_bands
#' @noRd
step2_headline_bands <- function(bands, series, hist_ref = 0, mm_fn = by_model_matrix) {
  for (i in seq_len(nrow(bands))) {
    vals <- mm_fn(series[[bands$scenario[[i]]]])$vals
    vals[!is.finite(vals)] <- NA_real_
    bands$value[[i]] <- mean(rowMeans(vals, na.rm = TRUE), na.rm = TRUE) - hist_ref
  }
  bands$center_method <- "equal_model_mean"
  bands
}

#' Per (scenario, model, sim_year) values
#' @inheritParams step2_pointrange_bands
#' @noRd
step2_timeseries_curves <- function(series, hist_ref = 0, mm_fn = by_model_matrix) {
  one_scenario <- function(tbl, scenario_label, is_hist) {
    if (is.null(tbl) || nrow(tbl) == 0L) {
      return(NULL)
    }
    mm <- mm_fn(tbl)
    if (is.null(mm)) {
      return(NULL)
    }
    vals <- mm$vals
    rows <- lapply(seq_len(nrow(vals)), function(i) {
      tibble::tibble(
        scenario      = scenario_label,
        model_id      = mm$model_ids[[i]],
        sim_year      = as.integer(mm$sim_years),
        value         = vals[i, ] - hist_ref,
        is_historical = is_hist
      )
    })
    dplyr::bind_rows(rows)
  }

  rows <- lapply(seq_along(series), function(i) {
    label <- names(series)[[i]]
    one_scenario(series[[i]], label, identical(label, "Historical"))
  })
  dplyr::bind_rows(Filter(Negate(is.null), rows))
}

#' One row per scenario, three variance components
#'
#' Aggregates the per-(sim_year) var_within / var_across columns to scalars
#' and re-computes var_coef from the per-(model, year) SD list-column.
#' @inheritParams step2_pointrange_bands
#' @noRd
step2_variance_breakdown <- function(series, mm_fn = by_model_matrix) {
  one_scenario_entry <- function(tbl, scenario_label, is_hist) {
    if (is.null(tbl) || !nrow(tbl)) {
      return(NULL)
    }
    sds_flat <- as.numeric(unlist(tbl$value_all_sd))
    var_coef <- if (length(sds_flat)) {
      mean(sds_flat^2, na.rm = TRUE)
    } else {
      0
    }
    # Use value-matrix-derived var_within / var_across so the metric
    # matches what the inter-annual / inter-model bands visualise and
    # avoids double-counting var_coef. (Unlike the pointrange total
    # band, this decomposition panel intentionally includes
    # var_within - its purpose is to show the share of every source,
    # including year-to-year spread.)
    mm <- mm_fn(tbl)
    vals <- if (is.null(mm)) NULL else mm$vals
    var_within <- if (!is.null(vals) && ncol(vals) > 1L) {
      v <- mean(apply(vals, 1L, stats::var, na.rm = TRUE), na.rm = TRUE)
      if (is.finite(v)) v else 0
    } else {
      0
    }
    var_across <- if (!is_hist && !is.null(vals) && nrow(vals) > 1L) {
      v <- stats::var(rowMeans(vals, na.rm = TRUE), na.rm = TRUE)
      if (is.finite(v)) v else 0
    } else {
      0
    }
    tibble::tibble(
      scenario      = scenario_label,
      var_coef      = var_coef,
      var_within    = var_within,
      var_across    = var_across,
      is_historical = is_hist
    )
  }

  rows <- lapply(seq_along(series), function(i) {
    label <- names(series)[[i]]
    one_scenario_entry(series[[i]], label, identical(label, "Historical"))
  })
  dplyr::bind_rows(Filter(Negate(is.null), rows))
}

#' Return-period thresholds: long-format rows ready to pivot wide
#'
#' One row per (scenario, Estimate, RP). Estimate names are derived from the
#' user's band quantile selection: e.g., with coef=p10_p90 and ensemble=minmax
#' the rows are "Central (P50)", "Coef P10", "Coef P90", "Ensemble min",
#' "Ensemble max", "Pooled P10", "Pooled P90". Pooled rows combine the
#' coefficient and inter-model components assuming independence:
#' SE_pooled = sqrt(coef_sd^2 + var_across_at_rp). Historical (no inter-model
#' component) does not emit Pooled rows - they would duplicate the Coef rows.
#'
#' @inheritParams step2_pointrange_bands
#' @param bq_coef Coefficient band as a quantile pair.
#' @param method Aggregation method.
#' @param so Selected outcome (metric metadata).
#' @noRd
step2_threshold_table <- function(series, bq_coef, bq_ens, hist_ref = 0, method = "mean",
                                  so = NULL, mm_fn = by_model_matrix) {
  z_coef_lo <- stats::qnorm(bq_coef[["lo"]])
  z_coef_hi <- stats::qnorm(bq_coef[["hi"]])
  adverse_tail <- metric_metadata(method, so)$adverse_tail

  RPs <- c(RP_LOW, c("1:1" = 0.5), RP_HIGH)

  one_scenario <- function(tbl, scenario_label, is_hist) {
    if (is.null(tbl) || nrow(tbl) == 0L) {
      return(NULL)
    }
    mm <- mm_fn(tbl)
    if (is.null(mm)) {
      return(NULL)
    }
    vals <- mm$vals
    sds <- mm$sds
    n_yrs <- ncol(vals)
    n_pts <- if (is_hist) sum(is.finite(as.numeric(vals))) else n_yrs

    # Each model must independently support each rank; a longer member
    # cannot manufacture support for a shorter one.
    rp_ok <- vapply(RPs, function(p) {
      all(vapply(seq_len(nrow(vals)), function(i) {
        support <- adverse_year_support(vals[i, ], suppressWarnings(as.numeric(mm$sim_years)),
          p, adverse_tail)
        identical(support$status, "ok")
      }, logical(1)))
    }, logical(1))
    RPs_keep <- RPs[rp_ok]
    if (length(RPs_keep) == 0L) {
      return(NULL)
    }

    # Per-model rank-interp at each kept RP (matrix: model * RP) - shape
    # guaranteed by the helper (see by_model_rp_matrix()).
    per_model_rp <- matrix(NA_real_, nrow = nrow(vals), ncol = length(RPs_keep),
      dimnames = list(mm$model_ids, names(RPs_keep)))
    per_model_sd_at_rp <- matrix(NA_real_, nrow = nrow(vals), ncol = length(RPs_keep),
      dimnames = list(mm$model_ids, names(RPs_keep)))
    sd_years <- suppressWarnings(as.numeric(colnames(sds)))
    if (length(sd_years) != ncol(sds) || any(!is.finite(sd_years))) {
      sd_years <- suppressWarnings(as.numeric(mm$sim_years))
    }
    support_records <- vector("list", nrow(vals) * length(RPs_keep))
    for (i in seq_len(nrow(vals))) for (j in seq_along(RPs_keep)) {
      support <- adverse_year_support(vals[i, ], suppressWarnings(as.numeric(mm$sim_years)),
        RPs_keep[[j]], adverse_tail)
      support_records[[(i - 1L) * length(RPs_keep) + j]] <- data.frame(
        scenario = scenario_label, model_id = mm$model_ids[[i]],
        probability = RPs_keep[[j]], as.list(support), stringsAsFactors = FALSE)
      if (identical(support$status, "ok")) {
        applied <- apply_adverse_year_support(vals[i, ], suppressWarnings(as.numeric(mm$sim_years)), support)
        per_model_rp[i, j] <- applied$value
        sd_value <- if (identical(support$year_lo, support$year_hi) && support$weight_hi == 0) {
          if (is.finite(sds[i, match(support$year_lo, sd_years)])) {
            sds[i, match(support$year_lo, sd_years)]
          } else {
            NA_real_
          }
        } else {
          lo <- match(support$year_lo, sd_years)
          hi <- match(support$year_hi, sd_years)
          if (anyNA(c(lo, hi)) || any(!is.finite(sds[i, c(lo, hi)]))) NA_real_ else
            support$weight_lo * sds[i, lo] + support$weight_hi * sds[i, hi]
        }
        per_model_sd_at_rp[i, j] <- sd_value
      }
    }

    # Aggregate across models for each RP
    central_vec <- vapply(seq_len(ncol(per_model_rp)), function(j) {
      column <- per_model_rp[, j]
      if (!all(is.finite(column))) NA_real_ else mean(column)
    }, numeric(1))
    coef_sd_vec <- if (is_hist) {
      per_model_sd_at_rp[1L, ]
    } else {
      apply(per_model_sd_at_rp, 2L, stats::median, na.rm = TRUE)
    }
    coef_lo_vec <- central_vec + z_coef_lo * coef_sd_vec
    coef_hi_vec <- central_vec + z_coef_hi * coef_sd_vec

    intermod_lo_vec <- if (is_hist) {
      rep(NA_real_, length(RPs_keep))
    } else {
      apply(per_model_rp, 2L, stats::quantile,
        probs = bq_ens[["lo"]], na.rm = TRUE
      )
    }
    intermod_hi_vec <- if (is_hist) {
      rep(NA_real_, length(RPs_keep))
    } else {
      apply(per_model_rp, 2L, stats::quantile,
        probs = bq_ens[["hi"]], na.rm = TRUE
      )
    }

    # Total band combines coefficient and inter-model variance at each RP,
    # assuming independence. Inter-annual variability is already baked
    # into the per-rank value so it isn't added a second time here.
    var_across_at_rp <- if (is_hist) {
      rep(0, length(RPs_keep))
    } else {
      apply(per_model_rp, 2L, stats::var, na.rm = TRUE)
    }
    var_across_at_rp[is.na(var_across_at_rp)] <- 0
    sd_total_vec <- sqrt(pmax(coef_sd_vec^2 + var_across_at_rp, 0,
      na.rm = FALSE
    ))
    total_lo_vec <- central_vec + z_coef_lo * sd_total_vec
    total_hi_vec <- central_vec + z_coef_hi * sd_total_vec

    make_row <- function(estimate, vec) {
      tibble::tibble(
        scenario = scenario_label,
        Estimate = estimate,
        rp_name = names(RPs_keep),
        rp_label = names(RPs_keep),
        value = vec - hist_ref,
        absolute_value = vec,
        n_obs = n_pts,
        is_historical = is_hist
      )
    }
    coef_lo_lbl <- paste0("Coef ", pct_label(bq_coef[["lo"]]))
    coef_hi_lbl <- paste0("Coef ", pct_label(bq_coef[["hi"]]))
    ens_lo_lbl <- paste0("Ensemble ", pct_label(bq_ens[["lo"]],
      use_minmax = TRUE
    ))
    ens_hi_lbl <- paste0("Ensemble ", pct_label(bq_ens[["hi"]],
      use_minmax = TRUE
    ))
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
    supports <- dplyr::bind_rows(support_records)
    attr(out, "adverse_support") <- supports
    out
  }

  rows <- lapply(seq_along(series), function(i) {
    label <- names(series)[[i]]
    one_scenario(series[[i]], label, identical(label, "Historical"))
  })
  dplyr::bind_rows(Filter(Negate(is.null), rows))
}

#' The return-period decision table shown in the Results pane
#' @param threshold_tbl Result of `step2_threshold_table()`.
#' @param sim_summary Run summary (`historical_years`), or `NULL`.
#' @inheritParams step2_threshold_table
#' @return A data frame, or `NULL` when there is nothing to show.
#' @noRd
step2_threshold_df <- function(threshold_tbl, method, so, sim_summary = NULL) {
  tbl <- threshold_tbl
  if (is.null(tbl) || !nrow(tbl) || !"Estimate" %in% names(tbl)) {
    return(NULL)
  }
  n_h_yrs <- tryCatch(
    {
      run_info <- sim_summary %||% list()
      hy <- run_info$historical_years %||% integer(0)
      if (length(hy) >= 2L) as.integer(hy[2] - hy[1] + 1L) else max(tbl$n_obs, na.rm = TRUE)
    },
    error = function(e) max(tbl$n_obs, na.rm = TRUE)
  )

  build_threshold_table_df(
    threshold_tbl = tbl,
    group_order   = "scenario_x_year",
    show_coef     = TRUE,
    adverse_only  = TRUE,
    method        = method,
    so            = so,
    n_hist_years  = n_h_yrs
  )
}

#' Data behind the adverse-year dot plot
#' @param threshold_tbl Result of `step2_threshold_table()`.
#' @param ensemble_none The ensemble band is `"none"`: no inter-model spread.
#' @inheritParams step2_threshold_table
#' @noRd
step2_adverse_dot_view <- function(threshold_tbl, method, so, ensemble_none = TRUE) {
  table <- threshold_tbl
  historical_rows <- table$scenario == "Historical" &
    table$Estimate %in% c("Single historical estimate", "Equal-model mean", "Central (P50)")
  historical_year_count <- if ("n_obs" %in% names(table) && any(historical_rows)) {
    max(as.numeric(table$n_obs[historical_rows]), na.rm = TRUE)
  } else {
    NA_real_
  }
  rp_map <- metric_decision_return_periods(method, so)
  if (is.finite(historical_year_count)) {
    rp_map <- rp_map[names(rp_map) == "Expected" |
      vapply(names(rp_map), function(label) {
        if (identical(label, "Expected")) return(TRUE)
        historical_year_count >= as.integer(sub("^Adverse 1-in-", "", label))
      }, logical(1))]
  }
  dot <- step2_adverse_dot_data(
    table[table$rp_name %in% unname(rp_map), , drop = FALSE],
    method = method,
    so = so
  )
  if (isTRUE(ensemble_none) && nrow(dot)) {
    dot$intermod_lo <- NA_real_
    dot$intermod_hi <- NA_real_
  }
  dot
}

# Headline-card inputs ----

#' Observed-survey calibration of the simulated historical baseline
#' @param hs Historical result (`svy`, `so`).
#' @param hist_tbl Historical aggregation table of the metric.
#' @param pov_line Poverty line of the run.
#' @param weight_key `"weighted"` or `"unweighted"`.
#' @noRd
step2_baseline_check_view <- function(hs, hist_tbl, method, pov_line, weight_key) {
  sim_vals <- hist_tbl$value
  step2_baseline_check(
    hs$svy, hs$so, method, pov_line,
    use_weights = identical(weight_key, "weighted"),
    simulated = mean(sim_vals, na.rm = TRUE),
    metadata = metric_metadata(method, hs$so %||% NULL)
  )
}

#' Coefficient uncertainty of the climate shift of the first future scenario
#' @param bands Headline bands (`step2_headline_bands()`).
#' @param hist_tbl,scn_tbls Raw aggregation tables of the historical run and
#'   of each scenario (`F_agg_all` present when coefficient uncertainty ran).
#' @noRd
step2_delta_ci_view <- function(bands, hist_tbl, scn_tbls) {
  fut <- bands[!bands$is_historical, , drop = FALSE]
  if (!nrow(fut)) {
    return(NULL)
  }
  step2_delta_ci(hist_tbl, scn_tbls[[fut$scenario[[1L]]]])
}

#' Weather-support summary of the first future scenario on the cards
#' @param bands Headline bands.
#' @param scenarios Scenario entries (`weather_support`).
#' @param selected_weather Selected weather (labels), or `NULL`.
#' @noRd
step2_weather_support_view <- function(bands, scenarios, selected_weather = NULL) {
  fut <- bands[!bands$is_historical, , drop = FALSE]
  if (!nrow(fut)) {
    return(NULL)
  }
  ws <- tryCatch(scenarios[[fut$scenario[[1L]]]]$weather_support, error = function(e) NULL)
  if (!is.data.frame(ws) || !nrow(ws)) {
    return(NULL)
  }
  sw <- selected_weather
  if (!is.null(sw) && all(c("name", "label") %in% names(sw))) {
    lab <- stats::setNames(as.character(sw$label), as.character(sw$name))
    ws$weather_label <- unname(lab[ws$weather_variable])
  }
  ws
}

#' Metric metadata of the headline cards
#' @param hs Historical result (`so`, `analysis_unit`).
#' @noRd
step2_card_metadata <- function(hs, method, pov_line, weight_key) {
  metric_metadata(
    method,
    hs$so %||% NULL,
    pov_line = if (identical(method, "prosperity_gap")) NULL else pov_line,
    analysis_unit = hs$analysis_unit %||%
      .metric_context_value(hs$so, "level"),
    weighted = identical(weight_key, "weighted")
  )
}

#' Distributional incidence of every scenario by fixed baseline decile
#' @param hs Historical result (`svy`, `so`, `pipeline`).
#' @param scenarios Scenario entries.
#' @param labels Scenarios to include.
#' @noRd
step2_incidence_all <- function(hs, scenarios, labels = names(scenarios)) {
  if (!length(labels)) {
    return(tibble::tibble())
  }
  is_log <- identical(hs$so$transform, "log")
  svy <- hs$svy %||% hs$survey
  if (is.null(svy)) {
    return(tibble::tibble())
  }
  dplyr::bind_rows(lapply(labels, function(nm) {
    entry <- scenarios[[nm]]
    pipes <- entry$pipelines %||% list(entry$pipeline %||% entry)
    step2_incidence_by_decile(svy, hs$so$name, hs$pipeline, pipes, is_log, nm)
  }))
}

# Aggregation of a run ----

#' Poverty line the Results pane starts from
#'
#' The outcome's own line when it has one, otherwise $3.00 a day (the default
#' of the Results pane's poverty-line control).
#' @param so Selected outcome.
#' @noRd
step2_default_pov_line <- function(so) {
  pl <- so[["povline"]][1]
  if (!is.null(so) && "povline" %in% names(so) && !is.null(pl) && is.finite(pl) && pl > 0) {
    pl
  } else {
    3
  }
}

#' Aggregation tables of every metric for the historical run and each scenario
#'
#' The tables the Results pane shows: one table per metric from
#' `step2_display_aggregation_suite()`, computed once per group, at the
#' pane's initial poverty line and kernel bandwidth.
#'
#' @param hs The historical result of a Step 2 run.
#' @param scenarios The scenario entries of the run.
#' @param skip_coef Coefficient uncertainty was skipped in the run.
#' @param pov_line Poverty line (`step2_default_pov_line()` when `NULL`).
#' @param bandwidth_p0 Kernel bandwidth of the poverty-rate metric.
#' @return A list: `methods`, `weight_key`, `pov_line`, `hist` (metric ->
#'   table) and `scn` (scenario -> metric -> table).
#' @noRd
step2_run_aggregates <- function(hs, scenarios, skip_coef, pov_line = NULL, bandwidth_p0 = 0.05) {
  so <- hs$so
  pov_line <- pov_line %||% step2_default_pov_line(so)
  methods <- unname(hist_aggregate_choices(so$type, so$name))
  method <- if ("prosperity_gap" %in% methods) "prosperity_gap" else methods[[1L]]
  residuals <- hs$residuals %||% "original"
  seed <- .step2_run_seed(hs)
  cache <- .new_aggregation_preparation_cache(max_entries = 32L)
  suite <- function(pipelines, so, shared_context, historical) {
    step2_display_aggregation_suite(
      pipelines = pipelines, method = method, so = so, residuals = residuals,
      skip_coef = skip_coef, pov_line = pov_line, bandwidth_p0 = bandwidth_p0,
      shared_context = shared_context, historical = historical,
      preparation_cache = cache, seed = seed
    )
  }
  hist <- suite(hs$pipeline, so, hs$shared_context, TRUE)
  scn <- lapply(scenarios, function(s) {
    suite(s$pipelines, s$so, s$shared_context, FALSE)$tables
  })
  list(
    methods = methods, weight_key = hist$weight_key, pov_line = pov_line,
    hist = hist$tables, scn = scn
  )
}

# Batch tables ----

#' The `annual` table: one row per scenario, metric, member and year
#'
#' The unnested `value_all` / `value_all_sd` of the aggregation tables, so each
#' climate-model member keeps its own value and standard deviation. `sd` is
#' the delta-method standard deviation of the member's annual aggregate
#' (coefficient uncertainty plus residual variance); `var_within` and
#' `var_across` are the ensemble variances of the year and repeat on each
#' member row. The coefficient gradients (`F_agg_all`) are not kept.
#'
#' @param agg Result of `step2_run_aggregates()`.
#' @return A data frame (`policy_id` is `NA`: the baseline arm).
#' @noRd
step2_annual_table <- function(agg) {
  one <- function(tbl, scenario, metric) {
    if (is.null(tbl) || !nrow(tbl)) {
      return(NULL)
    }
    vals <- lapply(tbl$value_all, as.numeric)
    n <- lengths(vals)
    ids <- lapply(seq_along(vals), function(k) {
      id <- as.character(tbl$model_id[[k]])
      if (length(id) == n[[k]]) id else paste0("m", seq_len(n[[k]]))
    })
    sds <- lapply(seq_along(vals), function(k) {
      s <- as.numeric(tbl$value_all_sd[[k]])
      if (length(s) == n[[k]]) s else rep(s, length.out = n[[k]])
    })
    data.frame(
      policy_id = NA_character_, scenario = scenario, metric = metric,
      member = unlist(ids, use.names = FALSE), sim_year = rep(as.integer(tbl$sim_year), n),
      value = unlist(vals, use.names = FALSE), sd = unlist(sds, use.names = FALSE),
      var_within = rep(as.numeric(tbl$var_within), n), var_across = rep(as.numeric(tbl$var_across), n),
      weighted = rep(as.logical(tbl$weighted), n), stringsAsFactors = FALSE
    )
  }
  arms <- c(list(Historical = agg$hist), agg$scn)
  rows <- list()
  for (scenario in names(arms)) {
    for (metric in names(arms[[scenario]])) {
      rows[[length(rows) + 1L]] <- one(arms[[scenario]][[metric]], scenario, metric)
    }
  }
  out <- dplyr::bind_rows(rows)
  if (!nrow(out)) {
    return(NULL)
  }
  out
}

# Ensemble band the `summary` views are stored at: the 10th to 90th percentile
# of the climate models (batch/docs/tables.md). The Results pane starts
# at "none", which collapses the band to the median; a stored table needs the
# spread.
STEP2_SUMMARY_ENSEMBLE_BAND <- "p10_p90"

#' The Results views of one metric at the stored defaults
#'
#' Outcome level (no deviation), coefficient band p10-p90 and the ensemble
#' band `STEP2_SUMMARY_ENSEMBLE_BAND`: the views the Results pane shows for
#' that state of its controls, from the aggregation tables of `agg`.
#'
#' @param agg Result of `step2_run_aggregates()`.
#' @param hs,scenarios Historical result and scenario entries (annotated).
#' @param method The metric.
#' @param selected_weather Selected weather (labels), or `NULL`.
#' @return A list: `bands`, `headline_bands`, `timeseries`, `threshold`,
#'   `variance`, `adverse_dot` and the headline `cards` (`NULL` without
#'   results).
#' @noRd
step2_method_views <- function(agg, hs, scenarios, method, selected_weather = NULL) {
  so <- hs$so
  bq_ens <- step2_ensemble_band_q(STEP2_SUMMARY_ENSEMBLE_BAND)
  series <- c(list(Historical = agg$hist[[method]]), lapply(agg$scn, `[[`, method))
  bands <- step2_pointrange_bands(series, bq_ens)
  hb <- step2_headline_bands(bands, series)
  ts <- step2_timeseries_curves(series)
  thr <- step2_threshold_table(series, resolve_band_q("p10_p90"), bq_ens, 0, method, so)
  cards <- if (nrow(hb) && all(c("is_historical", "scenario") %in% names(hb))) {
    step2_headline_cards(
      bands = hb, threshold_tbl = thr, hist_sim = hs, saved_scenarios = scenarios,
      method = method, timeseries_curves = ts, deviation = "none",
      baseline_check = tryCatch(
        step2_baseline_check_view(hs, agg$hist[[method]], method, agg$pov_line, agg$weight_key),
        error = function(e) NULL
      ),
      delta_ci = tryCatch(
        step2_delta_ci_view(hb, agg$hist[[method]], lapply(agg$scn, `[[`, method)),
        error = function(e) NULL
      ),
      weather_support = tryCatch(
        step2_weather_support_view(hb, scenarios, selected_weather),
        error = function(e) NULL
      ),
      metadata = step2_card_metadata(hs, method, agg$pov_line, agg$weight_key)
    )
  }
  list(
    bands = bands, headline_bands = hb, timeseries = ts, threshold = thr,
    variance = step2_variance_breakdown(series),
    adverse_dot = step2_adverse_dot_view(thr, method, so, ensemble_none = FALSE),
    cards = cards
  )
}

#' The `summary` table: the Results views of every metric, in long form
#'
#' Sections: `expected` (expected outcome with its inter-annual and inter-model
#' bands), `adverse_year` (the outcome in adverse years with the coefficient,
#' ensemble and pooled bands), `adverse_dot` (the values behind the
#' return-period dot plot), `uncertainty` (variance components),
#' `headline` (the five headline cards) and `incidence` (effect by baseline
#' decile). All at the app defaults: outcome level (no deviation), the
#' coefficient band p10-p90 and the ensemble band `STEP2_SUMMARY_ENSEMBLE_BAND`.
#'
#' @param agg Result of `step2_run_aggregates()`.
#' @param hs,scenarios Historical result and scenario entries (annotated).
#' @param selected_weather Selected weather (labels), or `NULL`.
#' @return A data frame with the columns `scenario`, `metric`, `section`,
#'   `measure`, `group`, `return_period`, `estimate`, `lo`, `hi`, `n`, `text`.
#' @noRd
step2_summary_table <- function(agg, hs, scenarios, selected_weather = NULL) {
  row <- function(scenario, metric, section, measure, group = NA_character_,
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
  out <- list()
  for (m in agg$methods) {
    views <- step2_method_views(agg, hs, scenarios, m, selected_weather)
    hb <- views$headline_bands
    thr <- views$threshold
    dot <- views$adverse_dot
    var <- views$variance
    cards <- views$cards

    if (nrow(hb)) {
      out[[length(out) + 1L]] <- rbind(
        row(hb$scenario, m, "expected", "expected", "interannual", NA, hb$value,
          hb$interann_lo, hb$interann_hi, hb$n_models),
        row(hb$scenario, m, "expected", "expected", "intermodel", NA, hb$value,
          hb$intermod_lo, hb$intermod_hi, hb$n_models)
      )
    }

    if (!is.null(thr) && nrow(thr)) {
      key <- paste(thr$scenario, thr$rp_name, sep = "\r")
      for (k in unique(key)) {
        d <- thr[key == k, , drop = FALSE]
        mid <- d$absolute_value[d$Estimate %in% c("Single historical estimate", "Equal-model mean")]
        if (!length(mid)) mid <- NA_real_
        pair <- function(prefix) {
          v <- d$absolute_value[startsWith(d$Estimate, prefix)]
          c(if (length(v) >= 1L) v[[1L]] else NA_real_, if (length(v) >= 2L) v[[length(v)]] else NA_real_)
        }
        bandrows <- lapply(
          c(coefficient = "Coef ", ensemble = "Ensemble ", pooled = "Pooled "),
          pair
        )
        for (g in names(bandrows)) {
          if (g != "coefficient" && isTRUE(d$is_historical[[1L]])) next
          out[[length(out) + 1L]] <- row(
            d$scenario[[1L]], m, "adverse_year", "adverse_year_outcome", g, d$rp_name[[1L]],
            mid[[1L]], bandrows[[g]][[1L]], bandrows[[g]][[2L]], d$n_obs[[1L]]
          )
        }
      }
    }

    if (!is.null(dot) && nrow(dot)) {
      out[[length(out) + 1L]] <- row(
        dot$scenario, m, "adverse_dot", as.character(dot$rp_label), "ensemble", dot$rp_name,
        dot$value, dot$intermod_lo, dot$intermod_hi
      )
    }

    if (nrow(var)) {
      for (component in c("var_coef", "var_within", "var_across")) {
        out[[length(out) + 1L]] <- row(var$scenario, m, "uncertainty", component, NA, NA, var[[component]])
      }
    }

    if (!is.null(cards) && length(cards)) {
      focus <- hb$scenario[!hb$is_historical]
      focus <- if (length(focus)) focus[[1L]] else "Historical"
      hl <- step2_headline_df(cards)
      is_count <- hl$Summary_method == "simulation_count"
      parts <- list(
        historical = ifelse(is_count, NA_real_, hl$Historical_native),
        focus = hl$Focus_native, difference = hl$Difference_native,
        count = ifelse(is_count, hl$Historical_native, NA_real_)
      )
      for (g in names(parts)) {
        keep <- is.finite(parts[[g]])
        if (any(keep)) {
          out[[length(out) + 1L]] <- row(
            focus, m, "headline", hl$Metric[keep], g, NA, parts[[g]][keep], NA, NA, NA,
            if (identical(g, "focus")) hl$Value[keep] else NA_character_
          )
        }
      }
      keep <- is.finite(hl$Range_lower_native) & is.finite(hl$Range_upper_native)
      if (any(keep)) {
        out[[length(out) + 1L]] <- row(
          focus, m, "headline", hl$Metric[keep], "range", NA, NA, hl$Range_lower_native[keep],
          hl$Range_upper_native[keep]
        )
      }
    }
  }

  inc <- step2_incidence_all(hs, scenarios)
  if (nrow(inc)) {
    out[[length(out) + 1L]] <- row(
      inc$scenario, NA_character_, "incidence", "household_effect", paste0("decile_", inc$decile), NA,
      inc$effect, NA, NA, inc$n_households
    )
  }
  res <- dplyr::bind_rows(out)
  res$policy_id <- NA_character_
  res[c("policy_id", setdiff(names(res), "policy_id"))]
}

#' The `sim_weather` table: weather support of each scenario and its members
#'
#' Long form with a `section`: `scenario` (period and number of climate
#' models), `members` (one row per climate-model member) and `support` (per
#' weather variable: the share of simulated values outside the reference
#' support of the historical weather, the same pooled summary the Diagnostics
#' tab shows).
#'
#' @param scenarios The scenario entries of the run.
#' @return A data frame, or `NULL` without scenarios.
#' @noRd
step2_sim_weather_table <- function(scenarios) {
  if (!length(scenarios)) {
    return(NULL)
  }
  row <- function(scenario, section, statistic, member = NA_character_, variable = NA_character_,
                  value = NA_real_, text = NA_character_) {
    k <- max(lengths(list(member, variable, statistic, value, text)))
    data.frame(
      scenario = scenario, section = section, member = rep_len(as.character(member), k),
      variable = rep_len(as.character(variable), k), statistic = rep_len(as.character(statistic), k),
      value = rep_len(as.numeric(value), k), text = rep_len(as.character(text), k),
      stringsAsFactors = FALSE
    )
  }
  rows <- list()
  for (label in names(scenarios)) {
    s <- scenarios[[label]]
    yr <- suppressWarnings(as.numeric(s$year_range))
    rows[[length(rows) + 1L]] <- row(
      label, "scenario",
      c("period_start", "period_end", "n_models", "n_models_requested"),
      value = c(yr[1], yr[2], s$n_models %||% length(s$pipelines),
        s$n_models_requested %||% s$n_models %||% length(s$pipelines))
    )
    members <- names(s$pipelines) %||% paste0("model_", seq_along(s$pipelines))
    if (length(members)) {
      rows[[length(rows) + 1L]] <- row(label, "members", "member", member = members, value = 1)
    }
    ws <- s$weather_support
    if (is.data.frame(ws) && nrow(ws)) {
      num <- c(
        "n_reference", "n_scenario", "robust_lo", "robust_hi", "outside_n", "outside_share",
        "warning", "n_members", "max_member_share"
      )
      for (i in seq_len(nrow(ws))) {
        v <- ws$weather_variable[[i]]
        rows[[length(rows) + 1L]] <- row(
          label, "support", num, variable = v,
          value = vapply(num, function(f) as.numeric(ws[[f]][[i]] %||% NA_real_), numeric(1))
        )
        rows[[length(rows) + 1L]] <- row(
          label, "support", c("reference_label", "warning_rule", "is_binned"), variable = v,
          text = c(
            as.character(ws$reference_label[[i]]), as.character(ws$warning_rule[[i]]),
            as.character(ws$is_binned[[i]])
          )
        )
      }
    }
  }
  dplyr::bind_rows(rows)
}

#' All batch tables of one Step 2 run
#'
#' @param result A finished and annotated run: `hist_sim_result` and
#'   `new_scenarios` (`step2_compute()$result` after `wise_step2_annotate()`).
#' @param skip_coef Coefficient uncertainty was skipped in the run.
#' @param selected_weather Selected weather (labels), or `NULL`.
#' @return A list: `annual`, `summary`, `sim_weather`.
#' @noRd
step2_batch_tables <- function(result, skip_coef, selected_weather = NULL) {
  hs <- result$hist_sim_result
  scenarios <- result$new_scenarios
  agg <- step2_run_aggregates(hs, scenarios, skip_coef)
  list(
    annual = step2_annual_table(agg),
    summary = step2_summary_table(agg, hs, scenarios, selected_weather),
    sim_weather = step2_sim_weather_table(scenarios)
  )
}

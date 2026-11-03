# Seasonal forecast: members placed in the same-window reference distribution ----

#' Place forecast members in the same-window reference distribution
#'
#' `member_values` is one outcome per forecast member for the target window. `reference_values` is the
#' same outcome computed under observed weather for the same calendar months in each reference year.
#' A member is as adverse as `p` of the reference years when `p` is the share of reference years at
#' least as adverse as the member; its return period is `1 / p`. With `n` reference years, return
#' periods beyond `n / 2` (about 1-in-15 for 30 years) are not resolved: they are reported as
#' beyond the observed range (`NA` return period, `beyond = TRUE`) rather than extrapolated.
#'
#' The member share is an indicator, not a probability: the ensemble spread is not calibrated and
#' skill is not established. There is no return period for the ensemble mean.
#'
#' @param member_values Numeric vector, one value per member.
#' @param reference_values Numeric vector, one value per reference year.
#' @param adverse_tail `"high"` when higher values are worse (for example headcount), else `"low"`.
#' @return A list with `members` (data frame: `value`, `p_adverse`, `return_period`, `beyond`),
#'   `summary` (named list) and `n_reference`.
#' @noRd
.forecast_placement_stats <- function(member_values, reference_values, adverse_tail = "low") {
  member_values <- as.numeric(member_values)
  reference <- as.numeric(reference_values)
  reference <- reference[is.finite(reference)]
  n_ref <- length(reference)
  high <- identical(adverse_tail, "high")
  p_adverse <- vapply(member_values, function(v) {
    if (!is.finite(v) || !n_ref) return(NA_real_)
    mean(if (high) reference >= v else reference <= v)
  }, numeric(1L))
  cap <- n_ref / 2
  rp <- ifelse(is.na(p_adverse) | p_adverse <= 0, NA_real_, 1 / p_adverse)
  beyond <- !is.na(p_adverse) & (p_adverse <= 0 | (!is.na(rp) & rp > cap))
  rp[beyond] <- NA_real_
  worse_than <- function(threshold) {
    mean(if (high) member_values >= threshold else member_values <= threshold, na.rm = TRUE)
  }
  p10 <- if (n_ref) stats::quantile(reference, if (high) 0.9 else 0.1, names = FALSE) else NA_real_
  ref_median <- if (n_ref) stats::median(reference) else NA_real_
  med_member <- stats::median(member_values, na.rm = TRUE)
  med_p <- if (n_ref && is.finite(med_member)) mean(if (high) reference >= med_member else reference <= med_member) else NA_real_
  med_rp <- if (is.na(med_p) || med_p <= 0 || 1 / med_p > cap) NA_real_ else 1 / med_p
  list(
    members = data.frame(value = member_values, p_adverse = p_adverse, return_period = rp, beyond = beyond),
    n_reference = n_ref,
    summary = list(
      n_members = sum(is.finite(member_values)),
      member_median = med_member,
      reference_median = ref_median,
      difference_median = med_member - ref_median,
      reference_adverse_1in10 = p10,
      share_worse_than_median = if (n_ref) worse_than(ref_median) else NA_real_,
      share_worse_than_1in10 = if (n_ref) worse_than(p10) else NA_real_,
      median_member_return_period = med_rp,
      median_member_beyond = !is.na(med_p) && (med_p <= 0 || 1 / med_p > cap),
      n_beyond = sum(beyond)
    )
  )
}

#' Member outcomes and same-window reference outcomes of a forecast scenario
#'
#' Aggregates the scenario's member pipelines and its `reference_pipelines` (one per reference
#' year) with the Results tab's aggregation for `method`, then places each member
#' (`.forecast_placement_stats()`).
#'
#' @param scenario One forecast element of `step2_compute()$result$new_scenarios`.
#' @inheritParams step2_display_aggregation_suite
#' @return `NULL` when the scenario has no reference, else the list from `.forecast_placement_stats()`
#'   plus `method`, `adverse_tail`, `reference` (data frame: `year`, `value`) and `member_ids`.
#' @noRd
step2_forecast_placement <- function(scenario, method, so, residuals, skip_coef, pov_line,
                                     bandwidth_p0 = 0.05, seed = WISEAPP_DEFAULT_SEED,
                                     shared_context = scenario$shared_context) {
  reference <- scenario$reference_pipelines
  members <- scenario$pipelines
  if (!length(reference) || !length(members)) return(NULL)
  per_unit <- function(pipelines) {
    # The aggregation pools the pipelines of one sim_year as "models"; one common year gives one value each.
    pipelines <- lapply(pipelines, function(p) {
      p$sim_year <- rep(0L, length(p$sim_year))
      p
    })
    tbl <- step2_display_aggregation_suite(
      pipelines, method, so, residuals, skip_coef, pov_line, bandwidth_p0 = bandwidth_p0,
      shared_context = shared_context, seed = seed
    )$tables[[method]]
    if (is.null(tbl) || nrow(tbl) != 1L) return(NULL)
    data.frame(id = as.character(tbl$model_id[[1L]]), value = as.numeric(tbl$value_all[[1L]]))
  }
  m <- per_unit(members)
  r <- per_unit(reference)
  if (is.null(m) || is.null(r)) return(NULL)
  tail <- metric_metadata(method, so)$adverse_tail %||% "low"
  out <- .forecast_placement_stats(m$value, r$value, tail)
  out$members$member <- m$id
  out$reference <- data.frame(year = as.integer(sub("^refyear_", "", r$id)), value = r$value)
  out$method <- method
  out$adverse_tail <- tail
  out
}

#' Placement for the first forecast scenario of a result, or `NULL`
#'
#' Reads the reference of the first scenario that carries `reference_pipelines`, aggregated with the
#' display settings of the Results tab (`method`, `pov_line`, `bandwidth_p0`) at point estimates.
#' Any failure gives `NULL`, so the cards fall back to their placement-free form.
#' @param scenarios Named list of scenario entries (`new_scenarios`).
#' @param hs The historical result (supplies `so`, residual mode and seed).
#' @noRd
step2_forecast_placement_view <- function(scenarios, method, hs, pov_line = NULL, bandwidth_p0 = 0.05) {
  has_reference <- vapply(scenarios %||% list(), function(s) length(s$reference_pipelines) > 0L, logical(1L))
  if (!any(has_reference) || is.null(hs$so)) return(NULL)
  scenario <- scenarios[has_reference][[1L]]
  tryCatch(
    step2_forecast_placement(
      scenario, method, hs$so, hs$residuals %||% "original", skip_coef = TRUE,
      pov_line = pov_line %||% step2_default_pov_line(hs$so), bandwidth_p0 = bandwidth_p0,
      seed = .step2_run_seed(hs)
    ),
    error = function(e) NULL
  )
}

#' Cards text for a placement
#' @param placement Result of `step2_forecast_placement()`.
#' @return A list: `value` (share of members worse than the reference 1-in-10 level), `median_text`
#'   (where the median member falls), `note` (indicator wording) and `info`.
#' @noRd
.forecast_placement_text <- function(placement) {
  s <- placement$summary
  n_ref <- placement$n_reference
  p_med <- stats::median(placement$members$p_adverse, na.rm = TRUE)
  median_text <- if (!is.finite(p_med)) {
    "Placement unavailable"
  } else if (p_med >= 0.5) {
    "Median member is better than the median historical year"
  } else if (isTRUE(s$median_member_beyond)) {
    "Median member is beyond the observed range"
  } else {
    paste0("Median member is about a 1-in-", format(max(1, round(s$median_member_return_period)),
      big.mark = ","), " outcome")
  }
  list(
    value = paste0(formatC(100 * s$share_worse_than_1in10, format = "f", digits = 0), "% of members"),
    median_text = median_text,
    note = paste0("Worse than the historical 1-in-10 \u00b7 ", n_ref, " historical years, same months"),
    info = paste0(
      "Each forecast member is placed in the distribution of the same outcome under observed weather ",
      "for the same calendar months in each historical year. ",
      "The share of members is an indicator, not a probability: the member spread is not calibrated and ",
      "skill is not established. Outcomes rarer than about 1-in-", floor(n_ref / 2),
      " are reported as beyond the observed range, not extrapolated."
    )
  )
}

#' Batch tables of the forecast scenarios of one Step 2 run
#'
#' For every forecast scenario with a same-window reference and every metric of the Results tab:
#' `forecast` (one row per member and per reference year: outcome, adverse-side share and return period)
#' and `summary` rows with sections `placement` (the summary of `.forecast_placement_stats()`), `skill`
#' (the flag of each target month, in `text`; `n` is the lead) and `season` (the share of the model's
#' training observations interviewed in the target months, and the share an even spread would give).
#'
#' @param hs,scenarios Historical result and scenario entries.
#' @param agg Result of `step2_run_aggregates()` (supplies the metrics and the poverty line).
#' @return `NULL` without a forecast, else a list: `forecast`, `summary`.
#' @noRd
step2_forecast_batch_tables <- function(hs, scenarios, agg) {
  has_reference <- vapply(scenarios %||% list(), function(s) length(s$reference_pipelines) > 0L, logical(1L))
  if (!any(has_reference)) return(NULL)
  methods <- setdiff(agg$methods, "prosperity_gap")
  summ_row <- function(scenario, metric, section, measure, group = NA_character_, estimate = NA_real_,
                       n = NA_real_, text = NA_character_) {
    k <- max(lengths(list(measure, group, estimate, n, text)))
    data.frame(
      scenario = scenario, metric = rep_len(as.character(metric), k), section = section,
      measure = rep_len(as.character(measure), k), group = rep_len(as.character(group), k),
      return_period = NA_character_, estimate = rep_len(as.numeric(estimate), k),
      lo = NA_real_, hi = NA_real_, n = rep_len(as.numeric(n), k), text = rep_len(as.character(text), k),
      stringsAsFactors = FALSE
    )
  }
  forecast <- list()
  summary <- list()
  for (label in names(scenarios)[has_reference]) {
    s <- scenarios[[label]]
    for (m in methods) {
      pl <- step2_forecast_placement(
        s, m, hs$so, hs$residuals %||% "original", skip_coef = TRUE, pov_line = agg$pov_line,
        seed = .step2_run_seed(hs)
      )
      if (is.null(pl)) next
      forecast[[length(forecast) + 1L]] <- rbind(
        data.frame(scenario = label, metric = m, kind = "member", id = pl$members$member, year = NA_integer_,
          value = pl$members$value, p_adverse = pl$members$p_adverse,
          return_period = pl$members$return_period, beyond = pl$members$beyond, stringsAsFactors = FALSE),
        data.frame(scenario = label, metric = m, kind = "reference",
          id = paste0("refyear_", pl$reference$year), year = as.integer(pl$reference$year),
          value = pl$reference$value, p_adverse = NA_real_, return_period = NA_real_, beyond = NA,
          stringsAsFactors = FALSE)
      )
      stats <- unlist(lapply(pl$summary, as.numeric))
      summary[[length(summary) + 1L]] <- summ_row(
        label, m, "placement", names(stats), estimate = stats, n = pl$n_reference
      )
    }
    sk <- s$skill
    if (!is.null(sk)) {
      if (is.data.frame(sk$months)) {
        month_key <- format(sk$months$month, "%Y-%m")
        if ("variable" %in% names(sk$months)) month_key <- paste(sk$months$variable, month_key)
        summary[[length(summary) + 1L]] <- summ_row(
          label, NA_character_, "skill", "skill_flag", group = month_key,
          estimate = sk$months$acc, n = sk$months$lead_month, text = sk$months$skill_flag
        )
      } else {
        summary[[length(summary) + 1L]] <- summ_row(label, NA_character_, "skill", "skill_flag", text = sk$text)
      }
    }
    tm <- s$training_months
    if (!is.null(tm)) {
      summary[[length(summary) + 1L]] <- summ_row(
        label, NA_character_, "season", c("training_month_share", "training_month_expected"),
        estimate = c(tm$share, tm$expected)
      )
    }
  }
  list(forecast = dplyr::bind_rows(forecast), summary = dplyr::bind_rows(summary))
}

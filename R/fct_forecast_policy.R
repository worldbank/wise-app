# Seasonal forecast: policy effect in the forecast window (Step 3) ----

#' Policy effect under a seasonal forecast, against the same-window reference years
#'
#' Places the baseline arm and the policy arm of one forecast scenario in their same-window reference
#' (`step2_forecast_placement()`), pairs each member and each reference year with itself across the arms, and
#' reports the policy effect of the median member and of the median reference year. The share of members
#' worse than the baseline 1-in-10 reference level is given without and with the policy at that one fixed level.
#'
#' @param baseline,policy The forecast scenario of the baseline and of the policy arm (same members and reference).
#' @inheritParams step2_forecast_placement
#' @return `NULL` when either arm has no placement, else a list: `baseline`, `policy` (placements),
#'   `effect_members`, `effect_reference` (paired differences), `summary`, `method`, `adverse_tail`.
#' @noRd
step3_forecast_policy <- function(baseline, policy, method, so, residuals, skip_coef, pov_line,
                                  bandwidth_p0 = 0.05, seed = WISEAPP_DEFAULT_SEED) {
  place <- function(scenario) {
    step2_forecast_placement(scenario, method, so, residuals, skip_coef, pov_line,
      bandwidth_p0 = bandwidth_p0, seed = seed, shared_context = scenario$shared_context)
  }
  pb <- place(baseline)
  pp <- place(policy)
  if (is.null(pb) || is.null(pp)) return(NULL)
  if (!identical(pb$members$member, pp$members$member) || !identical(pb$reference$year, pp$reference$year)) {
    return(NULL)
  }
  high <- identical(pb$adverse_tail, "high")
  threshold <- pb$summary$reference_adverse_1in10
  worse <- function(x) mean(if (high) x >= threshold else x <= threshold, na.rm = TRUE)
  effect_members <- pp$members$value - pb$members$value
  effect_reference <- pp$reference$value - pb$reference$value
  list(
    baseline = pb, policy = pp,
    effect_members = effect_members, effect_reference = effect_reference,
    summary = list(
      n_members = length(effect_members),
      effect_member_median = stats::median(effect_members, na.rm = TRUE),
      effect_reference_median = stats::median(effect_reference, na.rm = TRUE),
      share_worse_baseline = worse(pb$members$value),
      share_worse_policy = worse(pp$members$value),
      reference_adverse_1in10 = threshold
    ),
    method = method, adverse_tail = pb$adverse_tail
  )
}

#' Cards text of a policy effect under the forecast
#' @param view Result of `step3_forecast_policy()`.
#' @param digits Decimal places of the effects.
#' @noRd
.forecast_policy_text <- function(view, digits = 3L) {
  s <- view$summary
  fmt <- function(x) formatC(x, format = "f", digits = digits, flag = "+")
  pct <- function(x) paste0(formatC(100 * x, format = "f", digits = 0), "%")
  list(
    headline = paste0(
      "Median member: ", fmt(s$effect_member_median), " with the policy; median reference year: ",
      fmt(s$effect_reference_median), "."
    ),
    tail = paste0(
      "Members worse than the baseline 1-in-10 reference level: ", pct(s$share_worse_baseline),
      " without the policy, ", pct(s$share_worse_policy), " with it."
    ),
    info = paste0(
      "Each member and each reference year is evaluated with and without the policy, over the target months ",
      "only. The policy acts identically in every month of the window; there is no timing within it. ",
      "Shares of members are indicators, not probabilities: the member spread is not calibrated and skill ",
      "is not established."
    )
  )
}

#' Strip chart of baseline and policy outcomes for the forecast members and the reference years
#'
#' Four rows: reference years and forecast members, each without and with the policy, on one outcome axis. The
#' dashed line is the baseline reference 1-in-10 level.
#' @param view Result of `step3_forecast_policy()`.
#' @noRd
echart_forecast_policy <- function(view, x_label = "Outcome", height = "340px") {
  if (!is.list(view)) return(echart_blank("Forecast policy view unavailable.", height = height))
  rows <- list(
    list(label = "Reference years, baseline", y = 1, v = view$baseline$reference$value, color = .wise_slate, op = 0.45),
    list(label = "Reference years, policy", y = 2, v = view$policy$reference$value, color = .wise_slate, op = 0.9),
    list(label = "Forecast members, baseline", y = 3, v = view$baseline$members$value, color = .wise_forecast, op = 0.45),
    list(label = "Forecast members, policy", y = 4, v = view$policy$members$value, color = .wise_forecast, op = 0.95)
  )
  spread <- function(n, centre) centre + ((seq_len(n) * 7L) %% 11L - 5L) / 30
  series <- lapply(rows, function(r) {
    n <- length(r$v)
    list(
      name = r$label, type = "scatter", symbolSize = 7,
      data = lapply(seq_len(n), function(i) list(value = list(round(r$v[[i]], 5), spread(n, r$y)[[i]]), name = r$label)),
      itemStyle = list(color = r$color, opacity = r$op)
    )
  })
  series[[1L]]$markLine <- list(symbol = "none", silent = TRUE, animation = FALSE, data = list(list(
    xAxis = view$summary$reference_adverse_1in10,
    lineStyle = list(color = .wise_marker, type = "dashed", width = 1),
    label = list(show = TRUE, formatter = "Baseline reference 1-in-10", position = "insideEndTop",
      color = .wise_marker, fontSize = 10)
  )))
  e <- .e_new(height)
  e$x$opts$series <- series
  e$x$opts$xAxis <- list(list(
    type = "value", scale = TRUE, name = stringr::str_wrap(x_label, 40),
    nameLocation = "middle", nameGap = 30, nameTextStyle = wise_eaxis_name(),
    axisLabel = wise_eaxis_label(fontSize = 10), splitLine = wise_esplit_line()
  ))
  e$x$opts$yAxis <- list(list(
    type = "value", min = 0, max = 5, interval = 1,
    axisLabel = wise_eaxis_label(formatter = htmlwidgets::JS(paste0(
      "function(v){ return ({1:'Reference years, baseline',2:'Reference years, policy',",
      "3:'Forecast members, baseline',4:'Forecast members, policy'})[v] || ''; }"))),
    splitLine = list(show = FALSE)
  ))
  e$x$opts$grid <- list(containLabel = TRUE, left = 8, right = 24, top = 24, bottom = 44)
  e$x$opts$tooltip <- list(
    trigger = "item",
    formatter = htmlwidgets::JS(
      "function(p){ return p.name + ': ' + Number(p.value[0]).toLocaleString('en-US',{maximumFractionDigits:3}); }"
    )
  )
  wise_echart_theme(e)
}

#' Batch rows of the policy arm of the forecast scenarios of one Step 3 run
#'
#' `forecast`: the policy arm's member and reference-year outcomes per metric (the layout of
#' `step2_forecast_batch_tables()`). `summary` rows: section `placement` (the policy arm placed in its own
#' reference) and section `policy_effect` (`effect_member_median`, `effect_reference_median`,
#' `share_worse_baseline`, `share_worse_policy`, `reference_adverse_1in10`; `n` = members).
#' @return `NULL` without a forecast scenario, else a list: `forecast`, `summary`.
#' @noRd
step3_forecast_batch_tables <- function(base_hs, base_ss, pol_hs, pol_ss, methods, pov_line) {
  has <- vapply(base_ss %||% list(), function(x) length(x$reference_pipelines) > 0L, logical(1L)) &
    names(base_ss) %in% names(pol_ss)
  if (!any(has)) return(NULL)
  methods <- setdiff(methods, "prosperity_gap")
  agg <- list(methods = methods, pov_line = pov_line)
  pol <- step2_forecast_batch_tables(pol_hs, pol_ss[names(base_ss)[has]], agg)
  # The skill and training-month rows belong to the baseline arm.
  summary <- pol$summary[pol$summary$section == "placement", , drop = FALSE]
  rows <- list()
  for (label in names(base_ss)[has]) {
    for (m in methods) {
      view <- step3_forecast_policy(
        base_ss[[label]], pol_ss[[label]], m, base_hs$so, base_hs$residuals %||% "original",
        skip_coef = TRUE, pov_line = pov_line, seed = .step2_run_seed(base_hs)
      )
      if (is.null(view)) next
      stats <- unlist(lapply(view$summary[c("effect_member_median", "effect_reference_median",
        "share_worse_baseline", "share_worse_policy", "reference_adverse_1in10")], as.numeric))
      rows[[length(rows) + 1L]] <- data.frame(
        scenario = label, metric = m, section = "policy_effect", measure = names(stats),
        group = NA_character_, return_period = NA_character_, estimate = as.numeric(stats),
        lo = NA_real_, hi = NA_real_, n = view$summary$n_members, text = NA_character_,
        stringsAsFactors = FALSE
      )
    }
  }
  list(forecast = pol$forecast, summary = dplyr::bind_rows(summary, rows))
}

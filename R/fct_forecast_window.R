# Seasonal forecast: target-window scope of the Step 2 Results charts ----
#
# The annual Results views compare annual aggregates across weather years. A forecast member is an aggregate over
# the target window only, so in the window scope every chart compares like with like: the same-window reference
# years (observed weather for the target months in each reference year) take the place of Historical, and the
# forecast members take the place of a climate scenario. Both are laid out as one sample of units, one row per
# reference year or member, in the shape of an annual aggregation table, so the annual chart builders apply as they
# are. The member series carries its own label (`.step2_window_forecast_label()`), which the forecast-scenario
# detector does not match: the member-as-model special cases of the annual views do not apply to it.

.STEP2_WINDOW_FORECAST_PREFIX <- "Forecast ("
.STEP2_WINDOW_REFERENCE_PREFIX <- "Historical ("

# Display label of the annual Historical series next to the target-month series.
.STEP2_ANNUAL_LABEL <- "Historical (annual)"

#' Label of the member series of a forecast scenario in the window scope
#' @param scenario_label Forecast scenario label, for example
#'   `"Seasonal forecast / Nov 2026 - Jan 2027 (October 2026 run)"`.
#' @noRd
.step2_window_forecast_label <- function(scenario_label) {
  # The run is named in the run summary above the charts; the chart label keeps the target window only.
  window <- sub(" \\([^()]* run\\)$", "", sub("^[^/]+ / ", "", as.character(scenario_label)))
  paste0(.STEP2_WINDOW_FORECAST_PREFIX, window, ")")
}

# Annual wording of the shared chart builders, as it reads in the window scope (exact strings).
.STEP2_WINDOW_TEXT <- c(
  "Single historical estimate" = "Central estimate",
  "Equal-model mean" = "Central estimate"
)

#' Is `nm` the member series of the window scope?
#' @noRd
.step2_is_window_forecast <- function(nm) {
  startsWith(as.character(nm), .STEP2_WINDOW_FORECAST_PREFIX)
}

#' Is `nm` the Historical series of the forecast target months, as a row of a merged chart?
#'
#' A series of its own next to `"Historical"` (annual), so `is_historical` stays `FALSE` for it.
#' @noRd
.step2_is_window_reference <- function(nm) {
  startsWith(as.character(nm), .STEP2_WINDOW_REFERENCE_PREFIX)
}

#' Series of the forecast target months: not parsed as an SSP or a period
#' @noRd
.step2_is_forecast_like <- function(nm) {
  .step2_is_forecast_scenario(nm) | .step2_is_window_forecast(nm) | .step2_is_window_reference(nm)
}

#' Display label of the same-window reference years: Historical, with the target months
#' @param scenario One forecast scenario entry (`forecast$forecast_months`).
#' @noRd
.step2_window_reference_label <- function(scenario) {
  months <- scenario$forecast$forecast_months
  if (!length(months)) return("Historical (same months)")
  m <- format(as.Date(months), "%b")
  paste0("Historical (", if (length(m) > 1L) paste(m[[1L]], "-", m[[length(m)]]) else m[[1L]], ")")
}

#' One aggregation row per unit of a one-row, many-model table
#'
#' The table holds one `sim_year` row whose list-columns carry one value per unit (member or reference year). The
#' result has one row per unit, all under one `model_id`, as an annual table of a single model has one row per year.
#' A single model has no across-model variance; the within variance is the unit's own coefficient variance.
#' @param tbl Aggregation table with one row.
#' @param model_id Model id of every row.
#' @param sim_years Integer `sim_year` of each unit.
#' @param scenario Value of the `scenario` column (kept only when `tbl` has one).
#' @noRd
.step2_window_unit_table <- function(tbl, model_id, sim_years, scenario = NULL) {
  if (is.null(tbl) || nrow(tbl) != 1L) return(NULL)
  vals <- as.numeric(tbl$value_all[[1L]])
  n <- length(vals)
  if (!n || length(sim_years) != n) return(NULL)
  sds <- as.numeric(tbl$value_all_sd[[1L]])
  if (length(sds) != n) sds <- rep(NA_real_, n)
  resid <- if ("var_resid_all" %in% names(tbl)) as.numeric(tbl$var_resid_all[[1L]]) else numeric(0)
  if (length(resid) != n) resid <- rep(0, n)
  f_mat <- if ("F_agg_all" %in% names(tbl)) tbl$F_agg_all[[1L]] else NULL
  out <- tibble::tibble(
    sim_year = as.integer(sim_years),
    value = vals,
    model_id = as.list(rep(model_id, n)),
    value_all = as.list(vals),
    value_all_sd = as.list(sds),
    var_resid_all = as.list(resid),
    F_agg_all = lapply(seq_len(n), function(i) {
      if (is.matrix(f_mat) && nrow(f_mat) == n) f_mat[i, , drop = FALSE] else NULL
    }),
    var_within = sds^2,
    var_across = 0,
    agg_method = tbl$agg_method[[1L]],
    weighted = tbl$weighted[[1L]]
  )
  if ("scenario" %in% names(tbl) || !is.null(scenario)) out$scenario <- scenario %||% tbl$scenario[[1L]]
  out[order(out$sim_year), , drop = FALSE]
}

#' Window-scope aggregation tables of one forecast scenario
#'
#' Aggregates the member pipelines and the same-window reference pipelines with the Results tab's aggregation (one
#' common `sim_year`, units as models, as in `step2_forecast_placement()`), then lays each out as one sample
#' (`.step2_window_unit_table()`): the reference under `"Historical"`, one row per reference year; the members under
#' `.step2_window_forecast_label()`, one row per member (`sim_year` = member index).
#'
#' @param scenario One forecast scenario entry (with `reference_pipelines`).
#' @param label The scenario's label.
#' @inheritParams step2_display_aggregation_suite
#' @return `NULL` without a reference, else a list: `historical`, `members` (tables for `method`), `label` (member
#'   series label), `reference_label` (the Historical row, "Historical (Nov - Jan)"), `months_label` ("Nov - Jan"),
#'   `scenario_label` (the forecast scenario) and `member_ids`.
#' @noRd
step2_window_series <- function(scenario, label, method, so, residuals, skip_coef, pov_line,
                                bandwidth_p0 = 0.05, seed = WISEAPP_DEFAULT_SEED) {
  reference <- scenario$reference_pipelines
  members <- scenario$pipelines
  if (!length(reference) || !length(members)) return(NULL)
  pooled <- function(pipelines) {
    pipelines <- lapply(pipelines, function(p) {
      p$sim_year <- rep(0L, length(p$sim_year))
      p
    })
    step2_display_aggregation_suite(
      pipelines, method, so, residuals, skip_coef, pov_line, bandwidth_p0 = bandwidth_p0,
      shared_context = scenario$shared_context, seed = seed
    )$tables[[method]]
  }
  m_tbl <- pooled(members)
  r_tbl <- pooled(reference)
  if (is.null(m_tbl) || is.null(r_tbl) || nrow(m_tbl) != 1L || nrow(r_tbl) != 1L) return(NULL)
  ref_ids <- as.character(r_tbl$model_id[[1L]])
  ref_years <- suppressWarnings(as.integer(sub("^refyear_", "", ref_ids)))
  if (anyNA(ref_years)) return(NULL)
  member_ids <- as.character(m_tbl$model_id[[1L]])
  member_label <- .step2_window_forecast_label(label)
  reference_label <- .step2_window_reference_label(scenario)
  list(
    historical = .step2_window_unit_table(r_tbl, "Historical", ref_years, scenario = "Historical"),
    members = .step2_window_unit_table(m_tbl, member_label, seq_along(member_ids)),
    label = member_label,
    reference_label = reference_label,
    months_label = sub("^Historical \\((.*)\\)$", "\\1", reference_label),
    scenario_label = label,
    member_ids = member_ids
  )
}

#' Points of the Diagnostics robustness chart for the forecast target window
#'
#' One row per forecast member and one per same-window reference year, in the shape of `model_robustness_data()`
#' (a point is that unit's outcome; `n_weather_years` is `NA`). Values carry the window group's own deviation
#' reference, as the Results views do. The `unit` column names what a point is, for the tooltip.
#' @param w Result of `step2_window_series()`, or `NULL`.
#' @param deviation Results deviation setting (`"none"`, `"mean"` or `"median"`).
#' @return `NULL` without a window, else a tibble.
#' @noRd
step2_window_robustness_data <- function(w, deviation = "none") {
  if (is.null(w) || is.null(w$historical) || is.null(w$members)) return(NULL)
  ref <- step2_hist_ref(w$historical, deviation)
  pts <- rbind(
    data.frame(
      scenario = w$reference_label, model_id = as.character(w$historical$sim_year),
      value = w$historical$value - ref, unit = "Reference year", stringsAsFactors = FALSE
    ),
    data.frame(
      scenario = w$label, model_id = as.character(w$member_ids[w$members$sim_year]),
      value = w$members$value - ref, unit = "Forecast member", stringsAsFactors = FALSE
    )
  )
  pts <- pts[is.finite(pts$value), , drop = FALSE]
  if (!nrow(pts)) return(NULL)
  # One value per unit: model_robustness_data() takes each unit's mean, so the centre and the spread are its own.
  out <- model_robustness_data(transform(pts, sim_year = 1L))
  out$n_weather_years <- NA_integer_
  out$unit <- ifelse(out$scenario == w$reference_label, "Reference year", "Forecast member")
  out
}

#' Placement of the members in the reference years, from the window series
#'
#' The result of `step2_forecast_placement()` without a second aggregation of the same pipelines.
#' @param w Result of `step2_window_series()`.
#' @inheritParams step2_forecast_placement
#' @noRd
step2_window_placement <- function(w, method, so) {
  tail <- metric_metadata(method, so)$adverse_tail %||% "low"
  out <- .forecast_placement_stats(w$members$value, w$historical$value, tail)
  out$members$member <- w$member_ids
  out$reference <- data.frame(year = w$historical$sim_year, value = w$historical$value)
  out$method <- method
  out$adverse_tail <- tail
  out
}

#' Name the Historical row by its target months in a chart or table of the window scope
#'
#' Replaces the exact string `"Historical"` with `reference_label` (for example "Historical (Nov - Jan)") and the
#' annual table wording in `.STEP2_WINDOW_TEXT`, in every character leaf of `x`: the options of an echarts widget,
#' the columns of a data frame or a list of card specifications. In JavaScript (axis formatters) only the quoted
#' label `"Historical"` is replaced. Longer strings ("Historical mean") keep their wording: in the window scope the
#' Historical row is the same-window outcome of the historical years.
#' @param x An htmlwidget, a data frame or a list.
#' @param reference_label Display label of the Historical row.
#' @param text Named wording replacements; empty to change the Historical label only.
#' @noRd
.step2_window_relabel <- function(x, reference_label, text = .STEP2_WINDOW_TEXT) {
  swap <- function(v) {
    fixed <- !is.na(v) & v %in% names(text)
    v[fixed] <- unname(text[v[fixed]])
    v[!is.na(v) & v == "Historical"] <- reference_label
    v
  }
  # In JavaScript (axis formatters carry their category labels as JSON), only the quoted label itself.
  swap_js <- function(v) {
    a <- attributes(v)
    out <- gsub('"Historical"', paste0('"', reference_label, '"'), v, fixed = TRUE)
    attributes(out) <- a
    out
  }
  walk <- function(node) {
    if (is.character(node)) {
      return(if (inherits(node, "JS_EVAL")) swap_js(node) else {
        a <- attributes(node)
        out <- swap(node)
        attributes(out) <- a
        out
      })
    }
    if (is.factor(node)) {
      levels(node) <- swap(levels(node))
      return(node)
    }
    if (is.list(node) && !is.environment(node)) {
      for (i in seq_along(node)) {
        if (!is.null(node[[i]])) node[[i]] <- walk(node[[i]])
      }
    }
    node
  }
  if (inherits(x, "htmlwidget")) {
    x$x <- walk(x$x)
    return(x)
  }
  walk(x)
}

#' Where the forecast members fall on the Historical same-window exceedance curve
#'
#' The Historical curve gives each outcome level its adverse exceedance probability among the reference years
#' (Hazen positions, `(rank - 0.5) / n`, as the exceedance chart). The median member and the 10th and 90th
#' percentiles of the members are read off that curve by linear interpolation; levels beyond the most or least
#' adverse reference year take the end probability.
#' @param reference,members Numeric: reference-year and member outcomes on the chart's scale.
#' @param adverse_tail `"high"` when higher values are worse, else `"low"`.
#' @param band_q Quantile pair of the member band (the Results ensemble-spread control), or `NULL` for none.
#' @return `NULL` without values, else a list: `value` and `p` (each `lo`, `mid`, `hi` for the lower band
#'   quantile, median and upper band quantile of the members; `lo` and `hi` are `NA` without a band), `p_min` and
#'   `p_max` (the end probabilities).
#' @noRd
.step2_window_exceedance_position <- function(reference, members, adverse_tail = "low",
                                              band_q = c(lo = 0.1, hi = 0.9)) {
  reference <- sort(reference[is.finite(reference)], decreasing = identical(adverse_tail, "high"))
  members <- members[is.finite(members)]
  n <- length(reference)
  if (n < 2L || !length(members)) return(NULL)
  probs <- (seq_len(n) - 0.5) / n
  q <- if (is.null(band_q)) c(NA_real_, 0.5, NA_real_) else c(band_q[["lo"]], 0.5, band_q[["hi"]])
  value <- stats::setNames(rep(NA_real_, 3L), c("lo", "mid", "hi"))
  value[!is.na(q)] <- stats::quantile(members, q[!is.na(q)], names = FALSE)
  p <- rep(NA_real_, 3L)
  p[!is.na(q)] <- stats::approx(reference, probs, xout = value[!is.na(q)], rule = 2, ties = mean)$y
  list(value = value, p = stats::setNames(p, names(value)), p_min = probs[[1L]], p_max = probs[[n]])
}

#' Forecast overlay on the Historical exceedance curve of the window scope
#'
#' Adds a vertical line at the exceedance probability of the median member and, with a member band, a shaded band
#' between those of the band's members (`.step2_window_exceedance_position()`). The probability axis of the chart ends
#' at `x_max`; a position past it is drawn at the edge and labelled as less adverse than the median year.
#' @param e Exceedance chart (`echart_exceedance()`).
#' @param pos Result of `.step2_window_exceedance_position()`.
#' @param label,colour,line_type,name Label prefix, colour and line type of the line; series name (with `__`, so the
#'   tooltip leaves it out).
#' @param label_offset Pixel offset of the label, to stack the labels of two lines.
#' @noRd
.step2_window_exceedance_overlay <- function(e, pos, x_max = 0.55, label = "Forecast median",
                                             colour = .wise_forecast, line_type = "solid", name = "forecast__position",
                                             label_offset = c(0, 0)) {
  if (is.null(pos) || !inherits(e, "htmlwidget")) return(e)
  clip <- function(p) min(max(p, 1e-6), x_max)
  rp <- function(p) {
    if (p > 0.5) return("better than the median year")
    paste0("about 1 in ", format(round(1 / p, 1), nsmall = 1))
  }
  mid <- clip(pos$p[["mid"]])
  has_band <- all(is.finite(pos$p[c("lo", "hi")]))
  band <- if (has_band) sort(c(clip(pos$p[["lo"]]), clip(pos$p[["hi"]])))
  overlay <- list(
    name = name, type = "line", data = list(), silent = TRUE, z = 0,
    markArea = if (has_band) list(
      silent = TRUE,
      itemStyle = list(color = colour, opacity = 0.12),
      data = list(list(list(xAxis = band[[1L]]), list(xAxis = band[[2L]])))
    ),
    # With other curves on the chart, the dot shows which curve the line was read from.
    markPoint = list(
      symbol = "circle", symbolSize = 10, silent = TRUE, animation = FALSE,
      itemStyle = list(color = colour, borderColor = "#FFFFFF", borderWidth = 1.5),
      label = list(show = FALSE),
      data = list(list(coord = list(mid, unname(pos$value[["mid"]]))))
    ),
    markLine = list(
      symbol = "none", silent = TRUE, animation = FALSE,
      data = list(list(
        xAxis = mid,
        lineStyle = list(color = colour, type = line_type, width = 2),
        label = list(
          show = TRUE, position = "end", align = "right", offset = label_offset,
          color = colour, fontSize = 11, fontWeight = "bold",
          formatter = paste0(label, ": ", rp(pos$p[["mid"]]))
        )
      ))
    )
  )
  # The labels of the curves ending left of the line stay readable where it passes.
  e$x$opts$series <- lapply(e$x$opts$series, function(s) {
    if (!is.null(s$endLabel)) s$endLabel$backgroundColor <- "#FFFFFF"
    s
  })
  e$x$opts$series <- c(e$x$opts$series, list(overlay))
  e
}

#' Adverse-level dots of the window scope: the Historical levels and one Forecast row
#'
#' Keeps the Historical rows of `step2_adverse_dot_view()` and adds a row "Forecast" below them: the median member
#' with a band between two member quantiles, on the chart's scale.
#' @param dot Result of `step2_adverse_dot_view()`.
#' @param members Member outcomes on the chart's scale.
#' @param label Member series label.
#' @param band_q Quantile pair of the member band (the Results ensemble-spread control), or `NULL` for none.
#' @noRd
.step2_window_adverse_dots <- function(dot, members, label, band_q = c(lo = 0.1, hi = 0.9)) {
  if (is.null(dot) || !nrow(dot)) return(dot)
  hist <- dot[dot$is_historical, , drop = FALSE]
  members <- members[is.finite(members)]
  if (!nrow(hist) || !length(members)) return(hist)
  q <- if (is.null(band_q)) {
    c(NA_real_, stats::median(members), NA_real_)
  } else {
    stats::quantile(members, c(band_q[["lo"]], 0.5, band_q[["hi"]]), names = FALSE)
  }
  levels_hist <- levels(droplevels(hist$rp_label))
  hist$rp_label <- factor(as.character(hist$rp_label), levels = c("Forecast", levels_hist))
  fc <- hist[1L, , drop = FALSE]
  fc$scenario <- label
  fc$is_historical <- FALSE
  fc$rp_label <- factor("Forecast", levels = levels(hist$rp_label))
  fc$value <- q[[2L]]
  fc$intermod_lo <- q[[1L]]
  fc$intermod_hi <- q[[3L]]
  if ("ssp_key" %in% names(fc)) fc$ssp_key <- "Forecast"
  if ("yr_lbl" %in% names(fc)) fc$yr_lbl <- label
  out <- rbind(hist, fc)
  for (col in c("value", "intermod_lo", "intermod_hi")) out[[col]] <- unname(as.numeric(out[[col]]))
  out$intermod_lo[out$is_historical] <- NA_real_
  out$intermod_hi[out$is_historical] <- NA_real_
  out
}

#' Name the annual Historical series once the target-month one sits next to it
#'
#' @param x An htmlwidget, a data frame or a list.
#' @param level Level view. In a difference view the zero line is the baseline of both Historical series, so its
#'   label stays general.
#' @noRd
.step2_annual_relabel <- function(x, level = TRUE) {
  text <- c(
    "Historical | Baseline" = paste(.STEP2_ANNUAL_LABEL, "| Baseline"),
    "Historical\nBaseline" = paste0(.STEP2_ANNUAL_LABEL, "\nBaseline")
  )
  if (isTRUE(level)) text <- c(text, "Historical mean" = paste(.STEP2_ANNUAL_LABEL, "mean"))
  .step2_window_relabel(x, .STEP2_ANNUAL_LABEL, text = text)
}

#' Exceedance curve rows of the Historical target-month outcome
#'
#' The rows of the exceedance chart (`echart_exceedance()`) for the one Historical sample of the window: values in
#' the adverse order, Hazen positions `(rank - 0.5) / n`, coefficient SDs. Unlike the annual curves, the whole
#' curve is kept, so a forecast less adverse than the median year still falls on it.
#' @param tbl Window Historical table (`step2_window_series()$historical`, contrast SDs applied).
#' @param hist_ref Value subtracted (deviation views).
#' @param adverse_tail `"high"` when higher values are worse, else `"low"`.
#' @noRd
.step2_window_exceedance_curves <- function(tbl, hist_ref = 0, adverse_tail = "low") {
  mm <- by_model_matrix(tbl)
  if (is.null(mm)) return(NULL)
  v <- as.numeric(mm$vals[1L, ])
  sd <- as.numeric(mm$sds[1L, ])
  ok <- is.finite(v)
  v <- v[ok]
  sd <- sd[ok]
  if (length(v) < 2L) return(NULL)
  ord <- order(v, decreasing = identical(adverse_tail, "high"))
  tibble::tibble(
    scenario = "Historical", model_id = "Historical", rank = seq_along(ord),
    welfare_val = v[ord] - hist_ref, coef_sd = sd[ord],
    exceed_prob = (seq_along(ord) - 0.5) / length(ord), is_historical = TRUE
  )
}

#' The forecast-window views of one Results state
#'
#' The Historical target-month sample and the forecast members (`step2_window_series()`) through the annual view
#' builders, with their own deviation reference (the Historical mean or median of the same months): distribution
#' curves, headline bands, return-period table, adverse dots with the Forecast row, variance (member spread as the
#' across-member component), the Historical exceedance curve with the forecast position, and the cards.
#' @param w Result of `step2_window_series()`.
#' @param scenario The forecast scenario entry (skill, training months, weather support for the cards).
#' @param placement Result of `step2_window_placement()` (level view cards), or `NULL`.
#' @param hist_sim,metadata As for `step2_headline_cards()`.
#' @param band_adverse,band_exceedance Member band of the adverse-level and exceedance views (quantile pairs, `NULL`
#'   for none): the Results ensemble-spread controls, shared with the climate-model spread of the scenarios.
#' @noRd
step2_window_views <- function(w, method, so, deviation = "none", scenario = NULL, placement = NULL,
                               hist_sim = NULL, metadata = NULL, band_adverse = c(lo = 0.1, hi = 0.9),
                               band_exceedance = band_adverse) {
  if (is.null(w) || is.null(w$historical) || is.null(w$members)) return(NULL)
  ref <- step2_hist_ref(w$historical, deviation)
  f_ref <- step2_hist_f_ref(w$historical, deviation)
  series <- stats::setNames(
    list(step2_contrast_sd(w$historical, f_ref), step2_contrast_sd(w$members, f_ref)),
    c("Historical", w$label)
  )
  central <- c(lo = 0.5, hi = 0.5)
  bands <- step2_pointrange_bands(series, central, ref)
  curves <- step2_timeseries_curves(series, ref)
  threshold <- step2_threshold_table(
    series, bq_coef = resolve_band_q("p10_p90"), bq_ens = central, hist_ref = ref, method = method, so = so
  )
  dots <- .step2_window_adverse_dots(
    step2_adverse_dot_view(threshold, method, so, ensemble_none = TRUE), w$members$value - ref, w$label, band_q = band_adverse
  )
  variance <- step2_variance_breakdown(series)
  if (!is.null(variance) && nrow(variance)) {
    # The member spread is an across-member spread, as across climate models; one window has no year-to-year spread.
    fc <- .step2_is_window_forecast(variance$scenario)
    variance$var_across[fc] <- variance$var_within[fc]
    variance$var_within[fc] <- 0
  }
  tail <- metric_metadata(method, so)$adverse_tail %||% "low"
  cards <- step2_headline_cards(
    bands = step2_headline_bands(bands, series, ref), hist_sim = hist_sim,
    saved_scenarios = stats::setNames(list(scenario), w$label), method = method, timeseries_curves = curves,
    deviation = deviation, forecast_placement = placement, metadata = metadata
  )
  list(
    ref = ref, series = series, curves = curves, threshold = threshold, dots = dots, variance = variance,
    exceedance = .step2_window_exceedance_curves(series[["Historical"]], ref, tail),
    position = .step2_window_exceedance_position(
      w$historical$value - ref, w$members$value - ref, tail, band_q = band_exceedance
    ),
    cards = .step2_window_relabel(cards, w$reference_label),
    n_reference = nrow(w$historical)
  )
}

#' Rows of one merged chart: the annual rows and the rows of the forecast target months
#'
#' The Historical rows of `window` become the series `reference_label`, next to the annual `"Historical"`. Each
#' group keeps its own deviation reference, so in a difference view both Historical series sit at zero. Rows follow
#' `.step2_scenario_order()`; a return-period row exists once, with `"Forecast"` at the bottom.
#' @param annual,window Rows with a `scenario` column; `window` from `step2_window_views()`.
#' @param reference_label Display label of the Historical series of the target months.
#' @noRd
.step2_window_merge <- function(annual, window, reference_label) {
  if (is.null(window) || !nrow(window)) return(annual)
  window$scenario <- as.character(window$scenario)
  hist <- window$scenario == "Historical"
  window$scenario[hist] <- reference_label
  if ("is_historical" %in% names(window)) window$is_historical[hist] <- FALSE
  if (!is.null(annual)) annual$scenario <- as.character(annual$scenario)
  rp_levels <- if ("rp_label" %in% names(window)) {
    union(intersect("Forecast", levels(window$rp_label)), union(levels(annual$rp_label), levels(window$rp_label)))
  }
  out <- dplyr::bind_rows(annual, window)
  if (!is.null(rp_levels)) out$rp_label <- droplevels(factor(as.character(out$rp_label), levels = rp_levels))
  out[order(match(out$scenario, .step2_scenario_order(out$scenario))), , drop = FALSE]
}

#' The forecast-window views of the Step 3 Results: baseline and policy for the target months
#'
#' The Step 2 window samples (`step2_window_series()`) of the baseline and of the policy arm of one forecast
#' scenario, in the layout of the Step 3 builders (a `source` column, Baseline and Policy): distribution rows, the
#' adverse-level dumbbells with one Forecast row (median member and member band of each arm), the no-policy
#' Historical target-month exceedance curve with the median member of each arm placed on it, the
#' return-period rows and the policy-effect cards. The deviation reference is the baseline Historical mean or median
#' of the same months, as the annual group uses the baseline Historical.
#' @param wb,wp `step2_window_series()` of the baseline and of the policy arm (same members and years).
#' @param band_adverse,band_exceedance Member band (quantile pair, `NULL` for none): the ensemble-spread controls.
#' @noRd
step3_window_views <- function(wb, wp, method, so, deviation = "none", band_adverse = NULL,
                               band_exceedance = NULL) {
  if (is.null(wb) || is.null(wp) || !identical(wb$member_ids, wp$member_ids) ||
    !identical(wb$historical$sim_year, wp$historical$sim_year)) {
    return(NULL)
  }
  ref <- step2_hist_ref(wb$historical, deviation)
  tail <- metric_metadata(method, so)$adverse_tail %||% "low"
  central <- c(lo = 0.5, hi = 0.5)
  arm <- function(w, source) {
    series <- stats::setNames(list(w$historical, w$members), c("Historical", w$label))
    threshold <- step2_threshold_table(
      series, bq_coef = resolve_band_q("p10_p90"), bq_ens = central, hist_ref = ref, method = method, so = so
    )
    curves <- step2_timeseries_curves(series, ref)
    if (!is.null(curves)) curves$source <- source
    if (!is.null(threshold) && nrow(threshold)) threshold$source <- source
    dots <- .step2_window_adverse_dots(
      step2_adverse_dot_view(threshold, method, so, ensemble_none = TRUE), w$members$value - ref, w$label,
      band_q = band_adverse
    )
    list(curves = curves, threshold = threshold, dots = dots)
  }
  b <- arm(wb, "Baseline")
  p <- arm(wp, "Policy")
  dots <- NULL
  if (!is.null(b$dots) && nrow(b$dots) && !is.null(p$dots) && nrow(p$dots)) {
    key <- function(d) paste(d$scenario, as.character(d$rp_label))
    idx <- match(key(b$dots), key(p$dots))
    dots <- tibble::tibble(
      scenario = b$dots$scenario, is_historical = b$dots$is_historical, rp_label = b$dots$rp_label,
      baseline_val = b$dots$value, policy_val = p$dots$value[idx],
      base_lo = b$dots$intermod_lo, base_hi = b$dots$intermod_hi,
      policy_lo = p$dots$intermod_lo[idx], policy_hi = p$dots$intermod_hi[idx]
    )
  }
  # Both arms' members are placed on the baseline Historical curve: the policy line shows which return period of
  # the no-policy historical years the forecast with the policy lines up with.
  ref_vals <- wb$historical$value - ref
  pos <- list(
    baseline = .step2_window_exceedance_position(ref_vals, wb$members$value - ref, tail, band_q = band_exceedance),
    policy = .step2_window_exceedance_position(ref_vals, wp$members$value - ref, tail, band_q = band_exceedance)
  )
  high <- identical(tail, "high")
  threshold_10 <- stats::quantile(wb$historical$value, if (high) 0.9 else 0.1, names = FALSE)
  worse <- function(x) mean(if (high) x >= threshold_10 else x <= threshold_10, na.rm = TRUE)
  effect <- list(
    member_median = stats::median(wp$members$value - wb$members$value, na.rm = TRUE),
    reference_median = stats::median(wp$historical$value - wb$historical$value, na.rm = TRUE),
    share_worse_baseline = worse(wb$members$value),
    share_worse_policy = worse(wp$members$value),
    n_members = nrow(wb$members), n_reference = nrow(wb$historical)
  )
  list(
    ref = ref, curves = dplyr::bind_rows(b$curves, p$curves),
    threshold = dplyr::bind_rows(b$threshold, p$threshold), dots = dots,
    exceedance = dplyr::mutate(.step2_window_exceedance_curves(wb$historical, ref, tail), source = "Baseline"),
    position = pos, effect = effect,
    n_reference = nrow(wb$historical), label = wb$label, reference_label = wb$reference_label,
    months_label = wb$months_label
  )
}

#' Headline cards of the Step 3 forecast window
#' @param views Result of `step3_window_views()`.
#' @param metadata Metric metadata (`metric_metadata()`), for the value format.
#' @param shock `shock_forecast` of the policy scenario, or `NULL` for a regular policy.
#' @noRd
.step3_window_cards <- function(views, metadata, shock = NULL) {
  e <- views$effect
  fmt <- function(x) format_metric_value(x, metadata, change = TRUE, digits = 3L)
  pct <- function(x) paste0(formatC(100 * x, format = "f", digits = 0), "%")
  card <- function(label, value, line1, line2, info) {
    list(
      label = label, value = value, note = paste(line1, line2, sep = " \u00b7 "),
      note_html = shiny::tagList(shiny::tags$div(line1), shiny::tags$div(style = "font-weight: 600;", line2)),
      info = info
    )
  }
  info <- paste(
    "Each member and each historical year is evaluated with and without the policy over the target months only.",
    if (is.null(shock)) {
      "The policy acts identically in every month of the window."
    } else {
      "The transfer pays where the weather of the window passes the trigger, once per window."
    },
    "Shares of members are indicators, not probabilities: the member spread is not calibrated and skill is not",
    "established."
  )
  cards <- list(
    card("Policy effect, forecast", fmt(e$member_median), "Median member: policy minus baseline",
      views$label, info),
    card("Policy effect, same months", fmt(e$reference_median), "Median historical year: policy minus baseline",
      views$reference_label, info),
    card("Members worse than the historical 1-in-10", paste(pct(e$share_worse_baseline), "\u2192",
      pct(e$share_worse_policy)), "Without and with the policy, at the baseline level",
      paste0(e$n_members, " members, ", e$n_reference, " historical years"), info)
  )
  if (is.null(shock)) return(cards)
  s <- sp_shock_window_summary(shock)
  money <- function(x) fmt_num(x, digits = 0, prefix = .sp_currency_prefix(shock$currency), na = "Not available")
  c(cards, list(card(
    "Population in triggered locations", pct(s$exposed_member),
    paste0("Mean member, against ", pct(s$exposed_reference), " in a historical year; ", pct(s$member_share),
      " of members and ", pct(s$reference_share), " of years have payments"),
    paste0("Cost of the window: ", money(s$cost_median), " (", money(s$cost_range[[1L]]), " to ",
      money(s$cost_range[[2L]]), ")"),
    paste(
      "The share of the population in locations that pass the trigger, set on the same months of the historical",
      "years. A member or year has payments when any location passes it, which is common with many locations.",
      "The cost is the median member and the range across members: what the window would cost if that member's",
      "weather happened, not an expected or annual cost. Shares of members are indicators, not probabilities."
    )
  )))
}

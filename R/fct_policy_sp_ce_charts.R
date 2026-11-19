# Cost-effectiveness tab: cards and charts ----
# Pure builders over `sp_cost_effectiveness()` (and the shock cost and reach
# summaries). Internally the weather basis is "Average year" or "1-in-20 year";
# on screen the second is "Adverse 1-in-20 year", the wording of Results (the
# baseline-anchored adverse weather year). The "95th percentile annual cost" of
# the shock summary is a different quantity and is named as such.

.sp_ce_basis_label <- function(basis) {
  ifelse(basis == "1-in-20 year", "Adverse 1-in-20 year", basis)
}

.sp_ce_short_label <- function(measure) {
  if (grepl("^Cost per person", measure)) {
    "Cost per person-year lifted"
  } else if (grepl("^Poverty gap", measure)) {
    "Poverty gap closed per $1"
  } else {
    measure
  }
}

# Formatter for a ratio: money for a cost per person, a plain number otherwise.
.sp_ce_ratio_fmt <- function(res, currency = "PPP") {
  prefix <- .sp_currency_prefix(currency)
  if (grepl("^Cost per person", res$measure[[1L]])) {
    function(x) fmt_compact(x, prefix = prefix, small_digits = 2, na = "Not available")
  } else {
    function(x) fmt_num(x, digits = 2, na = "Not available")
  }
}

#' Scenario the cards describe
#'
#' @param res Result of `sp_cost_effectiveness()`.
#' @param focus Preferred scenario label (the Results focus scenario).
#' @return One scenario label, or `NULL` without rows.
#' @keywords internal
.sp_ce_focus <- function(res, focus = NULL) {
  if (!is.data.frame(res) || !nrow(res)) {
    return(NULL)
  }
  if (!is.null(focus) && length(focus) == 1L && focus %in% res$scenario) focus else res$scenario[[1L]]
}

#' Headline cards of the cost-effectiveness tab
#'
#' The ratio in an average and in an adverse 1-in-20 year, and the annual cost,
#' for one scenario. A ratio that cannot be read shows its reason in the note.
#'
#' @param res Result of `sp_cost_effectiveness()`.
#' @param currency `"PPP"` or `"LCU"`.
#' @param scenario Scenario label (see `.sp_ce_focus()`).
#' @return A list of cards for `headline_cards_ui()`, or `NULL`.
#' @keywords internal
.sp_ce_cards <- function(res, currency = "PPP", scenario = NULL) {
  sc <- .sp_ce_focus(res, scenario)
  if (is.null(sc)) {
    return(NULL)
  }
  r <- res[res$scenario == sc, , drop = FALSE]
  per_person <- grepl("^Cost per person", r$measure[[1L]])
  prefix <- .sp_currency_prefix(currency)
  fmt <- .sp_ce_ratio_fmt(r, currency)
  money <- function(x) fmt_compact(x, prefix = prefix, na = "Not available")
  short <- .sp_ce_short_label(r$measure[[1L]])
  ratio_card <- function(basis, label) {
    row <- r[r$basis == basis, , drop = FALSE]
    if (!nrow(row)) {
      return(NULL)
    }
    ok <- identical(row$status[[1L]], "ok")
    note <- if (ok) {
      paste(c(
        if (per_person) {
          paste("Net people lifted:", fmt_compact(row$amount))
        } else {
          paste("Annual value of the change:", money(row$amount))
        },
        if (identical(row$interval, "95% interval")) {
          paste0("95% interval ", fmt(row$lo), " to ", fmt(row$hi))
        } else if (identical(row$interval, "not bounded")) {
          "Interval reaches zero effect (not bounded)"
        }
      ), collapse = ". ")
    } else {
      row$note
    }
    list(
      label = paste0(short, ", ", label),
      value = if (ok) {
        fmt(row$value)
      } else if (identical(row$status[[1L]], "unavailable")) {
        "Not available"
      } else {
        "Not applicable"
      },
      note = note
    )
  }
  avg <- r[r$basis == "Average year", , drop = FALSE]
  tail <- r[r$basis == "1-in-20 year", , drop = FALSE]
  cost_card <- if (nrow(avg) && is.finite(avg$cost[[1L]])) {
    tail_cost <- if (nrow(tail)) tail$cost[[1L]] else NA_real_
    list(
      label = "Annual cost, average year",
      value = money(avg$cost[[1L]]),
      note = if (is.finite(tail_cost) && abs(tail_cost - avg$cost[[1L]]) > 1e-6 * max(1, abs(avg$cost[[1L]]))) {
        paste("Adverse 1-in-20 year:", money(tail_cost))
      } else {
        "Same in every weather year"
      }
    )
  }
  # A metric without a per-dollar reading gets the cost card only; the tab says why.
  has_ratio <- grepl("^(Cost per person|Poverty gap)", r$measure[[1L]])
  Filter(Negate(is.null), list(
    if (has_ratio) ratio_card("Average year", "average year"),
    if (has_ratio) ratio_card("1-in-20 year", "adverse 1-in-20 year"),
    cost_card
  ))
}

# Plottable rows: finite ratios only, one per scenario and basis.
.sp_ce_plot_rows <- function(res, currency = "PPP") {
  if (!is.data.frame(res) || !nrow(res)) {
    return(data.frame())
  }
  fmt <- .sp_ce_ratio_fmt(res, currency)
  ok <- res$status == "ok" & is.finite(res$value)
  r <- res[ok, , drop = FALSE]
  if (!nrow(r)) {
    return(data.frame())
  }
  basis <- .sp_ce_basis_label(r$basis)
  bounded <- r$interval == "95% interval" & is.finite(r$lo) & is.finite(r$hi)
  data.frame(
    scenario = r$scenario, basis = basis,
    label = paste(r$scenario, basis, sep = " \u00b7 "),
    value = r$value, lo = ifelse(bounded, r$lo, NA_real_),
    hi = ifelse(bounded, r$hi, NA_real_),
    not_bounded = r$interval == "not bounded",
    tip = paste0(
      "<b>", r$scenario, " \u00b7 ", basis, "</b><br/>", fmt(r$value),
      ifelse(bounded, paste0("<br/>95% interval ", fmt(r$lo), " to ", fmt(r$hi)),
        ifelse(r$interval == "not bounded",
          "<br/>Interval reaches zero effect (not bounded)",
          ifelse(r$basis == "1-in-20 year", "<br/>No interval for the adverse year", "")
        )
      )
    ),
    stringsAsFactors = FALSE
  )
}

# Rows with no readable ratio, as one caption each (scenario, basis, reason).
.sp_ce_unshown <- function(res) {
  if (!is.data.frame(res) || !nrow(res)) {
    return(character())
  }
  r <- res[res$status != "ok" | !is.finite(res$value), , drop = FALSE]
  if (!nrow(r)) {
    return(character())
  }
  unique(paste0(r$scenario, ", ", tolower(.sp_ce_basis_label(r$basis)), ": ", r$note))
}

#' What the transfer buys: ratio per scenario and weather basis, with intervals
#'
#' A dot per scenario and weather basis, with a 95 percent interval from the
#' coefficient uncertainty for the average year. A cost per person lifted whose
#' interval reaches zero effect is a hollow dot without a whisker. Lower is
#' better for a cost per person; higher is better for a ratio per $1.
#'
#' @param res Result of `sp_cost_effectiveness()`.
#' @param currency `"PPP"` or `"LCU"`.
#' @return An `echarts4r` widget.
#' @keywords internal
echart_sp_ce_ratio <- function(res, currency = "PPP") {
  rows <- .sp_ce_plot_rows(res, currency)
  if (!nrow(rows)) {
    return(echart_blank("No cost-effectiveness ratio to show.", height = "160px"))
  }
  per_person <- grepl("^Cost per person", res$measure[[1L]])
  prefix <- .sp_currency_prefix(currency)
  labels <- rows$label
  n <- length(labels)
  basis_colour <- c("Average year" = .wise_blue, "Adverse 1-in-20 year" = .wise_policy)
  e <- echarts4r::e_charts(
    data.frame(label = rep_len(labels, max(2L, n)), y = 0), label,
    reorder = FALSE, height = paste0(100 + 40 * n, "px")
  )
  has_whisker <- is.finite(rows$lo) & is.finite(rows$hi)
  whisker <- list(
    name = "95% interval", type = "custom", silent = TRUE, z = 1,
    tooltip = list(show = FALSE), legendHoverLink = FALSE,
    renderItem = htmlwidgets::JS(sprintf(
      "function(params, api) {
        var y = api.value(2), a = api.coord([api.value(0), y]), b = api.coord([api.value(1), y]), h = 6;
        var st = {stroke: '%s', lineWidth: 2};
        return {type: 'group', children: [
          {type: 'line', shape: {x1: a[0], y1: a[1], x2: b[0], y2: b[1]}, style: st},
          {type: 'line', shape: {x1: a[0], y1: a[1] - h, x2: a[0], y2: a[1] + h}, style: st},
          {type: 'line', shape: {x1: b[0], y1: b[1] - h, x2: b[0], y2: b[1] + h}, style: st}
        ]};
      }", .wise_support
    )),
    encode = list(x = c(0, 1), y = 2),
    data = lapply(which(has_whisker), function(i) list(rows$lo[[i]], rows$hi[[i]], i - 1L))
  )
  dots <- lapply(names(basis_colour)[names(basis_colour) %in% rows$basis], function(b) {
    idx <- which(rows$basis == b)
    list(
      name = if (b == "Average year") b else paste(b, "(no interval)"),
      type = "scatter", symbolSize = 12, z = 3,
      itemStyle = list(color = unname(basis_colour[[b]])),
      data = lapply(idx, function(i) {
        item <- list(value = list(rows$value[[i]], rows$label[[i]]), tip = rows$tip[[i]])
        if (isTRUE(rows$not_bounded[[i]])) {
          item$itemStyle <- list(
            color = "#FFFFFF", borderColor = unname(basis_colour[[b]]), borderWidth = 2
          )
        }
        item
      })
    )
  })
  e$x$opts$series <- c(if (any(has_whisker)) list(whisker), dots)
  e$x$opts$yAxis <- list(
    type = "category", data = labels, inverse = TRUE,
    axisLabel = wise_eaxis_label(width = 210, overflow = "break"),
    axisLine = list(lineStyle = list(color = .wise_grid)),
    axisTick = list(show = FALSE), splitLine = wise_esplit_line()
  )
  # A cost per person has an upper bound that explodes as the effect nears
  # zero: a log axis when the values span more than a decade (it shows no ticks
  # on a narrower range). A gain per $1 can have a negative lower bound.
  span <- range(c(rows$value, rows$lo, rows$hi), finite = TRUE)
  wide <- per_person && span[[1L]] > 0 && span[[2L]] / span[[1L]] > 10
  e$x$opts$xAxis <- list(
    type = if (wide) "log" else "value", scale = !wide,
    axisLabel = wise_eaxis_label(formatter = paste0(if (per_person) prefix else "", "{value}")),
    splitLine = wise_esplit_line()
  )
  e$x$opts$legend <- modifyList(
    list(top = 0, left = 0, orient = "horizontal", data = vapply(dots, `[[`, "", "name")),
    wise_elegend_style()
  )
  e$x$opts$tooltip <- list(
    trigger = "item",
    formatter = htmlwidgets::JS("function(p) { return p.data && p.data.tip ? p.data.tip : ''; }")
  )
  e$x$opts$grid <- list(containLabel = TRUE, left = 8, right = 24, top = 36, bottom = 10)
  wise_echart_theme(e)
}

# Grouped bars of money per scenario. `measures` is a named list of numeric
# vectors; labels abbreviate to K, M and B.
.diag_grouped_money_chart <- function(scenarios, measures, colours, prefix = "$",
                                      height = "320px", bottom = 12, stack = FALSE,
                                      y_label = paste0("Annual cost (", trimws(prefix), ")")) {
  keep <- vapply(measures, function(x) any(is.finite(x)), logical(1))
  if (!length(scenarios) || !any(keep)) {
    return(echart_blank("Not available", height = height))
  }
  measures <- measures[keep]
  colours <- colours[keep]
  scenarios <- as.character(scenarios)
  abbrev <- sprintf(
    "function(v) { if (typeof v !== 'number') return '';
      var a = Math.abs(v), t = function(x) { return String(parseFloat(x.toFixed(1))); };
      var s = a >= 1e9 ? t(v / 1e9) + 'B' : a >= 1e6 ? t(v / 1e6) + 'M' : a >= 1e3 ? t(v / 1e3) + 'K' : t(v);
      return %s + s; }",
    jsonlite::toJSON(prefix, auto_unbox = TRUE)
  )
  e <- echarts4r::e_charts(
    data.frame(scenario = scenarios, y = 0), scenario, reorder = FALSE, height = height
  )
  e$x$opts$series <- lapply(seq_along(measures), function(i) {
    list(
      name = names(measures)[[i]], type = "bar", barMaxWidth = 38,
      stack = if (stack) "cost",
      data = lapply(measures[[i]], function(v) {
        list(value = if (is.finite(v)) v else NULL, itemStyle = list(color = unname(colours[[i]])))
      }),
      label = list(
        show = !stack, position = "top", color = .wise_charcoal, fontSize = 12,
        formatter = htmlwidgets::JS(sprintf("function(p) { return (%s)(p.value); }", abbrev))
      )
    )
  })
  e$x$opts$xAxis <- list(
    type = "category", data = as.list(scenarios),
    axisLabel = wise_eaxis_label(interval = 0L, width = 240, overflow = "break"),
    axisLine = list(lineStyle = list(color = .wise_grid)),
    axisTick = list(alignWithLabel = TRUE), splitLine = wise_esplit_line(show = FALSE)
  )
  e$x$opts$yAxis <- c(
    list(
      type = "value", min = 0,
      axisLabel = wise_eaxis_label(formatter = htmlwidgets::JS(sprintf("function(v) { return (%s)(v); }", abbrev))),
      splitLine = wise_esplit_line()
    ),
    .diag_y_title(y_label, gap = 68)
  )
  e$x$opts$legend <- modifyList(
    list(top = 0, left = "center", orient = "horizontal"), wise_elegend_style()
  )
  e$x$opts$tooltip <- list(
    trigger = "axis", axisPointer = list(type = "shadow"),
    valueFormatter = htmlwidgets::JS(sprintf(
      "function(v) { return typeof v === 'number' ? %s + v.toLocaleString(undefined, {maximumFractionDigits: 0}) : 'Not available'; }",
      jsonlite::toJSON(prefix, auto_unbox = TRUE)
    ))
  )
  e$x$opts$color <- unname(colours)
  e$x$opts$grid <- list(
    containLabel = TRUE, left = if (is.null(y_label)) 8 else 40, right = 14, top = 52, bottom = bottom
  )
  wise_echart_theme(e)
}

#' What the transfer costs: where the average-year cost goes
#'
#' Annual cost in an average year, split into transfers to the poor, leakage to
#' the non-poor and administration. Without a leakage share (no poverty line)
#' the transfer is one block. A regular program costs the same in every scenario
#' and gets one bar; the adverse-year cost is on the headline card.
#'
#' @param res Result of `sp_cost_effectiveness()`.
#' @param currency `"PPP"` or `"LCU"`.
#' @param admin Administration share of cost.
#' @param leakage Share of transfer spending that reaches the non-poor, or `NA`.
#'   For a shock program this is the share when payments are made.
#' @return An `echarts4r` widget.
#' @keywords internal
echart_sp_ce_cost <- function(res, currency = "PPP", admin = 0, leakage = NA_real_) {
  if (!is.data.frame(res) || !nrow(res)) {
    return(echart_blank("No cost to show.", height = "160px"))
  }
  scen <- unique(res$scenario)
  avg <- vapply(scen, function(s) {
    v <- res$cost[res$scenario == s & res$basis == "Average year"]
    if (length(v)) v[[1L]] else NA_real_
  }, numeric(1), USE.NAMES = FALSE)
  if (length(avg) > 1L && all(abs(avg - avg[[1L]]) <= 1e-6 * max(1, abs(avg[[1L]])), na.rm = TRUE)) {
    scen <- "Every scenario"
    avg <- avg[[1L]]
  }
  admin <- if (is.finite(admin)) admin else 0
  transfer <- avg * (1 - admin)
  measures <- if (is.finite(leakage)) {
    list(
      "Transfers to the poor" = transfer * (1 - leakage),
      "Leakage to the non-poor" = transfer * leakage,
      "Administration" = avg * admin
    )
  } else {
    list("Transfers" = transfer, "Administration" = avg * admin)
  }
  colours <- c(.wise_blue, if (is.finite(leakage)) .wise_policy, .wise_slate)
  nonzero <- vapply(measures, function(x) any(x > 0, na.rm = TRUE), logical(1))
  measures <- measures[nonzero]
  colours <- colours[nonzero]
  .diag_grouped_money_chart(
    scen, measures, colours, prefix = .sp_currency_prefix(currency), stack = TRUE
  )
}

#' Climate-adjusted cost of a shock program, by scenario
#'
#' Mean annual cost and the 95th percentile of annual cost per scenario. The
#' axis labels carry how often payments are made and the change in mean cost
#' against the reference scenario.
#'
#' @param d Result of `sp_shock_climate_cost()`.
#' @param currency `"PPP"` or `"LCU"`.
#' @return An `echarts4r` widget.
#' @keywords internal
echart_shock_climate_cost <- function(d, currency = "PPP") {
  if (!is.data.frame(d) || !nrow(d)) {
    return(echart_blank("No climate-adjusted cost to show.", height = "160px"))
  }
  change <- ifelse(
    d$is_reference, "Reference",
    ifelse(is.finite(d$cost_change),
      paste0("Cost ", ifelse(d$cost_change > 0, "+", ""), fmt_num(100 * d$cost_change, 0), "% vs historical"),
      "Cost change not available"
    )
  )
  labels <- paste0(
    d$scenario, "\nPayments in ", fmt_num(100 * d$activation_freq, 0, suffix = "%"),
    " of years\n", change
  )
  .diag_grouped_money_chart(
    labels,
    list(
      "Mean annual cost" = d$mean_total_cost,
      "95th percentile annual cost" = d$cost_1_in_20
    ),
    c(.wise_blue, .wise_policy),
    prefix = .sp_currency_prefix(currency), height = "380px", bottom = 12
  )
}

#' Coverage and adequacy of the shock-affected poor, by scenario
#'
#' @param res Result of `sp_shock_reach()`.
#' @return An `echarts4r` widget.
#' @keywords internal
echart_shock_affected_poor <- function(res) {
  if (!is.data.frame(res) || !nrow(res)) {
    return(echart_blank("Needs a positive poverty line.", height = "160px"))
  }
  .diag_grouped_pct_chart(
    res$scenario,
    list(
      "Coverage: poor household-years paid" = res$coverage,
      "Adequacy: payment as a share of loss" = res$adequacy
    ),
    c(.wise_blue, "#009E73"), y_label = "Share"
  )
}

# Step 3 diagnostics charts ----
# echarts4r builders for the Diagnostics tab (reach, targeting accuracy, targeting
# outcomes and the shock-responsive program). They draw precomputed shares only;
# no Shiny dependency. Shares are passed as fractions and shown as percent.

# Colours of the four assignment states (eligible x treated)
.diag_status_colours <- c(
  "Eligible and treated" = "#0072B2",
  "Exclusion error: eligible, not treated" = "#A86400",
  "Inclusion error: not eligible, treated" = "#D55E00",
  "Not eligible, not treated" = "#C9D3DB"
)

.diag_pct_label <- htmlwidgets::JS(
  "function(p) { return (typeof p.value === 'number' ? p.value : p.value[0]).toFixed(1) + '%'; }"
)

# One horizontal bar per row, values in percent. `notes` is an optional
# character vector shown under the value in the tooltip.
.diag_hbar_chart <- function(labels, values, colours, notes = NULL, x_max = 100,
                             empty = "Not available", name = "Share") {
  keep <- is.finite(values)
  if (!any(keep)) {
    return(echart_blank(empty, height = "160px"))
  }
  labels <- as.character(labels)[keep]
  values <- values[keep]
  colours <- rep_len(colours, length(keep))[keep]
  notes <- if (is.null(notes)) rep("", length(keep))[keep] else as.character(notes)[keep]
  n <- length(labels)
  height <- paste0(70 + 46 * n, "px")
  e <- echarts4r::e_charts(
    data.frame(label = labels, value = values), label,
    reorder = FALSE, height = height
  )
  e$x$opts$series <- list(list(
    name = name, type = "bar", barMaxWidth = 26,
    data = lapply(seq_len(n), function(i) {
      list(
        value = values[[i]], note = notes[[i]],
        itemStyle = list(color = unname(colours[[i]]))
      )
    }),
    label = list(
      show = TRUE, position = "right", color = .wise_charcoal, fontSize = 13,
      formatter = .diag_pct_label
    )
  ))
  e$x$opts$yAxis <- list(
    type = "category", data = labels, inverse = TRUE,
    axisLabel = wise_eaxis_label(width = 190, overflow = "break"),
    axisLine = list(lineStyle = list(color = .wise_grid)),
    axisTick = list(show = FALSE)
  )
  e$x$opts$xAxis <- c(
    list(type = "value", min = 0),
    if (!is.null(x_max)) list(max = x_max),
    list(
      axisLabel = wise_eaxis_label(formatter = "{value}%"),
      splitLine = wise_esplit_line()
    )
  )
  e$x$opts$tooltip <- list(
    trigger = "item",
    formatter = htmlwidgets::JS(
      "function(p) { var t = '<b>' + p.name + '</b><br/>' + p.value.toFixed(1) + '%';
        if (p.data && p.data.note) t += '<br/>' + p.data.note; return t; }"
    )
  )
  e$x$opts$grid <- list(containLabel = TRUE, left = 8, right = 56, top = 10, bottom = 10)
  wise_echart_theme(e)
}

#' Population reached by each policy component
#'
#' @param component Result of `policy_component_matrix()`: `component`,
#'   `population_share` (fraction) and `weighted_affected` (people).
#' @return An `echarts4r` widget.
#' @keywords internal
echart_policy_reach <- function(component) {
  if (is.null(component) || !nrow(component)) {
    return(echart_blank("No policy component reaches the population.", height = "160px"))
  }
  both <- component$component == "Touched by both policy types"
  pal <- unname(.wise_cat)
  colours <- ifelse(both, .wise_slate, pal[(seq_len(nrow(component)) - 1L) %% length(pal) + 1L])
  .diag_hbar_chart(
    component$component, 100 * component$population_share, colours,
    notes = paste(fmt_count(component$weighted_affected), "people represented"),
    x_max = NULL, empty = "No policy component reaches the population.",
    name = "Population share"
  )
}

#' Eligibility versus treatment as one stacked bar
#'
#' @param treatment Result of `policy_treatment_matrix()`: `status` and
#'   `weighted_share` (fraction).
#' @return An `echarts4r` widget.
#' @keywords internal
echart_sp_treatment <- function(treatment) {
  if (is.null(treatment) || !nrow(treatment) ||
    !all(is.finite(treatment$weighted_share))) {
    return(echart_blank("No social protection assignment to show.", height = "170px"))
  }
  states <- names(.diag_status_colours)
  states <- states[states %in% treatment$status]
  e <- echarts4r::e_charts(
    data.frame(x = "Population", y = 0), x, reorder = FALSE, height = "170px"
  )
  e$x$opts$series <- lapply(states, function(s) {
    v <- 100 * treatment$weighted_share[match(s, treatment$status)]
    list(
      name = s, type = "bar", stack = "population", barWidth = 46,
      data = list(list(value = v, itemStyle = list(color = unname(.diag_status_colours[[s]])))),
      label = list(
        show = TRUE, position = "inside", fontSize = 12,
        color = if (identical(s, "Not eligible, not treated")) .wise_charcoal else "#FFFFFF",
        formatter = htmlwidgets::JS(
          "function(p) { return p.value >= 4 ? p.value.toFixed(1) + '%' : ''; }"
        )
      )
    )
  })
  e$x$opts$yAxis <- list(type = "category", data = "Population", show = FALSE)
  e$x$opts$xAxis <- list(
    type = "value", min = 0, max = 100,
    axisLabel = wise_eaxis_label(formatter = "{value}%"), splitLine = wise_esplit_line(show = FALSE)
  )
  e$x$opts$legend <- modifyList(
    list(bottom = 0, left = 0, orient = "horizontal", data = states),
    wise_elegend_style()
  )
  e$x$opts$tooltip <- list(
    trigger = "item",
    formatter = htmlwidgets::JS(
      "function(p) { return p.seriesName + '<br/><b>' + p.value.toFixed(1) + '%</b> of the population'; }"
    )
  )
  e$x$opts$color <- unname(.diag_status_colours[states])
  e$x$opts$grid <- list(containLabel = TRUE, left = 8, right = 14, top = 6, bottom = 54)
  wise_echart_theme(e)
}

#' Coverage, leakage and adequacy of the transfer
#'
#' @param metrics `metrics` of `sp_effectiveness()`: `metric`, `value`
#'   (fraction), `kind` and `note`.
#' @return An `echarts4r` widget.
#' @keywords internal
echart_sp_targeting_metrics <- function(metrics) {
  empty <- "Poverty-line measures need a positive poverty line."
  if (is.null(metrics) || !nrow(metrics)) {
    return(echart_blank(empty, height = "160px"))
  }
  rows <- metrics[grepl("^(Coverage|Leakage|Adequacy)", metrics$metric), , drop = FALSE]
  if (!nrow(rows)) {
    return(echart_blank(empty, height = "160px"))
  }
  colour <- ifelse(grepl("^Leakage", rows$metric), .wise_policy,
    ifelse(grepl("^Adequacy", rows$metric), "#009E73", .wise_blue)
  )
  v <- 100 * rows$value
  .diag_hbar_chart(
    rows$metric, v, colour, notes = rows$note,
    x_max = max(100, ceiling(max(v[is.finite(v)], 0) / 10) * 10),
    empty = empty, name = "Share"
  )
}

# Grouped vertical bars of percentages, one group per scenario. `measures` is
# a named list of fraction vectors (one value per scenario).
.diag_grouped_pct_chart <- function(scenarios, measures, colours,
                                    height = "300px") {
  keep <- vapply(measures, function(x) any(is.finite(x)), logical(1))
  if (!length(scenarios) || !any(keep)) {
    return(echart_blank("Not available", height = height))
  }
  measures <- measures[keep]
  colours <- colours[keep]
  scenarios <- as.character(scenarios)
  e <- echarts4r::e_charts(
    data.frame(scenario = scenarios, y = 0), scenario, reorder = FALSE, height = height
  )
  e$x$opts$series <- lapply(seq_along(measures), function(i) {
    list(
      name = names(measures)[[i]], type = "bar", barMaxWidth = 38,
      data = lapply(measures[[i]], function(v) {
        list(
          value = if (is.finite(v)) 100 * v else NULL,
          itemStyle = list(color = unname(colours[[i]]))
        )
      }),
      label = list(
        show = TRUE, position = "top", color = .wise_charcoal, fontSize = 12,
        formatter = htmlwidgets::JS(
          "function(p) { return typeof p.value === 'number' ? p.value.toFixed(0) + '%' : ''; }"
        )
      )
    )
  })
  e$x$opts$xAxis <- list(
    type = "category", data = scenarios, axisLabel = wise_eaxis_label(),
    axisLine = list(lineStyle = list(color = .wise_grid)),
    axisTick = list(alignWithLabel = TRUE), splitLine = wise_esplit_line(show = FALSE)
  )
  e$x$opts$yAxis <- list(
    type = "value", min = 0, max = 100,
    axisLabel = wise_eaxis_label(formatter = "{value}%"), splitLine = wise_esplit_line()
  )
  e$x$opts$legend <- modifyList(
    list(bottom = 0, left = 0, orient = "horizontal"), wise_elegend_style()
  )
  e$x$opts$tooltip <- list(
    trigger = "axis", axisPointer = list(type = "shadow"),
    valueFormatter = htmlwidgets::JS(
      "function(v) { return typeof v === 'number' ? v.toFixed(1) + '%' : 'Not available'; }"
    )
  )
  e$x$opts$color <- unname(colours)
  e$x$opts$grid <- list(containLabel = TRUE, left = 8, right = 14, top = 34, bottom = 46)
  wise_echart_theme(e)
}

#' Share of simulated years with payments, by scenario
#'
#' @param summary Result of `sp_shock_summary()` (`scenario`, `activation_freq`).
#' @return An `echarts4r` widget.
#' @keywords internal
echart_shock_activation <- function(summary) {
  if (is.null(summary) || !nrow(summary)) {
    return(echart_blank("No shock-responsive run to show.", height = "300px"))
  }
  .diag_grouped_pct_chart(
    summary$scenario, list("Years with payments" = summary$activation_freq),
    .wise_blue
  )
}

#' Basis risk of the trigger, by scenario
#'
#' False positive rate: share of the population in no-loss-event locations that
#' is paid. False negative rate: share of the population in loss-event
#' locations that is not paid.
#'
#' @param summary Result of `sp_shock_summary()`.
#' @return An `echarts4r` widget.
#' @keywords internal
echart_shock_basis_risk <- function(summary) {
  if (is.null(summary) || !nrow(summary)) {
    return(echart_blank("No shock-responsive run to show.", height = "300px"))
  }
  .diag_grouped_pct_chart(
    summary$scenario,
    list(
      "False positives: paid, no loss event" = summary$false_positive_rate,
      "False negatives: loss event, not paid" = summary$false_negative_rate
    ),
    c(.wise_policy, "#A86400")
  )
}

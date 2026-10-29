# Seasonal forecast controls for the Step 2 sidebar ----
#
# UI scaffolding only: no forecast data is wired and nothing here reaches the
# simulation run. `.step2_forecast_runs()` is the single seam for the data
# source; it returns NULL (forecast shown as unavailable) unless the developer
# option `wiseapp.forecast_scaffold` is TRUE, which supplies one placeholder
# run so the controls can be exercised. See wise-app-data/dev/forecast_pipeline_plan.md.

# Weather variables the monthly forecast provides (SEAS5 t, tn, tx, r).
.STEP2_FORECAST_VARS <- c("t", "tn", "tx", "r")

# Months of context shown either side of the forecast months on the strip.
.STEP2_FORECAST_BEFORE <- 2L
.STEP2_FORECAST_AFTER <- 3L

# Most observed months the strip shows before the first forecast month, however
# far the fitted lagged predictors reach back.
.STEP2_FORECAST_BEFORE_MAX <- 6L

.STEP2_FORECAST_LEN_CHOICES <- c("1 month" = "1", "3 months" = "3", "6 months" = "6")

.STEP2_FORECAST_PRODUCT_LABELS <- c(
  "seasonal" = "Seasonal forecast",
  "subseasonal" = "Subseasonal forecast"
)

# TRUE for scenario names built by `.step2_forecast_display_key()`.
.step2_is_forecast_scenario <- function(nm) {
  grepl(paste0("^(", paste(.STEP2_FORECAST_PRODUCT_LABELS, collapse = "|"), ") / "), as.character(nm))
}

.step2_month_add <- function(d, n) {
  seq(d, by = paste(n, "month"), length.out = 2L)[2L]
}

#' Months before the target month that the fitted weather predictors reach back
#'
#' The longest `ref_end` (months before the interview) over the selected weather
#' variables; 0 when none is selected. Step 1 defines the lag windows, so this is
#' the lag a forecast target month needs from observed or earlier forecast months.
#' @param selected_weather Data frame of selected weather variables.
#' @noRd
.step2_forecast_lag <- function(selected_weather) {
  ends <- suppressWarnings(as.integer(selected_weather$ref_end))
  ends <- ends[!is.na(ends)]
  if (!length(ends)) return(0L)
  max(ends, 0L)
}

.step2_forecast_scaffold <- function() isTRUE(getOption("wiseapp.forecast_scaffold", FALSE))

#' Available forecast runs for the baseline country (placeholder)
#'
#' @param scaffold Logical; supply the placeholder run.
#' @return NULL when no forecast is available, else a named list of runs, each
#'   with `id`, `product`, `lead_unit`, `label`, `model`, `init` (first of the initialization month),
#'   `released`, `next_release`, `n_members` and `n_leads`.
#' @noRd
.step2_forecast_runs <- function(scaffold = .step2_forecast_scaffold()) {
  if (!isTRUE(scaffold)) return(NULL)
  list("2026-10" = list(
    id = "2026-10",
    product = "seasonal",
    lead_unit = "month",
    label = "October 2026",
    model = "ECMWF SEAS5",
    init = as.Date("2026-10-01"),
    released = as.Date("2026-10-06"),
    next_release = as.Date("2026-11-06"),
    n_members = 51L,
    n_leads = 6L
  ))
}

#' Month strip of a forecast run: observed context, forecast leads, beyond
#'
#' @param run One element of `.step2_forecast_runs()`.
#' @param lag Lag in months from `.step2_forecast_lag()`; widens the observed
#'   context up to `.STEP2_FORECAST_BEFORE_MAX` months.
#' @return Data frame with `month` (Date), `value` ("YYYY-MM"), `name`
#'   ("Nov"), `year` and `kind` ("obs", "fc" or "na").
#' @noRd
.step2_forecast_months <- function(run, lag = 0L) {
  n_before <- max(.STEP2_FORECAST_BEFORE, min(as.integer(lag), .STEP2_FORECAST_BEFORE_MAX))
  month <- seq(.step2_month_add(run$init, -n_before), by = "month",
    length.out = n_before + run$n_leads + .STEP2_FORECAST_AFTER)
  data.frame(
    month = month,
    value = format(month, "%Y-%m"),
    name = format(month, "%b"),
    year = format(month, "%Y"),
    kind = c(rep("obs", n_before), rep("fc", run$n_leads), rep("na", .STEP2_FORECAST_AFTER)),
    stringsAsFactors = FALSE
  )
}

#' Target-window start that fits the forecast horizon
#'
#' Keeps `start` when the `len`-month window fits inside the forecast months,
#' otherwise moves it to the nearest start that fits. An unset or invalid
#' `start` becomes the second forecast month (lead 2), the first full month.
#' @return A "YYYY-MM" value, or NULL when the run has no forecast months.
#' @noRd
.step2_forecast_clamp_start <- function(months, start, len) {
  fc <- which(months$kind == "fc")
  if (!length(fc)) return(NULL)
  len <- min(max(as.integer(len %||% 3L), 1L), length(fc))
  idx <- match(start %||% NA_character_, months$value)
  if (is.na(idx) || months$kind[idx] != "fc") idx <- fc[min(2L, length(fc))]
  months$value[min(max(idx, fc[1L]), fc[length(fc)] - len + 1L)]
}

#' Target window description for a start month and length
#' @return NULL, or a list with `label` ("Nov 2026 - Jan 2027"), `short`
#'   ("Nov-Jan"), `lead_from`, `lead_to` and the row range `idx`.
#' @noRd
.step2_forecast_window <- function(months, start, len) {
  start <- .step2_forecast_clamp_start(months, start, len)
  if (is.null(start)) return(NULL)
  len <- min(max(as.integer(len %||% 3L), 1L), sum(months$kind == "fc"))
  i <- match(start, months$value)
  j <- i + len - 1L
  dash <- "\u2013"
  first_fc <- which(months$kind == "fc")[1L]
  list(
    start = start,
    idx = c(i, j),
    label = if (len == 1L) {
      paste(months$name[i], months$year[i])
    } else {
      paste0(months$name[i], " ", months$year[i], " ", dash, " ", months$name[j], " ", months$year[j])
    },
    short = if (len == 1L) months$name[i] else paste0(months$name[i], dash, months$name[j]),
    lead_from = i - first_fc + 1L,
    lead_to = j - first_fc + 1L
  )
}

#' Sentence naming the months the lagged predictors also use
#' @noRd
.step2_forecast_lag_text <- function(months, window, lag) {
  i <- window$idx[[1L]]
  rows <- utils::tail(seq_len(i - 1L), lag)
  if (!length(rows)) return(NULL)
  lbl <- function(r) paste(months$name[r], months$year[r])
  obs <- rows[months$kind[rows] == "obs"]
  fc <- rows[months$kind[rows] == "fc"]
  parts <- c(
    if (length(obs)) paste("observed", paste(lbl(obs), collapse = ", ")),
    if (length(fc)) paste("forecast", paste(lbl(fc), collapse = ", "))
  )
  more <- if (lag > length(rows)) {
    paste0(" The model reaches back ", lag, " months in total; earlier months are observed.")
  }
  paste0("Lagged predictors also use ", paste(parts, collapse = " and "), ".", more)
}

#' Weather variables of the fitted model that the forecast does not provide
#' @param weather_names Character vector of selected weather variable names.
#' @noRd
.step2_forecast_unsupported <- function(weather_names) {
  setdiff(unique(as.character(weather_names)), .STEP2_FORECAST_VARS)
}

#' Why the forecast cannot be used, or NULL when it can
#' @param runs Result of `.step2_forecast_runs()`.
#' @param unsupported Result of `.step2_forecast_unsupported()`.
#' @noRd
.step2_forecast_block_reason <- function(runs, unsupported) {
  if (!length(runs)) {
    return("No seasonal forecast is available for the baseline country yet.")
  }
  if (length(unsupported)) {
    return(paste0(
      "Not available for this model: it uses ", paste(unsupported, collapse = ", "),
      ", which the monthly forecast does not provide. Refit without ",
      if (length(unsupported) == 1L) "it" else "them", " in Step 1 to enable."
    ))
  }
  NULL
}

#' Target window start picker: one tile per month
#'
#' A `pill_toggle()` styled as a month strip. Only forecast months can be
#' chosen. `inst/app/www/custom.js` paints the target window and the lag
#' months from the selected start and the length input `len_id`.
#' @noRd
forecast_strip_input <- function(inputId, len_id, months, selected, lag = 0L, disabled = FALSE) {
  tiles <- lapply(seq_len(nrow(months)), function(i) {
    shiny::tagList(
      months$name[[i]],
      shiny::tags$small(`data-kind` = months$kind[[i]], months$year[[i]])
    )
  })
  strip <- pill_toggle(
    inputId,
    choiceNames = tiles,
    choiceValues = months$value,
    selected = selected,
    extra_class = "forecast-strip",
    disabled = if (isTRUE(disabled)) TRUE else months$value[months$kind != "fc"],
    aria_label = "Target window start month"
  )
  htmltools::tagAppendAttributes(
    strip,
    `data-len-input` = len_id,
    `data-lag` = lag,
    style = paste0("--fc-cols:", nrow(months), ";")
  )
}

forecast_strip_legend <- function() {
  item <- function(cls, text) {
    shiny::tags$span(shiny::tags$i(class = paste("forecast-key", cls)), text)
  }
  shiny::tags$div(
    class = "forecast-legend",
    item("fc-obs", "Observed"),
    item("fc-lag", "Used for lags"),
    item("fc-fc", "Forecast"),
    item("fc-tg", "Target")
  )
}

#' Display key of the forecast scenario, e.g.
#' "Seasonal forecast / Nov 2026 - Jan 2027 (Oct 2026 run)"
#'
#' Sibling of `.step2_scenario_display_key()` for the forecast state.
#' @param run One element of `.step2_forecast_runs()`.
#' @param window Result of `.step2_forecast_window()`.
#' @noRd
.step2_forecast_display_key <- function(run, window) {
  product <- .STEP2_FORECAST_PRODUCT_LABELS[run$product %||% "seasonal"]
  paste0(product, " / ", window$label, " (", run$label, " run)")
}

#' Forecast inputs that enter the simulation run signature
#'
#' Run, product, target start and length. Member and data-version fields join
#' once the published run catalogue carries them.
#' @noRd
.step2_forecast_signature <- function(run, window) {
  list(
    product = run$product %||% "seasonal",
    run = run$id,
    start = window$start,
    len = window$idx[[2L]] - window$idx[[1L]] + 1L
  )
}

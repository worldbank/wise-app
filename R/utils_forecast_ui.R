# Seasonal forecast controls for the Step 2 sidebar ----
#
# Local forecast runs come from the validated country catalogue. The developer
# option `wiseapp.forecast_scaffold` supplies a metadata-only placeholder for
# control tests; the placeholder never reaches simulation runs.

# Initial data-preparation scope, not a permanent limit on forecast variables.
.STEP2_FORECAST_VARS <- "t"

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
  if (n == 0L) return(d)
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

#' Available forecast runs for the baseline country
#'
#' @param scaffold Logical; supply the placeholder run.
#' @param connection_params Local data connection parameters.
#' @param code Baseline country code.
#' @return NULL when no forecast is available, else a named list of runs, each
#'   with `id`, `product`, `lead_unit`, `label`, `model`, `init` (first of the initialization month),
#'   `released`, `next_release`, `observed_through`, `n_members` and `n_leads`.
#' @noRd
.step2_forecast_runs <- function(scaffold = .step2_forecast_scaffold(), connection_params = NULL, code = NULL) {
  if (!isTRUE(scaffold)) return(.forecast_catalogue_runs(connection_params, code))
  list("2026-10" = list(
    id = "2026-10",
    product = "seasonal",
    lead_unit = "month",
    label = "October 2026",
    model = "ECMWF SEAS5",
    init = as.Date("2026-10-01"),
    released = as.Date("2026-10-06"),
    next_release = as.Date("2026-11-06"),
    observed_through = as.Date("2025-12-01"),
    n_members = 51L,
    n_leads = 6L
  ))
}

#' Month strip of a forecast run: observed context, forecast leads, beyond
#'
#' @param run One element of `.step2_forecast_runs()`.
#' @param lag Lag in months from `.step2_forecast_lag()`; widens the observed
#'   context up to `.STEP2_FORECAST_BEFORE_MAX` months.
#' @param selected_weather Fitted predictor definitions; when supplied, check
#'   their exact lag windows rather than every lag up to `lag`.
#' @return Data frame with `month` (Date), `value` ("YYYY-MM"), `name`
#'   ("Nov"), `year`, `kind` ("obs", "fc" or "na") and `predictor_ok`.
#' @noRd
.step2_forecast_months <- function(run, lag = 0L, selected_weather = NULL) {
  n_before <- max(.STEP2_FORECAST_BEFORE, min(as.integer(lag), .STEP2_FORECAST_BEFORE_MAX))
  month <- seq(.step2_month_add(run$init, -n_before), by = "month",
    length.out = n_before + run$n_leads + .STEP2_FORECAST_AFTER)
  fc <- seq(run$init, by = "month", length.out = run$n_leads)
  observed <- run$observed_through %||% as.Date(NA)
  lags <- if (is.null(selected_weather)) {
    seq.int(0L, lag)
  } else {
    unique(unlist(lapply(seq_len(nrow(selected_weather)), function(i) {
      seq.int(as.integer(selected_weather$ref_start[i]), as.integer(selected_weather$ref_end[i]))
    })))
  }
  predictor_ok <- vapply(month, function(target) {
    needed <- vapply(lags, function(n) as.numeric(.step2_month_add(target, -n)), numeric(1))
    all((!is.na(observed) & needed <= as.numeric(observed)) | needed %in% as.numeric(fc))
  }, logical(1))
  data.frame(
    month = month,
    value = format(month, "%Y-%m"),
    name = format(month, "%b"),
    year = format(month, "%Y"),
    kind = ifelse(month %in% fc, "fc", ifelse(!is.na(observed) & month <= observed, "obs", "na")),
    predictor_ok = predictor_ok,
    stringsAsFactors = FALSE
  )
}

# Valid starts require every target month's fitted predictors to be available.
.step2_forecast_starts <- function(months, len) {
  len <- as.integer(len %||% 3L)
  if (length(len) != 1L || is.na(len) || len < 1L || len > nrow(months)) return(character(0))
  starts <- seq_len(nrow(months) - len + 1L)
  ok <- vapply(starts, function(i) {
    rows <- seq.int(i, i + len - 1L)
    all(months$kind[rows] == "fc" & months$predictor_ok[rows])
  }, logical(1))
  months$value[starts[ok]]
}

#' Target-window start that fits the forecast horizon and predictor availability
#'
#' Keeps `start` when the `len`-month window and its predictors are available,
#' otherwise moves it to the nearest start that fits. An unset or invalid
#' `start` defaults to the available start nearest the second forecast month.
#' @return A "YYYY-MM" value, or NULL when no complete window is available.
#' @noRd
.step2_forecast_clamp_start <- function(months, start, len) {
  fc <- which(months$kind == "fc")
  starts <- .step2_forecast_starts(months, len)
  if (!length(starts)) return(NULL)
  idx <- match(start %||% NA_character_, months$value)
  if (is.na(idx) || months$kind[idx] != "fc") idx <- fc[min(2L, length(fc))]
  valid <- match(starts, months$value)
  starts[which.min(abs(valid - idx))]
}

#' Target window description for a start month and length
#' @return NULL, or a list with `label` ("Nov 2026 - Jan 2027"), `short`
#'   ("Nov-Jan"), `lead_from`, `lead_to` and the row range `idx`.
#' @noRd
.step2_forecast_window <- function(months, start, len) {
  start <- .step2_forecast_clamp_start(months, start, len)
  if (is.null(start)) return(NULL)
  len <- as.integer(len %||% 3L)
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
.step2_forecast_lag_text <- function(months, window, lag, selected_weather = NULL) {
  i <- window$idx[[1L]]
  rows <- utils::tail(seq_len(i - 1L), lag)
  if (!is.null(selected_weather)) {
    lags <- unique(unlist(lapply(seq_len(nrow(selected_weather)), function(j) {
      seq.int(as.integer(selected_weather$ref_start[j]), as.integer(selected_weather$ref_end[j]))
    })))
    needed <- unique(unlist(lapply(seq.int(window$idx[1L], window$idx[2L]), function(j) {
      vapply(lags, function(n) as.numeric(.step2_month_add(months$month[j], -n)), numeric(1))
    })))
    rows <- rows[as.numeric(months$month[rows]) %in% needed]
  }
  if (!length(rows) && lag <= i - 1L) return(NULL)
  lbl <- function(r) paste(months$name[r], months$year[r])
  obs <- rows[months$kind[rows] == "obs"]
  fc <- rows[months$kind[rows] == "fc"]
  parts <- c(
    if (length(obs)) paste("observed", paste(lbl(obs), collapse = ", ")),
    if (length(fc)) paste("forecast", paste(lbl(fc), collapse = ", "))
  )
  more <- if (lag > i - 1L) {
    paste0(" The model reaches back ", lag, " months in total; earlier required months are observed.")
  }
  paste0(if (length(parts)) paste0("Lagged predictors also use ", paste(parts, collapse = " and "), "."), more)
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
.step2_forecast_block_reason <- function(runs, unsupported, months = NULL, len = 1L, start = NULL) {
  if (!length(runs)) {
    return("No seasonal forecast is available for the baseline country yet.")
  }
  if (length(unsupported)) {
    return(paste0(
      "Not available for this model: it uses ", paste(unsupported, collapse = ", "),
      ", which the current forecast data preparation does not provide. Refit without ",
      if (length(unsupported) == 1L) "it" else "them", " in Step 1 to enable."
    ))
  }
  if (!is.null(months)) {
    starts <- .step2_forecast_starts(months, len)
    if (!length(starts) || (!is.null(start) && !start %in% starts)) {
      return(paste0(
        "Target window unavailable: every target month and every month needed by its fitted predictors ",
        "must be observed through the run's observed cutoff or forecast by this run. ",
        "Choose another start or a shorter window; missing months are not filled."
      ))
    }
  }
  NULL
}

#' Target window start picker: one tile per month
#'
#' A `pill_toggle()` styled as a month strip. Only forecast months can be
#' chosen. `inst/app/www/custom.js` paints the target window and the lag
#' months from the selected start and the length input `len_id`.
#' @noRd
forecast_strip_input <- function(inputId, len_id, months, selected, lag = 0L, disabled = FALSE, len = 1L) {
  starts <- .step2_forecast_starts(months, len)
  tiles <- lapply(seq_len(nrow(months)), function(i) {
    why <- if (months$kind[i] == "fc" && !months$value[i] %in% starts) {
      .step2_forecast_block_reason(list(TRUE), character(0), months, len, months$value[i])
    }
    shiny::tags$span(title = why,
      months$name[[i]],
      shiny::tags$small(`data-kind` = months$kind[[i]], months$year[[i]]),
      if (!is.null(why)) shiny::tags$span(class = "visually-hidden", why)
    )
  })
  strip <- pill_toggle(
    inputId,
    choiceNames = tiles,
    choiceValues = months$value,
    selected = selected %||% character(0),
    extra_class = "forecast-strip",
    disabled = if (isTRUE(disabled)) TRUE else setdiff(months$value, starts),
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
#' Run, product, target start, length and immutable data/member identity.
#' @noRd
.step2_forecast_signature <- function(run, window) {
  out <- list(
    product = run$product %||% "seasonal",
    run = run$id,
    start = window$start,
    len = window$idx[[2L]] - window$idx[[1L]] + 1L
  )
  if (!is.null(run$data_sha256)) {
    out$data_version <- run$data_version
    out$data_sha256 <- run$data_sha256
    out$manifest_sha256 <- run$manifest_sha256
    out$historical_sha256 <- run$historical_sha256
    out$members <- run$members
  }
  out
}

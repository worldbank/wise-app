# ENSO annotation of results (roadmap/enso.md) ----
#
# Shiny-free helpers. ENSO is a label on results, never an input to them (D1): nothing here
# is called from the simulation, the aggregation or the run signature. The two tables are
# optional (D6): every loader failure returns NULL and no error reaches the caller.

ENSO_FILES <- c(
  observed = "metadata/enso.csv",
  forecast = "metadata/enso_forecast.csv"
)

# Phase ids as published upstream, plus the "mixed" class of the year label (D2).
ENSO_PHASES <- c("el_nino", "neutral", "la_nina")
ENSO_LABEL_LEVELS <- c(ENSO_PHASES, "mixed")
ENSO_LABEL_TEXT <- c(
  el_nino = "El Ni\u00f1o", neutral = "Neutral", la_nina = "La Ni\u00f1a", mixed = "Mixed"
)

# Model id of a forecast run (its manifest) to the matching source in `enso_forecast.csv` (D4).
ENSO_FORECAST_SOURCES <- c(ecmwf_seas51 = "ecmwf_51")

# A share within this distance of the threshold counts as reaching it. It absorbs
# floating-point sums such as 0.1 + 0.2 + 0.2 and is far below any real share step.
.ENSO_SHARE_TOL <- 1e-9


# Loading and validation (D6) ----

#' Soft loader for the observed and forecast ENSO tables
#'
#' Reads `metadata/enso.csv` and `metadata/enso_forecast.csv` through `load_data()` (local and
#' cloud sources). On Databricks the Overview loader fetches both files in its own request batch
#' and passes them as `tables`, so no DuckDB session starts for them. Both tables are optional: a
#' missing, empty or malformed observed table returns `NULL`; a missing or malformed forecast
#' table only leaves `forecast` as `NULL`. Never signals an error or a warning.
#'
#' @param connection_params Named connection parameter list, as for `load_data()`.
#' @param tables Optional list with the already read `observed` and `forecast` data frames
#'   (`NULL` for a file that could not be read); skips reading.
#' @return `NULL`, or a list with `observed` (tibble: `month`, `source`, `roni`, `phase`,
#'   one row per consecutive month, sorted) and `forecast` (tibble or `NULL`).
#' @noRd
enso_load <- function(connection_params = list(type = "local", path = .default_data_path()),
                      tables = NULL) {
  read_one <- function(file) {
    if (!is.null(tables)) return(tables[[names(ENSO_FILES)[match(file, ENSO_FILES)]]])
    tryCatch(
      suppressWarnings(suppressMessages(
        load_data(file, connection_params, collect = TRUE)
      )),
      error = function(e) NULL
    )
  }
  observed <- .enso_validate_observed(read_one(ENSO_FILES[["observed"]]))
  if (is.null(observed)) return(NULL)
  forecast <- .enso_validate_forecast(read_one(ENSO_FILES[["forecast"]]))
  list(observed = observed, forecast = forecast)
}

# First day of the month as Date, or NULL if any value is not a date.
.enso_as_month <- function(x) {
  if (inherits(x, "POSIXt")) x <- as.Date(x)
  if (!inherits(x, "Date")) {
    x <- tryCatch(as.Date(as.character(x), optional = TRUE), error = function(e) NULL)
  }
  if (is.null(x) || anyNA(x)) return(NULL)
  as.Date(format(x, "%Y-%m-01"))
}

# Month counter used as a join key: year * 12 + month - 1.
.enso_month_key <- function(x) {
  lt <- as.POSIXlt(x)
  (lt$year + 1900L) * 12L + lt$mon
}

.enso_validate_observed <- function(df) {
  if (!is.data.frame(df) || !nrow(df) || !all(c("timestamp", "roni", "phase") %in% names(df))) {
    return(NULL)
  }
  month <- .enso_as_month(df$timestamp)
  roni <- suppressWarnings(as.numeric(df$roni))
  phase <- as.character(df$phase)
  if (is.null(month) || anyNA(roni) || !all(phase %in% ENSO_PHASES)) return(NULL)
  o <- order(month)
  month <- month[o]
  if (any(diff(.enso_month_key(month)) != 1L)) return(NULL) # duplicates and gaps
  source <- if ("source" %in% names(df)) as.character(df$source)[o] else rep(NA_character_, length(o))
  tibble::tibble(month = month, source = source, roni = roni[o], phase = phase[o])
}

.enso_validate_forecast <- function(df) {
  need <- c(
    "source", "init_date", "timestamp", "lead_month", "roni", "prob_el_nino", "prob_la_nina",
    "prob_neutral", "phase"
  )
  if (!is.data.frame(df) || !nrow(df) || !all(need %in% names(df))) return(NULL)
  # Upstream writes an empty value as the text "NA", which also makes these columns character.
  optional <- setdiff(need, c("source", "init_date", "timestamp"))
  df[optional] <- lapply(df[optional], function(x) replace(x, as.character(x) %in% c("", "NA"), NA))
  month <- .enso_as_month(df$timestamp)
  init <- .enso_as_month(df$init_date)
  num <- function(x) suppressWarnings(as.numeric(x))
  phase <- as.character(df$phase)
  probs <- lapply(df[c("prob_el_nino", "prob_la_nina", "prob_neutral")], num)
  # Empty values are allowed only where upstream leaves them empty (first and last lead).
  bad_num <- function(x, orig) anyNA(x[!is.na(orig)])
  if (is.null(month) || is.null(init) || !all(phase[!is.na(phase)] %in% ENSO_PHASES) ||
      bad_num(num(df$roni), df$roni) || bad_num(num(df$lead_month), df$lead_month) ||
      any(mapply(bad_num, probs, df[c("prob_el_nino", "prob_la_nina", "prob_neutral")]))) {
    return(NULL)
  }
  if (anyDuplicated(data.frame(df$source, month))) return(NULL)
  tibble::tibble(
    source = as.character(df$source), init_date = init, month = month,
    lead_month = as.integer(num(df$lead_month)), roni = num(df$roni),
    prob_el_nino = probs$prob_el_nino, prob_la_nina = probs$prob_la_nina,
    prob_neutral = probs$prob_neutral, phase = phase
  )
}


# Fitted window and month weights ----

#' Lags covered by the fitted weather windows (D2)
#'
#' With several weather variables the window is the union range, from the smallest
#' `ref_start` to the largest `ref_end`, in months before the interview month.
#'
#' @param selected_weather Data frame with `ref_start` and `ref_end`.
#' @return Integer vector of lags; `integer(0)` when the input is unusable.
#' @noRd
enso_window <- function(selected_weather) {
  if (!is.data.frame(selected_weather) || !all(c("ref_start", "ref_end") %in% names(selected_weather))) {
    return(integer(0))
  }
  s <- suppressWarnings(as.integer(selected_weather$ref_start))
  e <- suppressWarnings(as.integer(selected_weather$ref_end))
  if (!length(s) || anyNA(c(s, e)) || any(s < 0L) || any(e < s)) return(integer(0))
  seq.int(min(s), max(e))
}

#' Share of the baseline weight in each calendar month
#'
#' @param months Interview months: integers 1 to 12, or `Date`/`POSIXt` values.
#' @param weights Optional non-negative weights, one per interview; equal when `NULL`.
#' @return Numeric vector of length 12 that sums to 1 (`NA`s when there is no weight).
#' @noRd
enso_month_weights <- function(months, weights = NULL) {
  if (inherits(months, c("Date", "POSIXt"))) months <- as.integer(format(months, "%m"))
  months <- as.integer(as.character(months)) # through text: a factor's codes are not months
  weights <- if (is.null(weights)) rep(1, length(months)) else as.numeric(weights)
  keep <- !is.na(months) & months >= 1L & months <= 12L & !is.na(weights) & weights > 0
  out <- vapply(1:12, function(m) sum(weights[keep & months == m]), numeric(1))
  total <- sum(out)
  if (total > 0) out / total else rep(NA_real_, 12L)
}


# Year labels (D2) ----

#' Exposure-weighted ENSO label of each simulated year
#'
#' For year `r`, interview-month weight `w[mu]` and fitted lags `K`, the share in phase `k`
#' is `sum_mu w[mu] * mean_j(phase(r, mu - j) == k)`, and the exposure RONI is the same
#' average of `roni`. A year is labelled by the phase whose share reaches `threshold`;
#' otherwise (or when two phases both reach it, a tie at exactly 0.5) it is `"mixed"`. A year
#' whose lag reaches outside the table gets `NA` in every column. Shares are not rounded.
#'
#' @param enso Observed table from `enso_load()$observed`.
#' @param years Integer vector of simulation years.
#' @param month_weights Length-12 weights from `enso_month_weights()`; normalised here.
#' @param lags Integer lags in months before the interview month, from `enso_window()`.
#' @param start_month `NULL` for the annual series. For a forecast window that crosses
#'   December, the first target month: months before it belong to the following calendar
#'   year, so the reference year is the year the window starts (D3).
#' @param threshold Share needed to label a year.
#' @return Tibble: `sim_year`, `el_nino`, `neutral`, `la_nina` (shares), `roni_exp`, `label`.
#' @noRd
enso_year_labels <- function(enso, years, month_weights, lags, start_month = NULL, threshold = 0.5) {
  years <- as.integer(years)
  empty <- tibble::tibble(
    sim_year = years, el_nino = NA_real_, neutral = NA_real_, la_nina = NA_real_,
    roni_exp = NA_real_, label = NA_character_
  )
  w <- as.numeric(month_weights)
  lags <- as.integer(lags)
  if (is.null(enso) || length(w) != 12L || anyNA(w) || any(w < 0) || sum(w) <= 0 ||
      !length(lags) || anyNA(lags)) {
    return(empty)
  }
  w <- w / sum(w)
  mu <- which(w > 0)
  key <- .enso_month_key(enso$month)
  grid <- expand.grid(lag = lags, mu = mu)
  wt <- w[grid$mu] / length(lags) # each (mu, lag) cell carries w[mu] / |K|
  shift <- if (is.null(start_month)) 0L else as.integer(grid$mu < start_month)

  for (i in seq_along(years)) {
    pos <- match((years[i] + shift) * 12L + grid$mu - 1L - grid$lag, key)
    if (anyNA(pos)) next
    ph <- enso$phase[pos]
    s <- vapply(ENSO_PHASES, function(k) sum(wt[ph == k]), numeric(1))
    top <- s >= threshold - .ENSO_SHARE_TOL
    empty$el_nino[i] <- s[["el_nino"]]
    empty$neutral[i] <- s[["neutral"]]
    empty$la_nina[i] <- s[["la_nina"]]
    empty$roni_exp[i] <- sum(wt * enso$roni[pos])
    empty$label[i] <- if (sum(top) == 1L) ENSO_PHASES[top] else "mixed"
  }
  empty
}


#' ENSO label of each reference year of a forecast window (D3)
#'
#' The D2 label with equal weight on the target months as interview months, so the fitted lags
#' are treated as for a household. The reference year is the year the window starts, as in
#' `refyear_<year>` of `.get_forecast_weather()`: November 1997 to January 1998 is 1997.
#'
#' @param enso Observed table from `enso_load()$observed`.
#' @param forecast The `forecast` entry of a scenario (`forecast_months`, `reference_years`).
#' @param lags Integer lags from `enso_window()`.
#' @return Tibble from `enso_year_labels()` with `period`, the months of each reference year as
#'   text ("Nov 1997 - Jan 1998").
#' @noRd
enso_window_labels <- function(enso, forecast, lags) {
  months <- as.Date(forecast$forecast_months)
  mu <- as.integer(format(months, "%m"))
  labels <- enso_year_labels(
    enso, forecast$reference_years, enso_month_weights(mu), lags, start_month = mu[[1L]]
  )
  first <- months[[1L]]
  last <- months[[length(months)]]
  crossing <- as.integer(format(last, "%Y")) - as.integer(format(first, "%Y"))
  labels$period <- if (length(months) > 1L) {
    paste(format(first, "%b"), labels$sim_year, "-", format(last, "%b"), labels$sim_year + crossing)
  } else {
    paste(format(first, "%b"), labels$sim_year)
  }
  labels
}


# Phase comparison (D5) ----

#' Mean outcome by ENSO label, with the difference from Neutral
#'
#' Counts and means only (D5). The difference from Neutral is `NA` for Neutral itself, for
#' Mixed, and when either side has fewer than `min_n` years. Years without a label are not
#' counted.
#'
#' @param labels Tibble from `enso_year_labels()` (`sim_year`, `label`).
#' @param values Data frame with `sim_year`, `value` and optionally `series`.
#' @param min_n Smallest number of years in a phase to compare it.
#' @return Tibble: `series`, `label`, `n`, `mean`, `diff_neutral`, one row per series and
#'   label in `ENSO_LABEL_LEVELS`.
#' @noRd
enso_phase_summary <- function(labels, values, min_n = 3L) {
  if (!"series" %in% names(values)) values$series <- "all"
  d <- merge(
    values[c("series", "sim_year", "value")], labels[c("sim_year", "label")],
    by = "sim_year"
  )
  d <- d[!is.na(d$label) & !is.na(d$value), , drop = FALSE]
  rows <- lapply(unique(as.character(values$series)), function(s) {
    di <- d[d$series == s, , drop = FALSE]
    n <- vapply(ENSO_LABEL_LEVELS, function(k) sum(di$label == k), numeric(1))
    m <- vapply(ENSO_LABEL_LEVELS, function(k) {
      if (any(di$label == k)) mean(di$value[di$label == k]) else NA_real_
    }, numeric(1))
    comparable <- n >= min_n & n[["neutral"]] >= min_n & ENSO_LABEL_LEVELS %in% c("el_nino", "la_nina")
    tibble::tibble(
      series = s, label = ENSO_LABEL_LEVELS, n = as.integer(n), mean = unname(m),
      diff_neutral = unname(ifelse(comparable, m - m[["neutral"]], NA_real_))
    )
  })
  do.call(rbind, rows)
}


# Outlook for a forecast run (D4) ----

#' ENSO state of the target months of a forecast run
#'
#' Uses `enso_forecast.csv` when its `init_date` equals the run's `init`, preferring the row
#' set of the run's own `system` (for example `"ecmwf_51"`) and falling back on
#' `"multimodel"`. The file keeps only the latest initialisation, so otherwise the months
#' come from `enso.csv` (`basis` is `"observed"`: a later outlook). RONI empty at the first
#' and last lead is filled from `enso.csv`; probabilities stay `NA` there. Probabilities
#' are shares of members, not calibrated.
#'
#' @param enso List from `enso_load()`.
#' @param target_months `Date` vector of target months.
#' @param init `Date` of the run's initialisation.
#' @param system Source id of the weather run, or `NULL`.
#' @return Tibble: `month`, `roni`, `phase`, `prob_el_nino`, `prob_la_nina`, `prob_neutral`,
#'   `source` (the forecast source, or `NA`), `basis`; zero rows when nothing covers the months.
#' @noRd
enso_forecast_outlook <- function(enso, target_months, init, system = NULL) {
  months <- .enso_as_month(target_months)
  out <- tibble::tibble(
    month = as.Date(character()), roni = numeric(), phase = character(),
    prob_el_nino = numeric(), prob_la_nina = numeric(), prob_neutral = numeric(),
    source = character(), basis = character()
  )
  if (is.null(enso) || is.null(months)) return(out)
  obs_pos <- match(.enso_month_key(months), .enso_month_key(enso$observed$month))
  init <- tryCatch(.enso_as_month(init), error = function(e) NULL)

  fc <- NULL
  fc_source <- NA_character_
  if (!is.null(enso$forecast) && !is.null(init) && length(init) == 1L) {
    cand <- enso$forecast[enso$forecast$init_date == init, , drop = FALSE]
    for (src in unique(c(system, "multimodel"))) {
      hit <- cand[cand$source == src & .enso_month_key(cand$month) %in% .enso_month_key(months), ,
        drop = FALSE]
      if (nrow(hit)) {
        fc <- hit
        fc_source <- src
        break
      }
    }
  }
  fpos <- if (is.null(fc)) rep(NA_integer_, length(months)) else {
    match(.enso_month_key(months), .enso_month_key(fc$month))
  }
  keep <- !is.na(fpos) | !is.na(obs_pos)
  if (!any(keep)) return(out)
  pick <- function(col) if (is.null(fc)) rep(NA_real_, length(months)) else fc[[col]][fpos]
  roni <- ifelse(is.na(pick("roni")), enso$observed$roni[obs_pos], pick("roni"))
  phase <- if (is.null(fc)) rep(NA_character_, length(months)) else fc$phase[fpos]
  phase <- ifelse(is.na(phase), enso$observed$phase[obs_pos], phase)
  tibble::tibble(
    month = months, roni = roni, phase = phase,
    prob_el_nino = pick("prob_el_nino"), prob_la_nina = pick("prob_la_nina"),
    prob_neutral = pick("prob_neutral"),
    source = ifelse(is.na(fpos), NA_character_, fc_source),
    basis = ifelse(is.na(fpos), "observed", "forecast")
  )[keep, ]
}


#' Phase of an outlook: the phase of at least half of its months, else `"mixed"`
#'
#' @param outlook Tibble from `enso_forecast_outlook()`.
#' @return A label id from `ENSO_LABEL_LEVELS`, or `NA` without a phase.
#' @noRd
enso_outlook_phase <- function(outlook) {
  phase <- outlook$phase[!is.na(outlook$phase)]
  if (!length(phase)) return(NA_character_)
  top <- vapply(ENSO_PHASES, function(k) mean(phase == k), numeric(1)) >= 0.5 - .ENSO_SHARE_TOL
  if (sum(top) == 1L) ENSO_PHASES[top] else "mixed"
}

#' Reference years at least as adverse as the median member, in one phase and in all (item 7)
#'
#' "At least as adverse" as in `.forecast_placement_stats()`. Counts only; `NULL` below `min_n`
#' years of the phase (D5).
#'
#' @param placement Result of `step2_window_placement()`.
#' @param labels Tibble from `enso_window_labels()`.
#' @param phase Label id of the years to compare with.
#' @param min_n Smallest number of years in the phase to compare it.
#' @return `NULL`, or a list: `n`, `n_adverse` (the phase) and `n_all`, `n_adverse_all` (all years).
#' @noRd
enso_reference_comparison <- function(placement, labels, phase, min_n = 3L) {
  median_member <- placement$summary$member_median
  if (is.null(labels) || !length(median_member) || !is.finite(median_member)) return(NULL)
  ref <- placement$reference[is.finite(placement$reference$value), , drop = FALSE]
  label <- labels$label[match(as.integer(ref$year), labels$sim_year)]
  in_phase <- !is.na(label) & label == phase
  if (sum(in_phase) < min_n) return(NULL)
  adverse <- if (identical(placement$adverse_tail, "high")) ref$value >= median_member else ref$value <= median_member
  list(
    n = sum(in_phase), n_adverse = sum(adverse[in_phase]), n_all = nrow(ref), n_adverse_all = sum(adverse)
  )
}

# Source id of the forecast run in `enso_forecast.csv`, or `NULL` when the run has none (D4).
.enso_run_system <- function(run) {
  model <- run$model_id
  if (length(model) == 1L && model %in% names(ENSO_FORECAST_SOURCES)) ENSO_FORECAST_SOURCES[[model]]
}

#' ENSO outlook of the forecast target months as a mark for the forecast members
#'
#' The members share one target window, so they share one state: the outlook phase (D4). The text names
#' the outlook for the tooltip of a marked member.
#'
#' @param enso List from `enso_load()`.
#' @param forecast The `forecast` entry of the scenario (`forecast_months`).
#' @param run The run's `init` and `model_id` (`hist_sim$forecast_run`), or `NULL`.
#' @param months_label Target months as text ("Nov - Jan").
#' @return `NULL` when nothing covers the target months, else a list: `phase` (label id), `roni` (mean over the
#'   months) and `text`.
#' @noRd
enso_forecast_marks <- function(enso, forecast, run, months_label) {
  outlook <- enso_forecast_outlook(enso, forecast$forecast_months, run$init, .enso_run_system(run))
  phase <- enso_outlook_phase(outlook)
  if (is.na(phase)) return(NULL)
  roni <- unique(formatC(range(outlook$roni, na.rm = TRUE), digits = 2L, format = "f"))
  later <- if (!all(outlook$basis == "forecast")) ", later outlook, not from this run" else ""
  list(
    phase = phase, roni = mean(outlook$roni, na.rm = TRUE),
    text = paste0(
      "ENSO outlook, ", months_label, ": ", enso_label_text(phase), " (RONI ", paste(roni, collapse = " to "),
      later, ")"
    )
  )
}

#' ENSO text of the forecast placement card (item 7)
#'
#' The outlook of the target months (D4) and, when the outlook has one phase, the median member
#' against the reference years of that phase. The RONI of the current event crosses a data seam
#' upstream, so a value above the record is named as such, without a margin.
#'
#' @param enso List from `enso_load()`.
#' @param forecast The `forecast` entry of the scenario (`forecast_months`).
#' @param run The run's `init` and `model_id` (`hist_sim$forecast_run`), or `NULL`.
#' @param placement Result of `step2_window_placement()`.
#' @param labels Tibble from `enso_window_labels()`, or `NULL`.
#' @param months_label Target months as text ("Nov - Jan").
#' @return `NULL` when nothing covers the target months, else a list: `line`, `info`, `outlook`
#'   (`enso_forecast_outlook()`), `phase` and `compare` (`enso_reference_comparison()`, or `NULL`).
#' @noRd
enso_placement_text <- function(enso, forecast, run, placement, labels, months_label) {
  system <- .enso_run_system(run)
  outlook <- enso_forecast_outlook(enso, forecast$forecast_months, run$init, system)
  phase <- enso_outlook_phase(outlook)
  if (is.na(phase)) return(NULL)

  origin <- if (!all(outlook$basis == "forecast")) {
    " (later outlook, not from this run)"
  } else if (all(outlook$source == "multimodel") && !identical(system, "multimodel")) {
    " (multi-model)"
  } else {
    ""
  }
  roni <- unique(formatC(range(outlook$roni, na.rm = TRUE), digits = 2L, format = "f"))
  members <- if (phase %in% ENSO_PHASES) outlook[[paste0("prob_", phase)]]
  state <- paste0(
    "RONI ", paste(roni, collapse = " to "),
    if (length(members) && !anyNA(members)) {
      if (min(members) >= 1) ", all members" else paste0(", at least ", round(100 * min(members)), "% of members")
    }
  )
  record <- enso$observed$roni[!enso$observed$source %in% "forecast"]
  stronger <- identical(phase, "el_nino") && length(record) && max(outlook$roni, na.rm = TRUE) > max(record)
  name <- if (identical(phase, "mixed")) "Mixed phases" else enso_label_text(phase)
  compare <- if (phase %in% ENSO_PHASES) enso_reference_comparison(placement, labels, phase)
  line <- paste0(
    "ENSO outlook, ", months_label, origin, ": ", name, " (", state, ")",
    if (stronger) ", stronger than any event in the record, on this forecast", ".",
    if (!is.null(compare)) sprintf(
      " At least as adverse as the median member: %d of %d %s exposure years, %d of %d in all years.",
      compare$n_adverse, compare$n, name, compare$n_adverse_all, compare$n_all
    )
  )
  list(outlook = outlook, phase = phase, compare = compare, line = line, info = paste(c(
    if (!is.null(compare)) sprintf("Few events fall in a window: %d of %d years here.", compare$n, compare$n_all),
    "Past events differ from each other and are not a forecast. Shares of members are not calibrated. The index",
    "is relative Ni\u00f1o 3.4 (RONI), which may differ from figures in the press."
  ), collapse = " "))
}


# Results helpers (items 1, 2, 3 and 5) ----

# Marks on the distribution chart: colour plus symbol, so the phase never rests on colour alone.
# The colours stay clear of `.ssp_colours`, `.wise_policy` and `.wise_forecast`; the dark outline
# keeps a light fill readable on the white chart.
ENSO_MARKS <- list(
  el_nino = list(color = "#E69F00", symbol = "triangle", symbol_size = 9),
  la_nina = list(color = "#56B4E9", symbol = "diamond", symbol_size = 9)
)

#' Display text of ENSO labels
#' @param x Character vector of label ids (`ENSO_LABEL_LEVELS`).
#' @noRd
enso_label_text <- function(x) unname(ENSO_LABEL_TEXT[as.character(x)])

#' ENSO phase and RONI of each interview month, by survey wave
#'
#' Placed by interview date, so each wave sits in its own year. Where a wave has interviews in the same
#' calendar month of two years, the first one counts. Months outside the ENSO record are left out.
#'
#' @param enso Observed table from `enso_load()$observed`.
#' @param dates Interview dates (`Date` or `POSIXt`), one per household.
#' @param group Vector (the survey wave) matching `dates`.
#' @return Data frame: `group`, `month_num`, `phase`, `roni`.
#' @noRd
enso_interview_months <- function(enso, dates, group) {
  ok <- !is.na(dates)
  d <- as.Date(dates[ok])
  pos <- match(.enso_month_key(d), .enso_month_key(enso$month))
  hit <- !is.na(pos)
  out <- data.frame(
    group = as.character(group[ok])[hit], month_num = as.integer(format(d[hit], "%m")),
    phase = enso$phase[pos[hit]], roni = enso$roni[pos[hit]], stringsAsFactors = FALSE
  )
  out[!duplicated(out[c("group", "month_num")]), , drop = FALSE]
}

#' Attach the ENSO label of each simulation year to a table of annual outcomes
#'
#' Rows of the forecast target months (the forecast members, whose `sim_year` is the member
#' index, and the Historical series of the same months) get no label: D3 treats them apart.
#' Climate scenarios carry the label of their template year.
#'
#' @param tbl Data frame with `scenario` and `sim_year`.
#' @param labels Tibble from `enso_year_labels()`.
#' @return `tbl` with `enso_label`, `enso_el_nino`, `enso_neutral`, `enso_la_nina`, `enso_roni`.
#' @noRd
enso_attach_labels <- function(tbl, labels) {
  idx <- match(as.integer(tbl$sim_year), labels$sim_year)
  idx[.step2_is_forecast_like(tbl$scenario)] <- NA_integer_
  tbl$enso_label <- labels$label[idx]
  tbl$enso_el_nino <- labels$el_nino[idx]
  tbl$enso_neutral <- labels$neutral[idx]
  tbl$enso_la_nina <- labels$la_nina[idx]
  tbl$enso_roni <- labels$roni_exp[idx]
  tbl
}

#' Attach the window labels to the Historical rows of the forecast target months (item 7)
#'
#' Only rows of `reference_label` are touched: a member's `sim_year` is its index, so forecast
#' rows stay unlabelled (D3), and annual rows keep their own label.
#'
#' @param tbl Merged rows (`.step2_window_merge()`) with `scenario` and `sim_year`.
#' @param labels Tibble from `enso_window_labels()`, or `NULL`.
#' @param reference_label Display label of the Historical series of the target months.
#' @return `tbl` with the columns of `enso_attach_labels()` and `enso_period`.
#' @noRd
enso_attach_window_labels <- function(tbl, labels, reference_label) {
  if (is.null(labels) || is.null(reference_label)) return(tbl)
  rows <- which(tbl$scenario == reference_label)
  idx <- match(as.integer(tbl$sim_year[rows]), labels$sim_year)
  cols <- c(
    enso_label = "label", enso_el_nino = "el_nino", enso_neutral = "neutral", enso_la_nina = "la_nina",
    enso_roni = "roni_exp", enso_period = "period"
  )
  for (nm in names(cols)) {
    v <- tbl[[nm]] %||% rep(labels[[cols[[nm]]]][NA_integer_], nrow(tbl))
    v[rows] <- labels[[cols[[nm]]]][idx]
    tbl[[nm]] <- v
  }
  tbl
}

#' Attach the ENSO outlook to the forecast member rows
#'
#' Every member of the forecast window gets the outlook phase of the target months
#' (`enso_forecast_marks()`) and its tooltip text in `enso_text`; other rows are left as they are.
#'
#' @param tbl Merged rows with `scenario`, as after `enso_attach_labels()`.
#' @param marks Result of `enso_forecast_marks()`, or `NULL`.
#' @param member_label Display label of the forecast member series.
#' @return `tbl`, with `enso_text` added.
#' @noRd
enso_attach_forecast_labels <- function(tbl, marks, member_label) {
  if (is.null(marks) || is.null(member_label)) return(tbl)
  rows <- which(tbl$scenario == member_label)
  if (is.null(tbl$enso_text)) tbl$enso_text <- NA_character_
  if (is.null(tbl$enso_label)) tbl$enso_label <- NA_character_
  if (is.null(tbl$enso_roni)) tbl$enso_roni <- NA_real_
  tbl$enso_label[rows] <- marks$phase
  tbl$enso_roni[rows] <- marks$roni
  tbl$enso_text[rows] <- marks$text
  tbl
}

#' Phase comparison table of the Results section (item 3)
#'
#' One row per series. Each series is averaged over its climate models by simulation year
#' first, so a year counts once, then summarised by `enso_phase_summary()`.
#'
#' @param curves Data frame with `scenario`, `sim_year`, `value` and optionally `model_id`;
#'   forecast-like series are left out.
#' @param labels Tibble from `enso_year_labels()`.
#' @param min_n Smallest number of years in a phase to compare it.
#' @return Tibble: `series` and, for each of `el_nino`, `neutral`, `la_nina`, `mixed`, the
#'   columns `n_<phase>` and `mean_<phase>`, plus `diff_el_nino` and `diff_la_nina`.
#' @noRd
enso_series_table <- function(curves, labels, min_n = 3L) {
  if (is.null(curves)) return(NULL)
  curves <- curves[!.step2_is_forecast_like(curves$scenario) & is.finite(curves$value), , drop = FALSE]
  if (!nrow(curves)) return(NULL) # aggregate() fails on no rows
  yearly <- stats::aggregate(value ~ scenario + sim_year, data = curves, FUN = mean)
  yearly$scenario <- as.character(yearly$scenario)
  values <- data.frame(series = yearly$scenario, sim_year = yearly$sim_year, value = yearly$value)
  s <- enso_phase_summary(labels, values, min_n = min_n)
  out <- lapply(unique(s$series), function(g) {
    r <- s[s$series == g, , drop = FALSE]
    pick <- function(col, k) r[[col]][r$label == k]
    row <- list(series = g)
    for (k in ENSO_LABEL_LEVELS) {
      row[[paste0("n_", k)]] <- pick("n", k)
      row[[paste0("mean_", k)]] <- pick("mean", k)
    }
    row$diff_el_nino <- pick("diff_neutral", "el_nino")
    row$diff_la_nina <- pick("diff_neutral", "la_nina")
    tibble::as_tibble(row)
  })
  out <- tibble::as_tibble(do.call(rbind, out))
  out[order(match(out$series, .step2_scenario_order(out$series))), , drop = FALSE]
}

# A number for a table cell: "-" for NA; a plus sign on positive values only when they do not round to 0.
.enso_fmt <- function(v, scale = 1, digits = 3L, sign = FALSE) {
  if (is.na(v)) return("-")
  txt <- formatC(v * scale, digits = digits, format = "f", big.mark = ",")
  if (sign && v > 0 && as.numeric(gsub(",", "", txt)) != 0) paste0("+", txt) else sub("^-(0(\\.0*)?)$", "\\1", txt)
}

#' Reactable of the phase comparison (item 3)
#'
#' @param tbl Tibble from `enso_series_table()`.
#' @param scale 100 for rates shown as percent, else 1 (the means and differences are scaled).
#' @param digits Decimals shown.
#' @noRd
enso_phase_reactable <- function(tbl, scale = 1, digits = 3L) {
  num <- function(header) {
    reactable::colDef(
      name = header, align = "right", minWidth = 80, class = "wise-dt-wrap",
      cell = function(v) .enso_fmt(v, scale, digits)
    )
  }
  cnt <- function(header) reactable::colDef(name = header, align = "right", minWidth = 50)
  diff <- function(header) {
    reactable::colDef(
      name = header, align = "right", minWidth = 90,
      cell = function(v) .enso_fmt(v, scale, digits, sign = TRUE)
    )
  }
  reactable::reactable(
    tbl,
    columns = list(
      series = reactable::colDef(name = "Series", minWidth = 170, class = "wise-dt-wrap"),
      n_el_nino = cnt("Years"), mean_el_nino = num("Mean"), diff_el_nino = diff("vs Neutral"),
      n_neutral = cnt("Years"), mean_neutral = num("Mean"),
      n_la_nina = cnt("Years"), mean_la_nina = num("Mean"), diff_la_nina = diff("vs Neutral"),
      n_mixed = cnt("Years"), mean_mixed = reactable::colDef(show = FALSE)
    ),
    columnGroups = list(
      reactable::colGroup("El Ni\u00f1o exposure", c("n_el_nino", "mean_el_nino", "diff_el_nino")),
      reactable::colGroup("Neutral", c("n_neutral", "mean_neutral")),
      reactable::colGroup("La Ni\u00f1a exposure", c("n_la_nina", "mean_la_nina", "diff_la_nina")),
      reactable::colGroup("Mixed", c("n_mixed", "mean_mixed"))
    ),
    compact = TRUE, highlight = TRUE, pagination = FALSE
  )
}

#' Sentence on how many El Nino and La Nina exposure years a window holds (D8)
#'
#' @param labels Tibble from `enso_year_labels()`.
#' @noRd
enso_count_sentence <- function(labels) {
  lab <- labels$label[!is.na(labels$label)]
  n_en <- sum(lab == "el_nino")
  paste0(
    "This window has ", n_en, " El Ni\u00f1o and ", sum(lab == "la_nina"), " La Ni\u00f1a exposure years out of ",
    length(lab), ".", if (n_en < 10L) " A longer historical window adds more events, and also moves the baseline."
  )
}

#' Sentence on how many of the most adverse years are El Nino years (item 3)
#'
#' Looks at the `k` most adverse years of one series, about a fifth of its years and at least
#' three. Counts only; no test (D5). `NULL` when the series has fewer than five labelled years or
#' no El Nino year.
#'
#' @param labels Tibble from `enso_year_labels()`.
#' @param values Data frame with `sim_year` and `value` (one row per year).
#' @param adverse_tail `"low"` when low values are adverse, `"high"` when high values are.
#' @noRd
enso_adverse_sentence <- function(labels, values, adverse_tail = "low") {
  d <- merge(values[c("sim_year", "value")], labels[c("sim_year", "label")], by = "sim_year")
  d <- d[!is.na(d$label) & is.finite(d$value), , drop = FALSE]
  n <- nrow(d)
  n_en <- sum(d$label == "el_nino")
  if (n < 5L || n_en == 0L) return(NULL)
  k <- max(3L, as.integer(round(n / 5)))
  worst <- d[order(d$value, decreasing = identical(adverse_tail, "high")), , drop = FALSE][seq_len(k), ]
  sprintf(
    "%d of the %d most adverse years have El Ni\u00f1o exposure; %d of %d years do.",
    sum(worst$label == "el_nino"), k, n_en, n
  )
}

#' Interview-month weights of a baseline survey
#'
#' @param svy Baseline survey-weather frame (`int_month` or `timestamp`, and `weight`).
#' @return Length-12 vector from `enso_month_weights()`; `NA`s when the frame has no months.
#' @noRd
enso_baseline_months <- function(svy) {
  col <- intersect(c("int_month", "timestamp"), names(svy))
  if (!is.data.frame(svy) || !length(col)) return(rep(NA_real_, 12L))
  w <- survey_weight_column(names(svy))
  enso_month_weights(svy[[col[[1L]]]], if (!is.null(w)) svy[[w]])
}

# Wording of the marked draws (the note below the distribution charts).
.ENSO_NOTE_MARKS <- paste(
  "ENSO phase marks a draw as El Ni\u00f1o or La Ni\u00f1a; unmarked draws are Neutral or Mixed. A simulated weather year is a",
  "composite of the months that enter the model for each household, so it is marked when at least half of that",
  "exposure falls in the phase. Climate scenarios take the phase of their template year, and the Historical draws of the",
  "target months are classified the same way from the target months and the fitted lags. The phase of each month is",
  "from the relative Ni\u00f1o 3.4 index (RONI)."
)
.ENSO_NOTE_MARKS_FORECAST <- paste(
  "Forecast members share one state: the phase of at least half of the target months in the ENSO forecast (RONI",
  "outlook), or in the observed record when the forecast does not cover them."
)

#' Note on how the marked draws are classified
#' @param forecast Add the sentence on the forecast members.
#' @noRd
enso_mark_note_ui <- function(forecast = FALSE) {
  shiny::tags$p(
    class = "text-muted small", style = "margin-top: 6px; margin-bottom: 0;",
    .ENSO_NOTE_MARKS, if (isTRUE(forecast)) .ENSO_NOTE_MARKS_FORECAST
  )
}

#' Toggle that marks the El Nino and La Nina draws, with its label in line
#' @param ns Namespace function of the module.
#' @noRd
enso_mark_toggle_ui <- function(ns) {
  shiny::div(
    style = "display: flex; align-items: center; gap: 8px;",
    shiny::tags$span(class = "control-label", style = "margin: 0; font-weight: 600;", "ENSO phase"),
    pill_toggle(
      ns("enso_mark"),
      label = NULL,
      aria_label = "Mark draws by ENSO phase",
      choices = c("Off" = "off", "On" = "on"),
      selected = "off",
      layout = "horizontal"
    )
  )
}

#' ENSO phase chip for the interview months of one wave
#'
#' One month gives its phase and RONI. `"all"` counts the months of the wave by phase. El Nino and La Nina carry
#' the same mark as the legend, so the phase never rests on colour alone.
#'
#' @param months Rows of `enso_interview_months()` for the wave (`month_num`, `phase`, `roni`).
#' @param month `"all"`, or the interview month number as text.
#' @return A `shiny` tag, or `NULL` when the ENSO record does not cover the month.
#' @noRd
enso_month_chip_ui <- function(months, month = "all") {
  if (is.null(months) || !nrow(months)) return(NULL)
  mark <- function(k) {
    if (!k %in% names(ENSO_MARKS)) return(NULL)
    shiny::span(
      style = paste0("color:", ENSO_MARKS[[k]]$color, "; text-shadow: 0 0 1px #243746, 0 0 1px #243746;"),
      `aria-hidden` = "true", paste0(if (k == "el_nino") "\u25B2" else "\u25C6", " ")
    )
  }
  if (!identical(month, "all")) {
    m <- months[months$month_num == as.integer(month), , drop = FALSE]
    if (!nrow(m)) return(NULL)
    body <- list(mark(m$phase), paste0(enso_label_text(m$phase), ", RONI ", format(round(m$roni, 2), nsmall = 2)))
  } else {
    n <- table(factor(months$phase, levels = c("el_nino", "neutral", "la_nina")))
    n <- n[n > 0L]
    body <- list("ENSO: ")
    for (k in names(n)) body <- c(body, list(mark(k), paste0(n[[k]], " ", enso_label_text(k), "  ")))
    body <- c(body, list("months"))
  }
  shiny::span(class = "text-muted small", title = "ENSO phase of the interview month, from RONI", body)
}

#' Legend of the marked draws on the distribution charts
#' @noRd
enso_legend_ui <- function() {
  item <- function(k, text) {
    shiny::span(
      style = "margin-left: 14px;",
      shiny::span(
        style = paste0("color:", ENSO_MARKS[[k]]$color, "; text-shadow: 0 0 1px #243746, 0 0 1px #243746;"),
        `aria-hidden` = "true", if (k == "el_nino") "\u25B2" else "\u25C6"
      ),
      " ", text
    )
  }
  shiny::div(
    class = "text-muted small", style = "text-align: right; margin-bottom: 4px;",
    item("el_nino", "El Ni\u00f1o"), item("la_nina", "La Ni\u00f1a")
  )
}


# Policy comparison by ENSO label (item 4) ----

#' Baseline, policy and policy effect by ENSO label
#'
#' One row per series and label. Each series is averaged over its climate models by simulation
#' year first, so a year counts once, then over the years of the label. The effect is policy minus
#' baseline; `effect_vs_neutral` is the difference of the effect from its Neutral mean, shown only
#' for El Nino and La Nina and only when both sides have `min_n` years (D5). Counts and means only.
#'
#' @param paired Data frame with `scenario`, `sim_year`, `baseline`, `policy`, `effect` (the
#'   model-year pairs of `paired_model_year_effects()`, one `scenario` column added);
#'   forecast-like series are left out.
#' @param labels Tibble from `enso_year_labels()`.
#' @param min_n Smallest number of years in a phase to compare it.
#' @return Tibble: `series`, `label`, `n`, `baseline`, `policy`, `effect`, `effect_vs_neutral`;
#'   `NULL` when nothing is left.
#' @noRd
enso_policy_table <- function(paired, labels, min_n = 3L) {
  if (is.null(paired) || !nrow(paired)) return(NULL)
  order_of <- unique(as.character(paired$scenario))
  paired <- paired[!.step2_is_forecast_like(paired$scenario), , drop = FALSE]
  paired <- paired[is.finite(paired$baseline) & is.finite(paired$policy) & is.finite(paired$effect), ,
    drop = FALSE]
  if (!nrow(paired)) return(NULL)
  yearly <- stats::aggregate(
    cbind(baseline, policy, effect) ~ scenario + sim_year, data = paired, FUN = mean
  )
  yearly$scenario <- as.character(yearly$scenario)
  yearly$label <- labels$label[match(as.integer(yearly$sim_year), labels$sim_year)]
  yearly <- yearly[!is.na(yearly$label), , drop = FALSE]
  if (!nrow(yearly)) return(NULL)
  rows <- lapply(intersect(order_of, unique(yearly$scenario)), function(s) {
    d <- yearly[yearly$scenario == s, , drop = FALSE]
    n <- vapply(ENSO_LABEL_LEVELS, function(k) sum(d$label == k), numeric(1))
    m <- function(col) {
      vapply(ENSO_LABEL_LEVELS, function(k) if (any(d$label == k)) mean(d[[col]][d$label == k]) else NA_real_,
        numeric(1), USE.NAMES = FALSE)
    }
    eff <- m("effect")
    names(eff) <- ENSO_LABEL_LEVELS
    comparable <- n >= min_n & n[["neutral"]] >= min_n & ENSO_LABEL_LEVELS %in% c("el_nino", "la_nina")
    tibble::tibble(
      series = s, label = ENSO_LABEL_LEVELS, n = as.integer(n), baseline = m("baseline"),
      policy = m("policy"), effect = unname(eff),
      effect_vs_neutral = unname(ifelse(comparable, eff - eff[["neutral"]], NA_real_))
    )[n > 0, ]
  })
  do.call(rbind, rows)
}

#' Reactable of the policy comparison by ENSO label (item 4)
#'
#' @param tbl Tibble from `enso_policy_table()`.
#' @param scale 100 for rates shown as percent, else 1.
#' @param digits Decimals shown.
#' @noRd
enso_policy_reactable <- function(tbl, scale = 1, digits = 3L) {
  tbl$exposure <- enso_label_text(tbl$label)
  tbl <- tbl[c("series", "exposure", "n", "baseline", "policy", "effect", "effect_vs_neutral")]
  fmt <- function(v, sign = FALSE) .enso_fmt(v, scale, digits, sign)
  reactable::reactable(
    tbl,
    columns = list(
      series = reactable::colDef(name = "Series", minWidth = 170, class = "wise-dt-wrap"),
      exposure = reactable::colDef(name = "Exposure", minWidth = 90),
      n = reactable::colDef(name = "Years", align = "right", minWidth = 50),
      baseline = reactable::colDef(name = "Baseline mean", align = "right", minWidth = 90,
        cell = function(v) fmt(v)),
      policy = reactable::colDef(name = "Policy mean", align = "right", minWidth = 90,
        cell = function(v) fmt(v)),
      effect = reactable::colDef(name = "Policy effect", align = "right", minWidth = 90,
        cell = function(v) fmt(v, TRUE)),
      effect_vs_neutral = reactable::colDef(name = "Effect vs Neutral", align = "right", minWidth = 100,
        cell = function(v) fmt(v, TRUE))
    ),
    compact = TRUE, highlight = TRUE, pagination = FALSE
  )
}

#' Sentence on the policy effect in El Nino and Neutral years of one series (item 4)
#'
#' `NULL` unless the series has at least `min_n` El Nino and Neutral years. Counts and means only.
#'
#' @param tbl Tibble from `enso_policy_table()`.
#' @param series Series to describe.
#' @param scale,digits As for `enso_policy_reactable()`.
#' @noRd
enso_policy_sentence <- function(tbl, series, scale = 1, digits = 3L, min_n = 3L) {
  d <- tbl[tbl$series == series, , drop = FALSE]
  en <- d[d$label == "el_nino", , drop = FALSE]
  ne <- d[d$label == "neutral", , drop = FALSE]
  if (!nrow(en) || !nrow(ne) || en$n < min_n || ne$n < min_n) return(NULL)
  f <- function(v) formatC(v * scale, digits = digits, format = "f", big.mark = ",")
  sprintf(
    "In %d El Ni\u00f1o exposure years the policy changes the outcome by %s on average, against %s in %d Neutral years.",
    en$n, f(en$effect), f(ne$effect), ne$n
  )
}


# Weather support by ENSO label (item 6) ----

#' Share of weather outside the fitted support in El Nino and La Nina years
#'
#' Uses the support of `weather_support_reference()` (the robust 1st to 99th percentile of the
#' fitted sample's weather) and `weather_support_scenario()` on the rows of each series whose
#' simulation year carries the label. A phase with fewer than `min_years` years in a series is left
#' out (D5); `"all"` gives the share over every labelled-or-not year, for comparison.
#'
#' @param reference Data frame of the fitted sample's weather (column `variable`).
#' @param series Named list of data frames with `variable` and `sim_year` columns.
#' @param variable Weather variable name.
#' @param labels Tibble from `enso_year_labels()`.
#' @param min_years Smallest number of years of a phase to report it.
#' @param weather_specs Selected weather (`name`, `cont_binned`), so a binned variable is checked on
#'   its bins as the Diagnostics support check does; `NULL` treats every variable as continuous.
#' @return Tibble: `scenario`, `phase` (`"el_nino"`, `"la_nina"`, `"all"`), `n_years`, `n_values`,
#'   `outside_share`, `is_binned`; zero rows when the reference or the variable is unusable.
#' @noRd
weather_support_by_phase <- function(reference, series, variable, labels, min_years = 3L,
                                     weather_specs = NULL) {
  out <- tibble::tibble(
    scenario = character(), phase = character(), n_years = integer(), n_values = integer(),
    outside_share = numeric(), is_binned = logical()
  )
  ref <- weather_support_reference(reference, variable, weather_specs = weather_specs)
  if (!length(ref) || !is.list(series)) return(out)
  ref <- ref[[1L]]
  rows <- list()
  for (nm in names(series)) {
    d <- series[[nm]]
    if (!is.data.frame(d) || !all(c(variable, "sim_year") %in% names(d))) next
    lab <- labels$label[match(as.integer(d$sim_year), labels$sim_year)]
    for (k in c("el_nino", "la_nina", "all")) {
      keep <- if (identical(k, "all")) rep(TRUE, nrow(d)) else !is.na(lab) & lab == k
      n_years <- length(unique(d$sim_year[keep]))
      if (!identical(k, "all") && n_years < min_years) next
      s <- weather_support_scenario(ref, d[[variable]][keep], nm)
      if (is.null(s)) next
      rows[[length(rows) + 1L]] <- tibble::tibble(
        scenario = nm, phase = k, n_years = as.integer(n_years), n_values = as.integer(s$n_scenario),
        outside_share = s$outside_share, is_binned = s$is_binned
      )
    }
  }
  if (length(rows)) do.call(rbind, rows) else out
}

#' One sentence per series on weather outside the fitted support by ENSO label (item 6)
#'
#' @param tbl Tibble from `weather_support_by_phase()`.
#' @param label Display name of the weather variable.
#' @return Character vector, one sentence per series with an El Nino or La Nina row.
#' @noRd
enso_support_sentences <- function(tbl, label) {
  pct <- function(x) paste0(format(round(100 * x, 1), nsmall = 1, trim = TRUE), "%")
  out <- character(0)
  for (s in unique(tbl$scenario)) {
    d <- tbl[tbl$scenario == s, , drop = FALSE]
    parts <- character(0)
    for (k in c("el_nino", "la_nina")) {
      r <- d[d$phase == k, , drop = FALSE]
      if (nrow(r)) parts <- c(parts, sprintf("%s in %s exposure years (%d)", pct(r$outside_share), enso_label_text(k), r$n_years))
    }
    if (!length(parts)) next
    all_row <- d[d$phase == "all", , drop = FALSE]
    where <- if ("is_binned" %in% names(d) && isTRUE(d$is_binned[[1L]])) "in bins the fitted sample lacks" else "outside the fitted range"
    out <- c(out, sprintf(
      "%s, %s %s: %s%s.", s, tolower(label), where, paste(parts, collapse = ", "),
      if (nrow(all_row)) paste0("; ", pct(all_row$outside_share), " in all years") else ""
    ))
  }
  out
}


# Is ENSO relevant to this weather? (second version) ----

#' Rank correlation of each location's yearly weather with the exposure RONI
#'
#' The weather rows are the fitted sample's own (`.filter_hist_weather()`), so a value is the predictor the model
#' sees for that location, interview month and calendar year, and a year's exposure RONI is the one of
#' `enso_year_labels()`. Per location, each year's mean over the interview months is ranked against the exposure
#' RONI (Spearman) across the years; the result is the median over locations, so a national average cannot hide
#' opposite local signals. A location needs `min_years` years with variation in both series.
#'
#' @param weather Data frame with `loc_id`, `cal_year` and the weather variables.
#' @param labels Tibble from `enso_year_labels()` (`sim_year`, `roni_exp`).
#' @param variables Weather variable names; non-numeric columns are skipped.
#' @param min_years Smallest number of years for a location.
#' @return Tibble: `variable`, `n_years`, `n_locations`, `rho` (median, signed) and `abs_rho` (median of the
#'   absolute values); zero rows when nothing can be computed.
#' @noRd
enso_weather_relevance <- function(weather, labels, variables, min_years = 8L) {
  out <- tibble::tibble(
    variable = character(), n_years = integer(), n_locations = integer(), rho = numeric(), abs_rho = numeric()
  )
  if (!is.data.frame(weather) || is.null(labels) || !all(c("loc_id", "cal_year") %in% names(weather))) return(out)
  rows <- list()
  for (v in intersect(variables, names(weather))) {
    x <- weather[[v]]
    if (!is.numeric(x)) next
    r <- labels$roni_exp[match(as.integer(weather$cal_year), labels$sim_year)]
    ok <- is.finite(x) & is.finite(r)
    if (!any(ok)) next
    d <- data.frame(loc = weather$loc_id[ok], yr = weather$cal_year[ok], x = x[ok])
    ly <- stats::aggregate(x ~ loc + yr, data = d, FUN = mean)
    ly$r <- labels$roni_exp[match(as.integer(ly$yr), labels$sim_year)]
    rho <- vapply(split(ly, ly$loc), function(g) {
      if (nrow(g) < min_years || stats::sd(g$x) == 0 || stats::sd(g$r) == 0) return(NA_real_)
      suppressWarnings(stats::cor(g$x, g$r, method = "spearman"))
    }, numeric(1))
    rho <- rho[is.finite(rho)]
    if (!length(rho)) next
    rows[[length(rows) + 1L]] <- tibble::tibble(
      variable = v, n_years = length(unique(ly$yr)), n_locations = length(rho),
      rho = stats::median(rho), abs_rho = stats::median(abs(rho))
    )
  }
  if (length(rows)) do.call(rbind, rows) else out
}

#' Sentence on how closely the weather follows ENSO
#'
#' Words follow the median absolute correlation: below 0.2 "barely", below 0.4 "weakly", below 0.6 "moderately",
#' else "strongly". When every variable is barely related, the sentence adds that small differences between
#' phases are expected whatever the welfare response, so a flat result is not read as "ENSO does not matter".
#'
#' @param tbl Tibble from `enso_weather_relevance()`.
#' @param label_map Optional named character vector, variable name to display label.
#' @return A character vector of length 0 or 1.
#' @noRd
enso_relevance_sentences <- function(tbl, label_map = NULL) {
  if (is.null(tbl) || !nrow(tbl)) return(character(0))
  word <- function(a) if (a < 0.2) "barely" else if (a < 0.4) "weakly" else if (a < 0.6) "moderately" else "strongly"
  name <- ifelse(tbl$variable %in% names(label_map), label_map[tbl$variable], tbl$variable)
  parts <- sprintf("%s %s follows ENSO (r = %.2f)", name, vapply(tbl$abs_rho, word, character(1)), tbl$rho)
  paste0(
    "Weather and ENSO: ", paste(parts, collapse = "; "), ". r is the rank correlation of a location's yearly ",
    "weather with exposure RONI across ", max(tbl$n_years), " years, the median over ", max(tbl$n_locations),
    " locations.",
    if (all(tbl$abs_rho < 0.2)) {
      " With weather this far from ENSO, small differences between phases are expected whatever the welfare response."
    }
  )
}


# ENSO phase of the months of the forecast flyout strip ----

#' Phase marks for the month strip of the forecast flyout
#'
#' The observed record for past months and the outlook of the run (its own system, else the multi-model mean) for
#' the forecast months, through `enso_forecast_outlook()`. Months without a phase get no row.
#'
#' @param enso List from `enso_load()`, or `NULL`.
#' @param months Data frame from `.step2_forecast_months()` (`month`).
#' @param run One forecast run (`init`, `model_id`).
#' @return `NULL`, or a data frame: `value` ("YYYY-MM"), `phase` and `text` (phase, RONI and where it comes from).
#' @noRd
enso_strip_marks <- function(enso, months, run) {
  if (is.null(enso) || is.null(months) || !nrow(months)) return(NULL)
  out <- tryCatch(
    enso_forecast_outlook(enso, months$month, run$init, .enso_run_system(run)),
    error = function(e) NULL
  )
  if (is.null(out) || !nrow(out)) return(NULL)
  out <- out[!is.na(out$phase) & is.finite(out$roni), , drop = FALSE]
  if (!nrow(out)) return(NULL)
  obs <- enso$observed$source[match(.enso_month_key(out$month), .enso_month_key(enso$observed$month))]
  where <- ifelse(
    out$basis == "forecast", ifelse(out$source == "multimodel", "multi-model forecast", "forecast"),
    ifelse(obs %in% "cpc", "observed, CPC", ifelse(obs %in% "era5", "observed, ERA5", "later outlook"))
  )
  data.frame(
    value = format(out$month, "%Y-%m"), phase = out$phase,
    text = paste0(enso_label_text(out$phase), ", RONI ", formatC(out$roni, digits = 2L, format = "f"), " (", where, ")"),
    stringsAsFactors = FALSE
  )
}


# Exports and batch (item 8) ----

#' Version of the ENSO tables behind a result
#'
#' `enso.csv` history is not frozen, so a number needs its table version. The hash is of the
#' validated tables, which read the same from every data source. Not part of any run signature
#' or of the batch `metadata_digest` (D1).
#'
#' @param enso List from `enso_load()`, or `NULL`.
#' @return `NULL`, or a list: `enso_observed_sha256`, `enso_forecast_sha256`, `enso_last_cpc_month`
#'   (`YYYY-MM`) and `enso_forecast_init_date`; `NA` where a table or month is missing.
#' @noRd
enso_provenance <- function(enso) {
  if (is.null(enso)) return(NULL)
  cpc <- enso$observed$month[enso$observed$source %in% "cpc"]
  list(
    enso_observed_sha256 = digest::digest(enso$observed, algo = "sha256"),
    enso_forecast_sha256 = if (is.null(enso$forecast)) NA_character_ else digest::digest(enso$forecast, algo = "sha256"),
    enso_last_cpc_month = if (length(cpc)) format(max(cpc), "%Y-%m") else NA_character_,
    enso_forecast_init_date = if (is.null(enso$forecast)) NA_character_ else format(max(enso$forecast$init_date))
  )
}

#' The labels of one run as one table
#'
#' A climate scenario carries the label of its template year, so `annual` covers it. Forecast
#' members have no label (D3).
#'
#' @param labels Tibble from `enso_year_labels()`.
#' @param window_labels Tibble from `enso_window_labels()`, or `NULL`.
#' @return Tibble: `sample` (`annual`, `target_months`), `sim_year`, `el_nino`, `neutral`,
#'   `la_nina`, `roni_exp`, `label`, `period` (`NA` for `annual`).
#' @noRd
enso_year_table <- function(labels, window_labels = NULL) {
  annual <- tibble::add_column(labels, sample = "annual", .before = 1L)
  annual$period <- NA_character_
  if (is.null(window_labels)) return(annual)
  rbind(annual, tibble::add_column(window_labels, sample = "target_months", .before = 1L))
}

#' The outlook of a forecast run as one table, with the card's comparison
#'
#' @param text Result of `enso_placement_text()`, or `NULL`.
#' @return `NULL`, or the `outlook` tibble with `outlook_phase`, `n_phase_years`, `n_phase_adverse`,
#'   `n_years`, `n_adverse` (`NA` when the comparison is hidden) and `card_line`.
#' @noRd
enso_outlook_table <- function(text) {
  if (is.null(text)) return(NULL)
  out <- text$outlook
  count <- function(x) x %||% NA_integer_
  out$outlook_phase <- text$phase
  out$n_phase_years <- count(text$compare$n)
  out$n_phase_adverse <- count(text$compare$n_adverse)
  out$n_years <- count(text$compare$n_all)
  out$n_adverse <- count(text$compare$n_adverse_all)
  out$card_line <- text$line
  out
}

# Rows of the batch `summary` table, in its long form.
.enso_summary_rows <- function(scenario, metric, measure, group = NA_character_, estimate = NA_real_,
                               n = NA_real_, text = NA_character_) {
  k <- max(lengths(list(measure, group, estimate, n, text)))
  data.frame(
    scenario = scenario, metric = as.character(metric), section = "enso", measure = rep_len(measure, k),
    group = rep_len(as.character(group), k), return_period = NA_character_,
    estimate = rep_len(as.numeric(estimate), k), lo = NA_real_, hi = NA_real_, n = rep_len(as.numeric(n), k),
    text = rep_len(as.character(text), k), stringsAsFactors = FALSE
  )
}

#' The `enso` rows of `summary` for one metric of the annual series
#'
#' @param tbl Tibble from `enso_series_table()`.
#' @param metric Metric of the rows.
#' @noRd
enso_annual_summary <- function(tbl, metric) {
  rows <- lapply(seq_len(nrow(tbl)), function(i) {
    r <- tbl[i, , drop = FALSE]
    n <- unlist(r[paste0("n_", ENSO_LABEL_LEVELS)], use.names = FALSE)
    rbind(
      .enso_summary_rows(
        r$series, metric, "mean", ENSO_LABEL_LEVELS, unlist(r[paste0("mean_", ENSO_LABEL_LEVELS)], use.names = FALSE), n
      ),
      .enso_summary_rows(
        r$series, metric, "diff_neutral", c("el_nino", "la_nina"), c(r$diff_el_nino, r$diff_la_nina),
        c(r$n_el_nino, r$n_la_nina)
      )
    )
  })
  do.call(rbind, rows)
}

#' The `enso` rows of `summary` for a forecast scenario
#'
#' @param text Result of `enso_placement_text()`.
#' @param scenario Forecast scenario label.
#' @param metric Metric of the comparison.
#' @param outlook Also write the rows of the outlook, which do not depend on the metric.
#' @noRd
enso_forecast_summary <- function(text, scenario, metric, outlook = FALSE) {
  cmp <- text$compare
  rows <- list(
    .enso_summary_rows(scenario, metric, "card_line", text = text$line),
    if (!is.null(cmp)) {
      .enso_summary_rows(
        scenario, metric, c("reference_adverse", "reference_adverse_all"), c(text$phase, "all"),
        c(cmp$n_adverse, cmp$n_adverse_all), c(cmp$n, cmp$n_all)
      )
    }
  )
  if (isTRUE(outlook)) {
    o <- text$outlook
    month <- format(o$month, "%Y-%m")
    rows <- c(rows, list(
      .enso_summary_rows(scenario, NA_character_, "outlook_roni", month, o$roni, text = o$phase),
      .enso_summary_rows(scenario, NA_character_, "outlook_prob_el_nino", month, o$prob_el_nino),
      .enso_summary_rows(scenario, NA_character_, "outlook_prob_la_nina", month, o$prob_la_nina),
      .enso_summary_rows(scenario, NA_character_, "outlook_prob_neutral", month, o$prob_neutral),
      .enso_summary_rows(scenario, NA_character_, "outlook_basis", month, text = ifelse(is.na(o$source), o$basis, o$source))
    ))
  }
  do.call(rbind, rows)
}

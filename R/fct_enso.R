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

# A share within this distance of the threshold counts as reaching it. It absorbs
# floating-point sums such as 0.1 + 0.2 + 0.2 and is far below any real share step.
.ENSO_SHARE_TOL <- 1e-9


# Loading and validation (D6) ----

#' Soft loader for the observed and forecast ENSO tables
#'
#' Reads `metadata/enso.csv` and `metadata/enso_forecast.csv` through `load_data()`, which
#' covers the local, cloud and Databricks sources. Both tables are optional: a missing,
#' empty or malformed observed table returns `NULL`; a missing or malformed forecast table
#' only leaves `forecast` as `NULL`. Never signals an error or a warning.
#'
#' @param connection_params Named connection parameter list, as for `load_data()`.
#' @return `NULL`, or a list with `observed` (tibble: `month`, `source`, `roni`, `phase`,
#'   one row per consecutive month, sorted) and `forecast` (tibble or `NULL`).
#' @noRd
enso_load <- function(connection_params = list(type = "local", path = .default_data_path())) {
  read_one <- function(file) {
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
  months <- as.integer(months)
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


# Coverage of the survey sample ----

#' Phase of the interview months of a sample
#'
#' Household shares by the ENSO phase of the interview month, and the highest RONI at any
#' interview. Computed from interview dates, not from month numbers, so each wave is placed
#' in its own year. Interviews outside the table are counted in `n_missing`.
#'
#' @param enso Observed table from `enso_load()$observed`.
#' @param dates Interview dates (`Date` or `POSIXt`), one per household.
#' @param weights Optional household weights; unweighted when `NULL`.
#' @param group Optional vector (for example the survey wave) to summarise by.
#' @return Tibble: `group`, `n`, `n_missing`, `el_nino`, `neutral`, `la_nina` (shares),
#'   `max_roni`.
#' @noRd
enso_sample_coverage <- function(enso, dates, weights = NULL, group = NULL) {
  n <- length(dates)
  weights <- if (is.null(weights)) rep(1, n) else as.numeric(weights)
  group <- if (is.null(group)) rep("all", n) else as.character(group)
  ok_date <- !is.na(dates)
  pos <- rep(NA_integer_, n)
  pos[ok_date] <- match(.enso_month_key(as.Date(dates[ok_date])), .enso_month_key(enso$month))
  rows <- lapply(unique(group), function(g) {
    i <- group == g & !is.na(weights) & weights > 0
    hit <- i & !is.na(pos)
    total <- sum(weights[hit])
    share <- function(k) if (total > 0) sum(weights[hit & enso$phase[pos] %in% k]) / total else NA_real_
    tibble::tibble(
      group = g, n = sum(hit), n_missing = sum(i & is.na(pos)),
      el_nino = share("el_nino"), neutral = share("neutral"), la_nina = share("la_nina"),
      max_roni = if (any(hit)) max(enso$roni[pos[hit]]) else NA_real_
    )
  })
  do.call(rbind, rows)
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

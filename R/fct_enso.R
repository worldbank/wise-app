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

#' One sentence per survey wave on the ENSO phase of its interviews (item 1)
#'
#' Information, not a warning. Waves with no interview inside the ENSO record are left out.
#'
#' @param coverage Tibble from `enso_sample_coverage()`.
#' @param wave_labels Optional named character vector replacing the `group` text.
#' @return Character vector, one sentence per wave.
#' @noRd
enso_coverage_sentences <- function(coverage, wave_labels = NULL) {
  if (is.null(coverage) || !nrow(coverage)) return(character(0))
  coverage <- coverage[coverage$n > 0L, , drop = FALSE]
  vapply(seq_len(nrow(coverage)), function(i) {
    g <- coverage$group[[i]]
    wave <- if (!is.null(wave_labels) && g %in% names(wave_labels)) wave_labels[[g]] else g
    pct <- function(x) paste0(format(round(100 * x), trim = TRUE), "%")
    paste0(
      wave, ": ", pct(coverage$el_nino[[i]]), " of households were interviewed in El Ni\u00f1o months, ",
      pct(coverage$la_nina[[i]]), " in La Ni\u00f1a and ", pct(coverage$neutral[[i]]),
      " in neutral months. Highest RONI at an interview: ",
      format(round(coverage$max_roni[[i]], 2), nsmall = 2, trim = TRUE), "."
    )
  }, character(1))
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
  curves <- curves[!.step2_is_forecast_like(curves$scenario), , drop = FALSE]
  if (is.null(curves) || !nrow(curves)) return(NULL)
  yearly <- stats::aggregate(
    value ~ scenario + sim_year, data = curves[is.finite(curves$value), , drop = FALSE], FUN = mean
  )
  if (!nrow(yearly)) return(NULL)
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
      cell = function(v) if (is.na(v)) "-" else formatC(v * scale, digits = digits, format = "f", big.mark = ",")
    )
  }
  cnt <- function(header) reactable::colDef(name = header, align = "right", minWidth = 50)
  diff <- function(header) {
    reactable::colDef(
      name = header, align = "right", minWidth = 90,
      cell = function(v) {
        if (is.na(v)) "-" else paste0(if (v > 0) "+" else "", formatC(v * scale, digits = digits, format = "f"))
      }
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
    "Marked draws:", item("el_nino", "El Ni\u00f1o exposure"), item("la_nina", "La Ni\u00f1a exposure")
  )
}

# Step 1 data tables ----
# Tidy tables describing the survey sample and the weather exposure, built for
# the batch pipeline: `variable_stats`, `interview_dates` and `weather_stats`.
# Every statistic the app shows comes from the app's own builders
# (`weighted_summary_long()`, `survey_missingness_long()`,
# `summarise_interview_dates()`, `build_weather_stats_table()`, and the
# weighted quantile rule of `outcome_summary_wide()`); the batch-only
# statistics (location samples, within-location demeaning, indicators,
# deciles for every variable, interview-date totals) sit beside them. All
# functions are Shiny-free. Values are raw, never rounded.

# The deciles use the same probability vector as `outcome_summary_wide()`
# (`seq(0.1, 0.9, 0.1)`, not decimal literals) so the values are identical.
WISEAPP_STAT_PROBS <- c(
  stats::setNames(seq(0.1, 0.9, 0.1), paste0("p", seq(10, 90, 10))),
  p25 = 0.25, p75 = 0.75
)

# Scopes: waves, wave pools, country pools ----

#' Grouping scopes of a survey-like frame
#'
#' Three families of groups: one per survey wave (the app's `countryyear`
#' grouping), one per country over all its waves (`wave = "All"`), and, with
#' several countries, one pool of every country (`code` is the sorted codes
#' joined by `+`).
#'
#' @param df Frame with `code`, `year`, `survname`, `countryyear`.
#' @return A list of lists with `key` (group key per row, `NA` = not in the
#'   family) and `info` (one row per key: `key`, `code`, `wave`, `year`,
#'   `survname`).
#' @noRd
.stat_scopes <- function(df) {
  year <- as.character(df$year)
  code <- as.character(df$code)
  survname <- as.character(df$survname)
  info_for <- function(key, wave_of) {
    ord <- !duplicated(key) & !is.na(key)
    k <- key[ord]
    data.frame(
      key = k,
      code = vapply(k, function(x) paste(sort(unique(code[key %in% x])), collapse = "+"), ""),
      wave = wave_of(k),
      year = vapply(k, function(x) {
        y <- unique(year[key %in% x])
        if (length(y) == 1L) y else NA_character_
      }, ""),
      survname = vapply(k, function(x) paste(sort(unique(survname[key %in% x])), collapse = "+"), ""),
      stringsAsFactors = FALSE,
      row.names = NULL
    )
  }
  wave_key <- as.character(df$countryyear)
  wave_label <- function(k) {
    vapply(k, function(x) paste(unique(year[wave_key %in% x]), collapse = "+"), "")
  }
  scopes <- list(
    wave = list(key = wave_key, info = info_for(wave_key, wave_label)),
    country = list(key = code, info = info_for(code, function(k) rep("All", length(k))))
  )
  if (length(unique(code[!is.na(code)])) > 1L) {
    pool_key <- ifelse(is.na(code), NA_character_, "pool")
    scopes$pool <- list(key = pool_key, info = info_for(pool_key, function(k) rep("All", length(k))))
  }
  scopes
}


# Weighted quantiles ----

#' Weighted quantiles by group, with the outcome summary's rule
#'
#' Rows with a missing value or an invalid weight (not finite and positive)
#' are dropped; `collapse::fquantile(type = 7, w = )` runs per group, exactly
#' as `outcome_summary_wide()` computes its deciles.
#'
#' @param x Numeric vector.
#' @param w Weights.
#' @param group Group key per row (character; `NA` rows are ignored).
#' @return A matrix: one row per group key (rownames), one column per entry of
#'   `WISEAPP_STAT_PROBS`.
#' @noRd
.wtd_quantiles <- function(x, w, group) {
  probs <- WISEAPP_STAT_PROBS
  keys <- unique(group[!is.na(group)])
  out <- matrix(NA_real_, length(keys), length(probs), dimnames = list(keys, names(probs)))
  # fquantile() needs ascending probabilities, so the deciles and the
  # quartiles run as two calls (the decile call matches the outcome summary).
  blocks <- list(1:9, 10:11)
  w_ok <- is.finite(w) & (w > 0)
  ok <- !is.na(x) & w_ok & !is.na(group)
  if (!any(ok)) {
    return(out)
  }
  xv <- as.numeric(x[ok])
  wv <- w[ok]
  gv <- collapse::GRP(group[ok], group.sizes = TRUE)
  gl <- as.character(gv$groups[[1]])
  ord <- order(gv$group.id, method = "radix")
  xs <- xv[ord]
  ws <- wv[ord]
  sz <- gv$group.sizes
  starts <- c(1L, utils::head(cumsum(sz), -1) + 1L)
  for (j in seq_along(gl)) {
    idx <- starts[[j]] + seq_len(sz[[j]]) - 1L
    for (b in blocks) {
      out[gl[[j]], b] <- collapse::fquantile(xs[idx], probs = unname(probs[b]), w = ws[idx], type = 7)
    }
  }
  out
}


# Location samples and within-location values ----

#' Rows with a usable location
#'
#' Batch-only sample split: a record has a location when `loc_id` and, if the
#' frame carries it, `area_h3_7` are present.
#'
#' @param df Survey-like frame.
#' @return Logical vector.
#' @noRd
.has_location <- function(df) {
  has <- !is.na(df[["loc_id"]])
  if ("area_h3_7" %in% names(df)) has <- has & !is.na(df[["area_h3_7"]])
  has
}

#' Location key of a record
#'
#' A location is identified by country and `loc_id`: the same `loc_id` in
#' several waves is the same place, so within-location values deviate from the
#' location's mean over all its waves.
#' @noRd
.location_key <- function(df) {
  paste(df$code, df$loc_id, sep = "|")
}

#' Deviation from the weighted location mean
#'
#' Values are demeaned within each location; invalid values and weights are
#' masked first, like the app's weighted summaries.
#'
#' @param x Numeric vector.
#' @param w Weights.
#' @param loc Location key per row.
#' @return Numeric vector, `NA` where the value or weight is invalid.
#' @noRd
.demean_within <- function(x, w, loc) {
  x <- as.numeric(x)
  valid <- is.finite(x) & is.finite(w) & (w > 0) & !is.na(loc)
  x[!valid] <- NA_real_
  w[!valid] <- NA_real_
  g <- collapse::GRP(loc)
  m <- collapse::fmean(x, g = g, w = w, na.rm = TRUE)
  x - m[g$group.id]
}

#' Mean number of distinct values per location
#'
#' @param x Values.
#' @param loc Location key per row (`NA` rows ignored).
#' @param group Group key per row.
#' @return Named numeric vector, one value per group key.
#' @noRd
.n_unique_per_loc <- function(x, loc, group) {
  ok <- !is.na(x) & !is.na(loc) & !is.na(group)
  keys <- unique(group[!is.na(group)])
  out <- stats::setNames(rep(NA_real_, length(keys)), keys)
  if (!any(ok)) {
    return(out)
  }
  d <- data.frame(group = group[ok], loc = loc[ok], x = x[ok], stringsAsFactors = FALSE)
  per_loc <- collapse::fndistinct(d$x, g = collapse::GRP(d, by = c("group", "loc")))
  gl <- collapse::GRP(d, by = c("group", "loc"))$groups
  m <- tapply(per_loc, gl$group, mean)
  out[names(m)] <- as.numeric(m)
  out
}


# Variable statistics ----

#' Statistics of numeric variables over one grouping
#'
#' One engine for every scope of `variable_stats`: the mean, SD, minimum,
#' maximum, count and unweighted mean come from `weighted_summary_long()` and
#' the missing share from `survey_missingness_long()` (the app's tables);
#' counts, distinct values and the weighted quantiles are added beside them.
#'
#' @param d Frame with the grouping column `.key`, `weight` and the variables.
#' @param vars Character vector of numeric variable names.
#' @param extras Logical; `FALSE` returns the moments only (within-location).
#' @param gini_vars Variables that also get a weighted Gini (`gini` column).
#' @return A data frame keyed by `key` and `variable`.
#' @noRd
.variable_stats_engine <- function(d, vars, extras = TRUE, gini_vars = character(0)) {
  d <- d[!is.na(d$.key), , drop = FALSE]
  vars <- vars[vars %in% names(d)]
  if (!nrow(d) || !length(vars)) {
    return(NULL)
  }
  ws <- weighted_summary_long(d, vars, group = ".key")
  if (!nrow(ws)) {
    return(NULL)
  }
  out <- data.frame(
    key = ws$countryyear, variable = ws$variable, n = ws$N,
    mean = ws$Mean, unweighted_mean = ws$unweighted_mean, sd = ws$`Std. Dev.`,
    min = ws$Min, max = ws$Max, stringsAsFactors = FALSE
  )
  if (!extras) {
    return(out)
  }
  ms <- survey_missingness_long(d, vars, group = ".key")
  out$pct_missing <- ms$`% Missing`[match(
    paste(out$key, out$variable), paste(ms$countryyear, ms$variable)
  )]
  g <- collapse::GRP(d, by = ".key")
  gkey <- as.character(g$groups[[1]])
  n_rows <- stats::setNames(as.integer(tabulate(g$group.id, g$N.groups)), gkey)
  miss <- collapse::fsum(is.na(d[vars]), g = g)
  out$n_rows <- unname(n_rows[out$key])
  out$n_missing <- as.integer(mapply(function(k, v) miss[match(k, gkey), v], out$key, out$variable))
  extra <- lapply(vars, function(v) {
    x <- as.numeric(d[[v]])
    nu <- collapse::fndistinct(x, g = g, na.rm = TRUE)
    q <- .wtd_quantiles(x, d$weight, d$.key)
    res <- data.frame(
      key = gkey, variable = v, n_unique = as.integer(nu),
      q[gkey, , drop = FALSE], row.names = NULL, check.names = FALSE,
      stringsAsFactors = FALSE
    )
    if (v %in% gini_vars) res$gini <- .wtd_gini(x, d$weight, d$.key)[gkey]
    res
  })
  extra <- dplyr::bind_rows(extra)
  merge(out, extra, by = c("key", "variable"), all.x = TRUE, sort = FALSE)
}

#' Weighted Gini per group
#'
#' The app's `gini` aggregate (`resolve_agg_fn("gini")`, the one Step 2 reports)
#' over records with a finite value and a finite positive weight.
#'
#' @param x Numeric values.
#' @param w Weights.
#' @param key Group key per row.
#' @return Named numeric vector, one value per key (`NA` below two records).
#' @noRd
.wtd_gini <- function(x, w, key) {
  gini <- resolve_agg_fn("gini")
  ok <- is.finite(x) & is.finite(w) & w > 0 & !is.na(key)
  idx <- split(which(ok), key[ok])
  out <- vapply(idx, function(i) gini(x[i], w[i], NULL), numeric(1))
  out[unique(key[!is.na(key)])]
}

#' Binary indicator columns from the spec
#'
#' @param df Survey frame.
#' @param indicators Named list; each has `variable`, `operator` (`<` or `>`)
#'   and `threshold`.
#' @return `df` with one 0/1 column per indicator whose variable exists
#'   (`NA` where the variable is missing).
#' @noRd
.add_indicators <- function(df, indicators) {
  present <- character(0)
  for (nm in names(indicators)) {
    ind <- indicators[[nm]]
    if (!ind$variable %in% names(df)) next
    x <- as.numeric(df[[ind$variable]])
    flag <- switch(ind$operator,
      "<" = x < ind$threshold,
      ">" = x > ind$threshold,
      stop("Unsupported indicator operator: ", ind$operator, call. = FALSE)
    )
    df[[nm]] <- as.numeric(flag)
    present <- c(present, nm)
  }
  attr(df, "indicator_vars") <- present
  df
}

#' Variable groups of the survey statistics
#'
#' One row per (group, variable): the variable-list flags (`outcome`, `ind`,
#' `hh`, `firm`, `area`), the selected outcome, the policy variables and the
#' indicator variables.
#'
#' @param variable_list Variable metadata.
#' @param df Frame carrying the variables.
#' @param outcome Name of the selected outcome (added to `outcome`).
#' @param indicator_vars Names of the indicator columns.
#' @return Data frame with `var_group` and `variable`.
#' @noRd
.variable_groups <- function(variable_list, df, outcome = NULL, indicator_vars = character(0)) {
  num <- names(df)[vapply(df, is.numeric, logical(1))]
  pick <- function(flag) {
    if (is.null(variable_list) || !flag %in% names(variable_list)) {
      return(character(0))
    }
    intersect(variable_list$name[variable_list[[flag]] %in% 1], num)
  }
  groups <- list(
    outcome = unique(c(pick("outcome"), intersect(outcome, num))),
    policy = intersect(wise_policy_vars(variable_list), num),
    ind = pick("ind"), hh = pick("hh"), firm = pick("firm"), area = pick("area"),
    indicator = indicator_vars
  )
  do.call(rbind, lapply(names(groups), function(g) {
    if (!length(groups[[g]])) {
      return(NULL)
    }
    data.frame(var_group = g, variable = groups[[g]], stringsAsFactors = FALSE)
  }))
}

#' Variable statistics table
#'
#' One row per wave (and pooled `All` scope) x variable group x variable x
#' sample. The `all` sample reproduces the app's survey and outcome summary
#' tables; `with_loc`, `without_loc` and `within_loc`, the deciles for every
#' variable, the indicator variables and the outcome's `gini` are batch-only.
#'
#' @param df Survey frame with the outcome (`wise_outcome_data()`), with
#'   `countryyear`.
#' @param variable_list Variable metadata.
#' @param outcome Name of the selected outcome.
#' @param indicators Indicator definitions (spec `stats.indicators`).
#' @param location_samples Add the location samples (spec).
#' @return A data frame.
#' @noRd
variable_stats_table <- function(df, variable_list, outcome = NULL,
                                 indicators = list(), location_samples = TRUE) {
  if (is.null(df) || !nrow(df) || !"weight" %in% names(df)) {
    return(NULL)
  }
  if (!"countryyear" %in% names(df)) df$countryyear <- paste0(df$economy, ", ", df$year)
  df <- .add_indicators(df, indicators)
  groups <- .variable_groups(variable_list, df, outcome, attr(df, "indicator_vars"))
  if (is.null(groups)) {
    return(NULL)
  }
  vars <- unique(groups$variable)
  binary <- vars[vapply(vars, function(v) {
    x <- df[[v]]
    x <- x[!is.na(x)]
    length(x) > 0 && all(x %in% c(0, 1))
  }, logical(1))]

  # A Gini only for the outcome variables that are not 0/1.
  gini_vars <- setdiff(groups$variable[groups$var_group == "outcome"], binary)

  scopes <- .stat_scopes(df)
  samples <- list(all = rep(TRUE, nrow(df)))
  if (isTRUE(location_samples) && "loc_id" %in% names(df)) {
    has_loc <- .has_location(df)
    samples$with_loc <- has_loc
    samples$without_loc <- !has_loc
    samples$within_loc <- has_loc
  }

  parts <- list()
  for (sname in names(samples)) {
    rows <- samples[[sname]]
    base <- df[rows, c("weight", vars), drop = FALSE]
    if (identical(sname, "within_loc")) {
      loc <- .location_key(df[rows, , drop = FALSE])
      base[vars] <- lapply(base[vars], function(x) .demean_within(x, base$weight, loc))
    }
    for (fam in scopes) {
      d <- base
      d$.key <- fam$key[rows]
      res <- .variable_stats_engine(d, vars, extras = !identical(sname, "within_loc"), gini_vars = gini_vars)
      if (is.null(res)) next
      info <- fam$info
      res <- cbind(
        info[match(res$key, info$key), c("code", "wave", "year", "survname")],
        res[setdiff(names(res), "key")], sample = sname, row.names = NULL
      )
      parts[[length(parts) + 1L]] <- res
    }
  }
  out <- dplyr::bind_rows(parts)
  if (!nrow(out)) {
    return(NULL)
  }
  out$share_one <- ifelse(out$variable %in% binary & out$sample != "within_loc", out$mean, NA_real_)
  if (!"gini" %in% names(out)) out$gini <- NA_real_
  out <- merge(groups, out, by = "variable", sort = FALSE)
  front <- c("code", "wave", "year", "survname", "var_group", "variable", "sample")
  stats_cols <- c(
    "n", "n_rows", "n_missing", "pct_missing", "n_unique", "mean", "unweighted_mean",
    "sd", "min", "max", names(WISEAPP_STAT_PROBS), "share_one", "gini"
  )
  out <- out[, c(front, stats_cols), drop = FALSE]
  grp_order <- c("outcome", "policy", "hh", "ind", "area", "firm", "indicator")
  out <- out[order(
    out$code, match(out$var_group, grp_order), out$variable, out$sample, out$wave
  ), , drop = FALSE]
  rownames(out) <- NULL
  out
}


# Interview dates ----

#' Interview dates table
#'
#' One row per wave x interview month (the app's chart data from
#' `summarise_interview_dates()`) and one wave-total row (`month = NA`) that
#' adds the batch-only date summary: distinct dates, first and last date, the
#' number of locations of the wave and the average number of distinct dates per
#' location.
#'
#' @param df Survey frame with `countryyear` and `timestamp`.
#' @return A data frame, or `NULL` when there are no dates.
#' @noRd
interview_dates_table <- function(df) {
  if (is.null(df) || !nrow(df)) {
    return(NULL)
  }
  if (!"countryyear" %in% names(df)) df$countryyear <- paste0(df$economy, ", ", df$year)
  monthly <- summarise_interview_dates(df)
  if (!nrow(monthly)) {
    return(NULL)
  }
  info <- .stat_scopes(df)$wave$info
  ok <- !is.na(df$timestamp)
  g <- collapse::GRP(df[ok, , drop = FALSE], by = "countryyear")
  key <- as.character(g$groups[[1]])
  ts <- df$timestamp[ok]
  total <- data.frame(
    countryyear = key,
    month = NA_integer_,
    n = as.integer(collapse::fnobs(ts, g = g)),
    n_dates = as.integer(collapse::fndistinct(ts, g = g)),
    first_date = as.Date(collapse::fmin(as.numeric(ts), g = g), origin = "1970-01-01"),
    last_date = as.Date(collapse::fmax(as.numeric(ts), g = g), origin = "1970-01-01"),
    stringsAsFactors = FALSE
  )
  # Locations of the wave: distinct location keys among records that have one,
  # whether or not they carry an interview date.
  has_loc <- .has_location(df)
  total$n_locations <- NA_integer_
  if (any(has_loc)) {
    gw <- collapse::GRP(df[has_loc, , drop = FALSE], by = "countryyear")
    nl <- collapse::fndistinct(.location_key(df[has_loc, , drop = FALSE]), g = gw)
    total$n_locations <- as.integer(nl[match(total$countryyear, as.character(gw$groups[[1]]))])
    total$n_locations[is.na(total$n_locations)] <- 0L
  }
  has <- has_loc & ok
  total$avg_dates_per_loc <- NA_real_
  if (any(has)) {
    dl <- df[has, , drop = FALSE]
    gl <- collapse::GRP(dl, by = c("countryyear", "survname", "loc_id"))
    nd <- collapse::fndistinct(dl$timestamp, g = gl)
    per_wave <- tapply(nd, gl$groups$countryyear, mean)
    total$avg_dates_per_loc <- as.numeric(per_wave[total$countryyear])
  }
  by_month <- data.frame(
    countryyear = monthly$countryyear, month = as.integer(monthly$month_num),
    n = as.integer(monthly$hh), n_dates = NA_integer_,
    first_date = as.Date(NA), last_date = as.Date(NA), n_locations = NA_integer_,
    avg_dates_per_loc = NA_real_,
    stringsAsFactors = FALSE
  )
  out <- rbind(by_month, total)
  out <- cbind(
    info[match(out$countryyear, info$key), c("code", "wave", "year", "survname")],
    out[setdiff(names(out), "countryyear")], row.names = NULL
  )
  out <- out[order(out$code, out$wave, is.na(out$month), out$month), , drop = FALSE]
  rownames(out) <- NULL
  out
}


# Weather statistics ----

#' Relabel the wave of a survey-weather frame
#'
#' Pools every wave of a frame (or of a country) into one `countryyear` group
#' by overwriting `economy` and `year`, so the app's builder summarises the
#' pool with its own rules.
#' @noRd
.relabel_wave <- function(df, economy, year) {
  df$economy <- economy
  df$year <- year
  df
}

#' Weather statistics of one variable over the survey sample
#'
#' The `all` sample rows come from `build_weather_stats_table()` (the Weather
#' stats tab); deciles, distinct values and the within-location rows are
#' batch-only.
#'
#' @param survey_weather Continuous survey x weather frame.
#' @param sw_row One-row selected weather table.
#' @param survey_data Survey frame (missingness denominators).
#' @return Data frame keyed by `key` (scope key) and `sample`.
#' @noRd
.weather_survey_rows <- function(survey_weather, sw_row, survey_data) {
  sw_df <- survey_weather
  sw_df$year <- as.character(sw_df$year)
  survey_data$year <- as.character(survey_data$year)
  if (!"economy" %in% names(sw_df)) sw_df$economy <- sw_df$code
  sw_df$countryyear <- paste0(sw_df$economy, ", ", sw_df$year)
  sw_df$weight <- as.numeric(sw_df$weight)

  app_rows <- function(d, ref) {
    t <- build_weather_stats_table(function() d, function() sw_row, if (is.null(ref)) NULL else function() ref)
    if (is.null(t)) {
      return(NULL)
    }
    data.frame(
      key = t$`Country, Year`, n = t$N, pct_missing = t$`% Missing`,
      unweighted_mean = t$Unweighted_mean, mean = t$Mean, sd = t$`Std. Dev.`,
      min = t$Min, max = t$Max, stringsAsFactors = FALSE
    )
  }

  rows <- list()
  scopes <- .stat_scopes(sw_df)
  # Wave rows straight from the app builder; country and pool scopes reuse it
  # on a frame whose economy and year are overwritten.
  rows$wave <- app_rows(sw_df, survey_data)
  countries <- unique(sw_df$code)
  rows$country <- dplyr::bind_rows(lapply(countries, function(cd) {
    d <- .relabel_wave(sw_df[sw_df$code == cd, , drop = FALSE], paste0("scope:", cd), "All")
    r <- app_rows(d, .relabel_wave(
      survey_data[survey_data$code == cd, , drop = FALSE], paste0("scope:", cd), "All"
    ))
    if (!is.null(r)) r$key <- cd
    r
  }))
  if (!is.null(scopes$pool)) {
    r <- app_rows(
      .relabel_wave(sw_df, "scope:pool", "All"),
      .relabel_wave(survey_data, "scope:pool", "All")
    )
    if (!is.null(r)) r$key <- "pool"
    rows$pool <- r
  }
  out <- dplyr::bind_rows(rows)
  out$sample <- "all"
  list(rows = out, scopes = scopes, frame = sw_df)
}

#' Deciles, distinct values and within-location statistics for a scope
#'
#' @param x Values.
#' @param w Weights.
#' @param loc Location key per row.
#' @param scopes Output of `.stat_scopes()` for the frame.
#' @return A list of two data frames: `all` (extras keyed by `key`) and
#'   `within` (mean and SD of location-demeaned values).
#' @noRd
.weather_extras <- function(x, w, loc, has_loc, scopes) {
  all_rows <- list()
  within_rows <- list()
  x_loc <- x
  x_loc[!has_loc] <- NA_real_
  x_dm <- .demean_within(x_loc, w, loc)
  for (fam in scopes) {
    key <- fam$key
    q <- .wtd_quantiles(x, w, key)
    in_scope <- !is.na(key)
    g <- collapse::GRP(key[in_scope])
    nu <- stats::setNames(
      as.integer(collapse::fndistinct(x[in_scope], g = g, na.rm = TRUE)),
      as.character(g$groups[[1]])
    )
    npl <- .n_unique_per_loc(x, ifelse(has_loc, loc, NA_character_), key)
    keys <- rownames(q)
    all_rows[[length(all_rows) + 1L]] <- data.frame(
      key = keys, n_unique = unname(nu[keys]), n_unique_per_loc = unname(npl[keys]),
      q, row.names = NULL, check.names = FALSE, stringsAsFactors = FALSE
    )
    d <- data.frame(weight = w, v = x_dm, .key = key)
    d <- d[!is.na(d$.key), , drop = FALSE]
    ws <- weighted_summary_long(d, "v", group = ".key")
    if (nrow(ws)) {
      within_rows[[length(within_rows) + 1L]] <- data.frame(
        key = ws$countryyear, n = ws$N, mean = ws$Mean, sd = ws$`Std. Dev.`,
        stringsAsFactors = FALSE
      )
    }
  }
  list(all = dplyr::bind_rows(all_rows), within = dplyr::bind_rows(within_rows))
}

#' Weather statistics table for one weather variable
#'
#' Survey rows describe the weather the sample was exposed to (continuous
#' values, before any binning); historical rows describe the same locations
#' and calendar months over the historical comparison years, weighted by the
#' households behind each location-month, as in the weather distribution
#' plots.
#'
#' @param survey_weather Continuous survey x weather frame
#'   (`merge_survey_weather()`), with `weight`.
#' @param sw_row One-row selected weather table (`name`, ...).
#' @param survey_data Prepared survey frame.
#' @param hist_cells Historical comparison cells (`join_hist_sample_cells()`).
#' @param hist_years Named integer vector `c(from =, to =)`.
#' @param location_samples Add the within-location rows.
#' @return A data frame.
#' @noRd
weather_stats_table <- function(survey_weather, sw_row, survey_data, hist_cells = NULL,
                                hist_years = NULL, location_samples = TRUE) {
  v <- sw_row$name[1]
  if (is.null(survey_weather) || !v %in% names(survey_weather)) {
    return(NULL)
  }
  parts <- list()

  # Survey rows ----
  sv <- .weather_survey_rows(survey_weather, sw_row, survey_data)
  frame <- sv$frame
  ex <- .weather_extras(
    frame[[v]], frame$weight, .location_key(frame), .has_location(frame), sv$scopes
  )
  all_sv <- merge(sv$rows, ex$all, by = "key", all.x = TRUE, sort = FALSE)
  all_sv$source <- "survey"
  parts[[1]] <- list(rows = all_sv, within = ex$within, scopes = sv$scopes, source = "survey")

  # Historical rows ----
  if (!is.null(hist_cells) && nrow(hist_cells)) {
    h <- hist_cells
    h$year <- as.character(h$year)
    if (!is.null(hist_years)) {
      h <- h[!is.na(h$cal_year) & h$cal_year >= hist_years[["from"]] & h$cal_year <= hist_years[["to"]], ,
        drop = FALSE
      ]
    }
    h <- h[is.finite(h[[v]]), , drop = FALSE]
    if (nrow(h)) {
      h_scopes <- .stat_scopes(h)
      h$.key <- NA_character_
      rows <- lapply(names(h_scopes), function(nm) {
        d <- h
        d$.key <- h_scopes[[nm]]$key
        d <- d[!is.na(d$.key), , drop = FALSE]
        ws <- weighted_summary_long(d, v, group = ".key", weight = "n_hh")
        if (!nrow(ws)) {
          return(NULL)
        }
        data.frame(
          key = ws$countryyear, n = ws$N, pct_missing = NA_real_,
          unweighted_mean = ws$unweighted_mean, mean = ws$Mean, sd = ws$`Std. Dev.`,
          min = ws$Min, max = ws$Max, stringsAsFactors = FALSE
        )
      })
      hist_rows <- dplyr::bind_rows(rows)
      hx <- .weather_extras(
        h[[v]], as.numeric(h$n_hh), .location_key(h), !is.na(h$loc_id), h_scopes
      )
      hist_rows <- merge(hist_rows, hx$all, by = "key", all.x = TRUE, sort = FALSE)
      hist_rows$source <- "historical"
      parts[[2]] <- list(rows = hist_rows, within = hx$within, scopes = h_scopes, source = "historical")
    }
  }

  out <- lapply(parts, function(p) {
    info <- dplyr::bind_rows(lapply(p$scopes, `[[`, "info"))
    rows <- p$rows
    rows$sample <- "all"
    if (isTRUE(location_samples) && nrow(p$within)) {
      w <- p$within
      w$sample <- "within_loc"
      rows <- dplyr::bind_rows(rows, w)
    }
    rows$source <- p$source
    cbind(
      info[match(rows$key, info$key), c("code", "wave", "year", "survname")],
      variable = v, rows[setdiff(names(rows), "key")], row.names = NULL
    )
  })
  out <- dplyr::bind_rows(out)
  front <- c("code", "wave", "year", "survname", "variable", "source", "sample")
  stat_cols <- c(
    "n", "pct_missing", "n_unique", "n_unique_per_loc", "unweighted_mean", "mean", "sd",
    "min", "max", names(WISEAPP_STAT_PROBS)
  )
  for (cn in setdiff(stat_cols, names(out))) out[[cn]] <- NA_real_
  out <- out[, c(front, stat_cols), drop = FALSE]
  out <- out[order(out$code, out$source, out$sample, out$wave), , drop = FALSE]
  rownames(out) <- NULL
  out
}

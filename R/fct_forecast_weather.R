# Seasonal forecast weather construction ----

#' Construct location-month weather for each member of one seasonal run.
#'
#' The run file (draft-2 schema) holds a complete monthly series per member: observed
#' context months, then adjusted forecast months. This builder rolls the fitted
#' predictor windows over that series, then applies the same climate-reference,
#' binning, and rounding rules as `get_weather()`. `run` must come from
#' `.forecast_catalogue_runs()`, which verifies its checksums; the caller does not verify again.
#'
#' With `reference_years`, the same target calendar months are also built from observed ERA5-Land for
#' each of those years (the same-window reference): frames named `refyear_<year>` (the year the window
#' starts in), delivered through `weather_consumer` with metadata `forecast_reference = TRUE`, or as
#' `attr(, "forecast_reference")`. A year whose target or predictor months are not all observed is
#' left out and listed in `attr(, "forecast_reference_skipped")`.
#'
#' @noRd
.get_forecast_weather <- function(
  survey_data,
  selected_surveys,
  selected_weather,
  connection_params,
  run,
  start,
  len,
  stored_breaks = NULL,
  keep_continuous = FALSE,
  seed = WISEAPP_DEFAULT_SEED,
  weather_consumer = NULL,
  reference_years = NULL
) {
  required_run <- c(
    "id", "product", "model_id", "init", "observed_through", "context_months", "n_leads",
    "members", "variables", "file", "adjustment"
  )
  missing_run <- setdiff(required_run, names(run))
  if (length(missing_run)) {
    stop("Forecast run is missing field(s): ", paste(missing_run, collapse = ", "), call. = FALSE)
  }
  if (!run$adjustment %in% .FORECAST_ADJUSTMENTS) {
    stop("Forecast run must declare a supported pipeline adjustment.", call. = FALSE)
  }
  if (!identical(as.character(run$product), "seasonal")) {
    stop("Only monthly seasonal forecast runs are supported.", call. = FALSE)
  }
  if (!nrow(selected_weather) || !all(selected_weather$name %in% run$variables)) {
    stop("The forecast run does not provide every selected weather variable.", call. = FALSE)
  }
  if (anyDuplicated(selected_weather$name)) {
    stop("selected_weather contains duplicate weather variable names.", call. = FALSE)
  }
  if (!all(c("ref_start", "ref_end", "temporalAgg", "transformation") %in% names(selected_weather))) {
    stop("selected_weather is missing fitted weather transformation fields.", call. = FALSE)
  }

  start <- as.character(start)[1L]
  if (is.na(start) || !grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", start)) {
    stop("Forecast start must be a YYYY-MM month.", call. = FALSE)
  }
  len <- suppressWarnings(as.integer(len))
  if (length(len) != 1L || is.na(len) || len < 1L) {
    stop("Forecast length must be a positive integer number of months.", call. = FALSE)
  }
  target_start <- as.Date(paste0(start, "-01"))
  targets <- seq.Date(target_start, by = "month", length.out = len)
  init <- as.Date(run$init)
  forecast_months <- seq.Date(init, by = "month", length.out = as.integer(run$n_leads))
  if (is.na(init) || len > length(forecast_months) || !all(targets %in% forecast_months)) {
    stop("The complete target window must lie within this forecast run.", call. = FALSE)
  }

  # Apply the same exact fitted-lag availability rule used by the controls.
  visible_months <- .step2_forecast_months(run, selected_weather = selected_weather)
  allowed_starts <- .step2_forecast_starts(visible_months, len)
  if (!start %in% allowed_starts) {
    stop(
      "Forecast predictor months must lie in the run's observed context or forecast months; ",
      "missing months are not filled.",
      call. = FALSE
    )
  }

  vars <- as.character(selected_weather$name)
  lags <- unique(unlist(lapply(seq_len(nrow(selected_weather)), function(i) {
    seq.int(as.integer(selected_weather$ref_start[i]), as.integer(selected_weather$ref_end[i]))
  }), use.names = FALSE))
  predictor_months <- as.Date(unlist(lapply(targets, function(target) {
    vapply(lags, function(lag) as.numeric(.step2_month_add(target, -lag)), numeric(1L))
  }), use.names = FALSE), origin = "1970-01-01")
  needed_months <- sort(unique(c(targets, predictor_months)))

  members <- sort(as.integer(run$members))
  if (!length(members) || anyNA(members) || anyDuplicated(members)) {
    stop("Forecast run member identifiers are invalid.", call. = FALSE)
  }
  codes <- unique(as.character(survey_data$code))
  if (length(codes) != 1L || is.na(codes)) {
    stop("A forecast run requires survey data for exactly one country.", call. = FALSE)
  }
  weather_fnames <- paste0(
    "hazard/weather/historical/", codes, "/", codes, "_era5land.parquet"
  )
  h3_fnames <- selected_surveys |>
    dplyr::distinct(code, year, survname, source) |>
    dplyr::mutate(fname = paste0(
      "microdata/h3/", code, "/", code, "_", year, "_", survname, "_", source, "_h3.parquet"
    )) |>
    dplyr::pull(fname)
  # Observed ERA5-Land is only the climate reference (1991-2020) and, when no breaks are stored, the
  # survey months used to compute them. The predictor series comes from the run file itself.
  survey_timestamps <- unique(as.Date(survey_data$timestamp[!is.na(survey_data$timestamp)]))
  date_min <- min(
    seq.Date(as.Date("1991-01-01"), by = paste0("-", max(c(0L, lags)), " months"), length.out = 2L)[[2L]],
    min(needed_months)
  )
  reference_years <- sort(unique(as.integer(reference_years)))
  date_max <- max(c(as.Date("2020-12-31"), survey_timestamps,
    if (length(reference_years)) as.Date(paste0(max(reference_years) + 1L, "-12-31"))))

  .duck_load_ext("h3")
  con <- .duck_con()
  # Complete member series: observed context months and forecast months, adjusted by the pipeline.
  forecast <- .wx_cache_load(
    run$file, connection_params,
    cols = c("member", "h3", "timestamp", "source", vars), tcol = NULL
  ) |>
    dplyr::filter(timestamp %in% !!needed_months)
  observed <- .wx_cache_load(
    weather_fnames, connection_params,
    cols = c("h3", "timestamp", vars), tmin = date_min, tmax = date_max
  ) |>
    dplyr::filter(timestamp >= !!date_min, timestamp <= !!date_max)

  h3_cols <- c("h3", "code", "year", "survname", "loc_id", "pop_2020")
  h3_slim <- .wx_cache_load(
    h3_fnames, connection_params, cols = h3_cols, tcol = NULL
  )
  if (!"pop_2020" %in% colnames(h3_slim)) {
    h3_slim <- h3_slim |> dplyr::mutate(pop_2020 = 1.0)
  }
  if (!identical(sort(unique(as.character(dplyr::pull(selected_surveys, code)))), codes)) {
    stop("selected_surveys must cover exactly the survey data countries.", call. = FALSE)
  }
  h3_slim <- h3_slim |>
    dplyr::filter(!is.na(h3), !is.na(pop_2020), pop_2020 > 0) |>
    dplyr::select(h3, code, year, survname, loc_id, pop_2020)
  h3_slim <- h3_slim |>
    dplyr::group_by(code, year, survname, loc_id, h3) |>
    dplyr::summarise(pop_2020 = sum(pop_2020, na.rm = TRUE), .groups = "drop")
  # Explicit table names: dbplyr's generated names repeat under a fixed seed and collide across runs.
  tmp_names <- character()
  tmp_name <- function(tag) {
    name <- basename(tempfile(paste0("lw_forecast_", tag, "_")))
    tmp_names <<- c(tmp_names, name)
    name
  }
  on.exit(for (name in tmp_names) {
    try(DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", DBI::dbQuoteIdentifier(con, name))), silent = TRUE)
  }, add = TRUE)
  h3_slim <- h3_slim |> dplyr::compute(name = tmp_name("h3"), temporary = TRUE)

  forecast_h3 <- .harmonise_h3(h3_slim, forecast, con)
  observed_h3 <- .harmonise_h3(h3_slim, observed, con)
  if (observed_h3$res_weather != forecast_h3$res_weather ||
      observed_h3$target_res != forecast_h3$target_res) {
    stop("Observed and forecast weather use different H3 resolutions.", call. = FALSE)
  }
  if (forecast_h3$res_micro < forecast_h3$res_weather) {
    stop("Forecast weather finer than the survey H3 mapping is not supported by the pilot.", call. = FALSE)
  }
  .pop_weighted <- function(weather, mapping, group_vars) {
    mapping <- mapping |>
      dplyr::distinct(h3_weather, code, year, survname, loc_id, pop_2020)
    weather |>
      dplyr::inner_join(mapping, by = c("h3" = "h3_weather")) |>
      dplyr::group_by(dplyr::across(dplyr::all_of(c(group_vars, "code", "year", "survname", "loc_id", "timestamp")))) |>
      dplyr::summarise(
        dplyr::across(
          dplyr::all_of(vars),
          ~ dplyr::if_else(
            sum(dplyr::if_else(!is.na(.x), pop_2020, 0), na.rm = TRUE) > 0,
            sum(.x * pop_2020, na.rm = TRUE) /
              sum(dplyr::if_else(!is.na(.x), pop_2020, 0), na.rm = TRUE),
            NA_real_
          )
        ),
        .groups = "drop"
      )
  }
  # Materialised once; every later query (coverage, window, observed roll) reads these tables.
  monthly <- .pop_weighted(forecast_h3$weather, forecast_h3$h3_slim, "member") |>
    dplyr::compute(name = tmp_name("monthly"), temporary = TRUE)
  observed_loc <- .pop_weighted(observed_h3$weather, observed_h3$h3_slim, character()) |>
    dplyr::compute(name = tmp_name("observed"), temporary = TRUE)

  # The pipeline guarantees the run file's grid; check only what the survey locations need: every
  # member present for every location and needed month, once, with no missing predictor.
  n_locations <- h3_slim |> dplyr::distinct(code, year, survname, loc_id) |> dplyr::count() |>
    dplyr::pull(n) |> as.numeric()
  if (!n_locations) {
    stop("Forecast has no location rows matching the selected surveys.", call. = FALSE)
  }
  coverage <- monthly |>
    dplyr::summarise(
      n = dplyr::n(),
      n_keys = dplyr::n_distinct(member, code, year, survname, loc_id, timestamp),
      n_members = dplyr::n_distinct(member),
      min_member = min(member, na.rm = TRUE),
      max_member = max(member, na.rm = TRUE),
      dplyr::across(dplyr::all_of(vars), ~ sum(as.integer(is.na(.x))))
    ) |>
    dplyr::collect()
  if (as.integer(coverage$n_members) != length(members) || as.integer(coverage$min_member) != members[[1L]] ||
      as.integer(coverage$max_member) != members[[length(members)]]) {
    stop("Forecast file member identifiers do not match the selected run.", call. = FALSE)
  }
  if (coverage$n != coverage$n_keys) {
    stop("Forecast contains duplicate member/location/month rows.", call. = FALSE)
  }
  if (coverage$n != n_locations * length(members) * length(needed_months)) {
    stop("Forecast predictor months are missing for selected locations.", call. = FALSE)
  }
  missing_values <- vapply(coverage[vars], as.numeric, numeric(1L))
  if (any(missing_values > 0)) {
    stop(
      "Forecast predictor coverage is incomplete for variable(s): ",
      paste(names(missing_values)[missing_values > 0], collapse = ", "),
      ". Missing predictor months are not filled.", call. = FALSE
    )
  }
  # Preliminary (ERA5-Land-T) observed months that feed a predictor, for the interface to flag.
  preliminary <- forecast |>
    dplyr::filter(source == "era5land_t") |>
    dplyr::distinct(timestamp) |>
    dplyr::collect()

  agg_fn_map <- c(Mean = "AVG", Median = "MEDIAN", Min = "MIN", Max = "MAX", Sum = "SUM")
  make_roll_exprs <- function(partition) stats::setNames(lapply(seq_len(nrow(selected_weather)), function(i) {
    v <- vars[[i]]
    agg_fn <- agg_fn_map[[selected_weather$temporalAgg[i]]]
    if (is.null(agg_fn)) {
      stop("Unsupported temporal aggregation: ", selected_weather$temporalAgg[i], call. = FALSE)
    }
    dbplyr::sql(sprintf(
      paste0(
        "%s(%s) FILTER (WHERE %s IS NOT NULL) OVER (PARTITION BY %s, year, survname, loc_id ",
        "ORDER BY (YEAR(timestamp) * 12 + MONTH(timestamp)) RANGE BETWEEN %d PRECEDING AND %d PRECEDING)"
      ),
      agg_fn, v, v, partition,
      as.integer(selected_weather$ref_end[i]), as.integer(selected_weather$ref_start[i])
    ))
  }), vars)
  roll_exprs <- make_roll_exprs("member, code")
  observed_roll_exprs <- make_roll_exprs("code")
  observed_roll <- observed_loc |>
    dplyr::mutate(!!!observed_roll_exprs) |>
    dplyr::compute(name = tmp_name("roll"), temporary = TRUE)
  climate_ref <- .build_climate_reference(observed_roll, selected_weather)
  if (!is.null(climate_ref)) .warn_zero_sd_reference(climate_ref)
  has_binning <- "cont_binned" %in% names(selected_weather) &&
    any(!is.na(selected_weather$cont_binned) & selected_weather$cont_binned == "Binned")
  if (has_binning && (is.null(stored_breaks) || !length(stored_breaks))) {
    hist_frame <- observed_loc |>
      dplyr::mutate(!!!observed_roll_exprs) |>
      .apply_transformations(selected_weather, observed_roll, climate_ref = climate_ref) |>
      dplyr::filter(timestamp %in% !!survey_timestamps) |>
      dplyr::arrange(code, year, survname, loc_id, timestamp) |>
      dplyr::collect()
    hist_frame <- .wx_round_weather_values(hist_frame, vars)
    stored_breaks <- .compute_breaks(hist_frame, selected_weather, seed = seed)
  }
  expected_output <- n_locations * len
  if (!is.null(weather_consumer) && !is.function(weather_consumer)) {
    stop("weather_consumer must be NULL or a function.", call. = FALSE)
  }
  # One window query for all members; the partition already includes `member`.
  frames <- monthly |>
    dplyr::mutate(!!!roll_exprs) |>
    .apply_transformations(selected_weather, observed_roll, climate_ref = climate_ref) |>
    dplyr::filter(timestamp %in% !!targets) |>
    dplyr::arrange(member, code, year, survname, loc_id, timestamp) |>
    dplyr::collect()
  frames <- .wx_round_weather_values(frames, vars)
  if (has_binning) frames <- .apply_binning(frames, stored_breaks, keep_continuous)
  frames <- split(frames, factor(frames$member, levels = members))
  # Same-window reference: observed weather for the target calendar months of each reference year.
  start_year <- as.integer(format(target_start, "%Y"))
  reference <- list()
  reference_skipped <- integer()
  if (length(reference_years)) {
    ref_months <- lapply(reference_years, function(y) {
      as.Date(vapply(targets, function(m) as.numeric(.step2_month_add(m, 12L * (y - start_year))), numeric(1L)),
        origin = "1970-01-01")
    })
    ref_all <- observed_roll |>
      .apply_transformations(selected_weather, observed_roll, climate_ref = climate_ref) |>
      dplyr::filter(timestamp %in% !!as.Date(unlist(ref_months), origin = "1970-01-01")) |>
      dplyr::arrange(code, year, survname, loc_id, timestamp) |>
      dplyr::collect()
    ref_all <- .wx_round_weather_values(ref_all, vars)
    if (has_binning) ref_all <- .apply_binning(ref_all, stored_breaks, keep_continuous)
    for (i in seq_along(reference_years)) {
      frame <- ref_all[ref_all$timestamp %in% ref_months[[i]], , drop = FALSE]
      complete <- nrow(frame) == expected_output && !anyNA(frame[vars])
      if (!complete) {
        reference_skipped <- c(reference_skipped, reference_years[[i]])
        next
      }
      rownames(frame) <- NULL
      attr(frame, "forecast_reference_year") <- reference_years[[i]]
      reference[[paste0("refyear_", reference_years[[i]])]] <- frame
    }
  }
  output <- if (is.null(weather_consumer)) vector("list", length(members)) else list()
  window <- .step2_forecast_window(visible_months, start, len)
  window$months <- targets
  for (member_index in seq_along(members)) {
    member_id <- members[[member_index]]
    frame <- frames[[member_index]]
    if (nrow(frame) != expected_output) {
      stop(
        "Forecast member ", member_id,
        " does not contain every selected location for every target month.", call. = FALSE
      )
    }
    rownames(frame) <- NULL
    frame$member <- NULL
    attr(frame, "forecast_member") <- member_id
    attr(frame, "forecast_run") <- run$id
    attr(frame, "forecast_start") <- start
    attr(frame, "forecast_len") <- len
    if (is.null(weather_consumer)) {
      output[[member_index]] <- frame
    } else {
      weather_consumer(frame, list(
        forecast = TRUE,
        forecast_run = run$id,
        forecast_member = member_id,
        member_index = member_index,
        period_members = length(members),
        start = start,
        len = len,
        label = window$label,
        order = member_index,
        is_historical = FALSE
      ))
    }
  }
  if (is.null(weather_consumer)) {
    names(output) <- paste0("member_", members)
  } else {
    for (key in names(reference)) {
      weather_consumer(reference[[key]], list(
        forecast_reference = TRUE,
        forecast_reference_year = attr(reference[[key]], "forecast_reference_year"),
        forecast_run = run$id, start = start, len = len, is_historical = FALSE
      ))
    }
  }
  attr(output, "forecast_members") <- members
  attr(output, "forecast_window") <- window
  attr(output, "forecast_run") <- run$id
  attr(output, "forecast_reference") <- if (is.null(weather_consumer)) reference else NULL
  attr(output, "forecast_reference_skipped") <- reference_skipped
  attr(output, "forecast_preliminary_months") <- sort(as.Date(preliminary$timestamp))
  if (has_binning) attr(output, "stored_breaks") <- stored_breaks
  output
}

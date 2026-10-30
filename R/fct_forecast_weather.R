# Seasonal forecast weather construction ----

#' Construct location-month weather for each member of one seasonal run.
#'
#' Forecast values are already adjusted by the data pipeline. This builder
#' combines them with observed months only for fitted predictor windows, then
#' applies the same rolling, climate-reference, binning, and rounding rules as
#' `get_weather()`.
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
  weather_consumer = NULL
) {
  required_run <- c(
    "id", "product", "model_id", "init", "observed_through", "n_leads",
    "members", "variables", "file", "adjustment"
  )
  missing_run <- setdiff(required_run, names(run))
  if (length(missing_run)) {
    stop("Forecast run is missing field(s): ", paste(missing_run, collapse = ", "), call. = FALSE)
  }
  if (!identical(run$adjustment, "additive_mean_bias_only")) {
    stop("Forecast run must declare the pipeline's additive mean-bias adjustment.", call. = FALSE)
  }
  if (!identical(as.character(run$product), "seasonal")) {
    stop("Only monthly seasonal forecast runs are supported.", call. = FALSE)
  }
  if (!is.null(run$data_sha256)) {
    code <- unique(as.character(survey_data$code))
    if (length(code) != 1L || is.na(code)) {
      stop("Verified forecast runs require one selected country code.", call. = FALSE)
    }
    current_runs <- .forecast_catalogue_runs(connection_params, code)
    current <- if (is.null(current_runs)) NULL else current_runs[[run$id]]
    identity_fields <- c(
      "file", "model_id", "init", "observed_through", "n_leads", "members",
      "variables", "adjustment", "data_sha256", "manifest_sha256", "historical_sha256"
    )
    if (is.null(current) || !identical(run[identity_fields], current[identity_fields])) {
      stop("The selected forecast publication changed; reload the forecast run.", call. = FALSE)
    }
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
  observed_through <- as.Date(run$observed_through)
  forecast_months <- seq.Date(init, by = "month", length.out = as.integer(run$n_leads))
  if (anyNA(c(init, observed_through)) || len > length(forecast_months) ||
      !all(targets %in% forecast_months)) {
    stop("The complete target window must lie within this forecast run.", call. = FALSE)
  }

  # Apply the same exact fitted-lag availability rule used by the controls.
  visible_months <- .step2_forecast_months(run, selected_weather = selected_weather)
  allowed_starts <- .step2_forecast_starts(visible_months, len)
  if (!start %in% allowed_starts) {
    stop(
      "Forecast predictor months must be observed through observed_through or present in this run; missing months are not filled.",
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
  forecast_needed <- needed_months[needed_months > observed_through]
  if (any(forecast_needed > max(forecast_months))) {
    stop("Forecast predictor months are not covered by observations or the selected run.", call. = FALSE)
  }

  members <- sort(as.integer(run$members))
  if (!length(members) || anyNA(members) || anyDuplicated(members)) {
    stop("Forecast run member identifiers are invalid.", call. = FALSE)
  }
  codes <- unique(as.character(survey_data$code))
  weather_fnames <- paste0(
    "hazard/weather/historical/", codes, "/", codes, "_era5land.parquet"
  )
  if (length(codes) != 1L || is.na(codes)) {
    stop("A forecast run requires survey data for exactly one country.", call. = FALSE)
  }
  h3_fnames <- selected_surveys |>
    dplyr::distinct(code, year, survname, source) |>
    dplyr::mutate(fname = paste0(
      "microdata/h3/", code, "/", code, "_", year, "_", survname, "_", source, "_h3.parquet"
    )) |>
    dplyr::pull(fname)
  date_min <- min(
    seq.Date(as.Date("1991-01-01"), by = paste0("-", max(c(0L, lags)), " months"), length.out = 2L)[[2L]],
    min(needed_months)
  )
  date_max <- max(as.Date("2020-12-31"), observed_through)

  .duck_load_ext("h3")
  con <- .duck_con()
  forecast_cols <- c("model", "initialized_at", "member", "h3", "timestamp", "lead_month", vars)
  forecast <- .wx_cache_load(
    run$file, connection_params, cols = forecast_cols, tcol = NULL
  )
  forecast <- forecast |>
    dplyr::filter(
      model == !!as.character(run$model_id),
      initialized_at == !!init
    )
  observed <- .wx_cache_load(
    weather_fnames, connection_params,
    cols = c("h3", "timestamp", vars), tmin = date_min, tmax = date_max
  ) |>
    dplyr::filter(timestamp >= !!date_min, timestamp <= !!date_max)

  # The published pilot uses int64 H3 at the same resolution as ERA5-Land.
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
  h3_slim <- h3_slim |> dplyr::compute(temporary = TRUE)

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
  forecast_h3$weather <- forecast_h3$weather |> dplyr::compute(temporary = TRUE)
  observed_h3$weather <- observed_h3$weather |> dplyr::compute(temporary = TRUE)
  forecast_h3$h3_slim <- forecast_h3$h3_slim |> dplyr::compute(temporary = TRUE)
  observed_h3$h3_slim <- observed_h3$h3_slim |> dplyr::compute(temporary = TRUE)
  expected_h3 <- forecast_h3$h3_slim |>
    dplyr::distinct(h3_weather) |>
    dplyr::collect()
  observed_grid <- observed_h3$weather |>
    dplyr::distinct(h3, timestamp) |>
    dplyr::collect()
  observed_grid <- observed_grid[observed_grid$timestamp <= observed_through, , drop = FALSE]
  forecast_all_h3 <- forecast_h3$weather |>
    dplyr::distinct(h3) |>
    dplyr::collect() |>
    dplyr::pull(h3)
  if (!all(as.character(forecast_all_h3) %in% as.character(observed_grid$h3)) ||
      !all(as.character(observed_grid$h3) %in% as.character(forecast_all_h3))) {
    stop("Observed weather cells do not match the forecast H3 grid.", call. = FALSE)
  }
  forecast_loc <- .pop_weighted(forecast_h3$weather, forecast_h3$h3_slim, "member")
  observed_loc <- .pop_weighted(observed_h3$weather, observed_h3$h3_slim, character()) |>
    dplyr::filter(timestamp <= !!observed_through)

  # Reject identity drift, duplicate grid-month rows, and member/lead omissions.
  member_values <- forecast_loc |> dplyr::distinct(member) |> dplyr::collect() |> dplyr::pull(member)
  if (!identical(sort(as.integer(member_values)), members)) {
    stop("Forecast file member identifiers do not match the selected run.", call. = FALSE)
  }
  expected_leads <- data.frame(
    lead_month = seq_len(as.integer(run$n_leads)),
    timestamp = forecast_months
  )
  actual_leads <- forecast |>
    dplyr::distinct(lead_month, timestamp) |>
    dplyr::collect() |>
    dplyr::arrange(lead_month)
  if (!identical(as.integer(actual_leads$lead_month), expected_leads$lead_month) ||
      !identical(as.Date(actual_leads$timestamp), expected_leads$timestamp)) {
    stop("Forecast file lead months do not match the selected run.", call. = FALSE)
  }
  duplicate_forecast <- forecast_loc |>
    dplyr::count(member, code, year, survname, loc_id, timestamp) |>
    dplyr::filter(n != 1L) |>
    utils::head(1L) |>
    dplyr::collect()
  if (nrow(duplicate_forecast)) {
    stop("Forecast contains duplicate member/location/month rows.", call. = FALSE)
  }

  duplicate_h3_month <- forecast_h3$weather |>
    dplyr::count(h3, member, timestamp) |>
    dplyr::filter(n != 1L) |>
    utils::head(1L) |>
    dplyr::collect()
  if (nrow(duplicate_h3_month)) {
    stop("Forecast contains duplicate H3/member/month values.", call. = FALSE)
  }
  expected_grid <- merge(
    merge(expected_h3, data.frame(member = members), by = NULL),
    data.frame(timestamp = forecast_months), by = NULL
  )
  grid_name <- basename(tempfile("lw_forecast_grid_"))
  duckdb::duckdb_register(con, grid_name, expected_grid)
  on.exit(try(duckdb::duckdb_unregister(con, grid_name), silent = TRUE), add = TRUE)
  forecast_grid <- forecast_h3$weather |>
    dplyr::filter(timestamp %in% !!expected_grid$timestamp) |>
    dplyr::select(h3, member, timestamp) |>
    dplyr::distinct()
  missing_h3 <- dplyr::tbl(con, grid_name) |>
    dplyr::anti_join(
      forecast_grid,
      by = c("h3_weather" = "h3", "member", "timestamp")
    ) |>
    utils::head(1L) |>
    dplyr::collect()
  if (nrow(missing_h3)) {
    stop("Forecast is missing an H3/member/month predictor value.", call. = FALSE)
  }
  missing_weather <- forecast_h3$weather |>
    dplyr::filter(timestamp %in% !!expected_grid$timestamp) |>
    dplyr::summarise(dplyr::across(
      dplyr::all_of(vars), ~ sum(as.integer(is.na(.x)))
    )) |>
    dplyr::collect()
  if (any(vapply(missing_weather, as.numeric, numeric(1L)) > 0)) {
    stop("Forecast has missing weather values on its H3/member/month grid.", call. = FALSE)
  }

  # Replicate only the observed monthly predictor source across member keys.
  # Forecast and observed periods do not overlap under the run availability rule.
  member_tbl <- forecast_loc |> dplyr::distinct(member)
  monthly_cols <- c("member", "code", "year", "survname", "loc_id", "timestamp", vars)
  observed_by_member <- dplyr::cross_join(observed_loc, member_tbl) |>
    dplyr::select(dplyr::all_of(monthly_cols))
  monthly <- dplyr::union_all(
    observed_by_member,
    forecast_loc |> dplyr::select(dplyr::all_of(monthly_cols))
  )

  locations <- h3_slim |>
    dplyr::distinct(code, year, survname, loc_id) |>
    dplyr::collect()
  if (!nrow(locations)) {
    stop("Forecast has no location rows matching the selected surveys.", call. = FALSE)
  }
  expected <- merge(
    merge(locations, data.frame(member = members), by = NULL),
    data.frame(timestamp = needed_months), by = NULL
  )
  expected_name <- basename(tempfile("lw_forecast_expected_"))
  duckdb::duckdb_register(con, expected_name, expected)
  on.exit(try(duckdb::duckdb_unregister(con, expected_name), silent = TRUE), add = TRUE)
  coverage_keys <- c("code", "year", "survname", "loc_id", "member", "timestamp")
  expected_tbl <- dplyr::tbl(con, expected_name)
  missing_key <- expected_tbl |>
    dplyr::anti_join(monthly, by = coverage_keys) |>
    utils::head(1L) |>
    dplyr::collect()
  duplicate_key <- monthly |>
    dplyr::count(dplyr::across(dplyr::all_of(coverage_keys))) |>
    dplyr::filter(n != 1L) |>
    utils::head(1L) |>
    dplyr::collect()
  if (nrow(missing_key) || nrow(duplicate_key)) {
    stop("Forecast predictor months are missing or duplicated for selected locations.", call. = FALSE)
  }
  coverage <- monthly |>
    dplyr::inner_join(expected_tbl, by = coverage_keys) |>
    dplyr::summarise(dplyr::across(
      dplyr::all_of(vars), ~ sum(as.integer(is.na(.x)))
    )) |>
    dplyr::collect()
  missing_values <- vapply(coverage, as.numeric, numeric(1L))
  if (any(missing_values > 0)) {
    stop(
      "Forecast predictor coverage is incomplete for variable(s): ",
      paste(names(missing_values)[missing_values > 0], collapse = ", "),
      ". Missing predictor months are not filled.", call. = FALSE
    )
  }

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
    dplyr::compute(temporary = TRUE)
  climate_ref <- .build_climate_reference(observed_roll, selected_weather)
  if (!is.null(climate_ref)) .warn_zero_sd_reference(climate_ref)
  has_binning <- "cont_binned" %in% names(selected_weather) &&
    any(!is.na(selected_weather$cont_binned) & selected_weather$cont_binned == "Binned")
  if (has_binning && (is.null(stored_breaks) || !length(stored_breaks))) {
    survey_timestamps <- unique(as.Date(survey_data$timestamp[!is.na(survey_data$timestamp)]))
    hist_frame <- observed_loc |>
      dplyr::mutate(!!!observed_roll_exprs) |>
      .apply_transformations(selected_weather, observed_roll, climate_ref = climate_ref) |>
      dplyr::filter(timestamp %in% !!survey_timestamps) |>
      dplyr::arrange(code, year, survname, loc_id, timestamp) |>
      dplyr::collect()
    hist_frame <- .wx_round_weather_values(hist_frame, vars)
    stored_breaks <- .compute_breaks(hist_frame, selected_weather, seed = seed)
  }
  expected_output <- nrow(locations) * len
  if (!is.null(weather_consumer) && !is.function(weather_consumer)) {
    stop("weather_consumer must be NULL or a function.", call. = FALSE)
  }
  output <- if (is.null(weather_consumer)) vector("list", length(members)) else list()
  window <- .step2_forecast_window(visible_months, start, len)
  window$months <- targets
  for (member_index in seq_along(members)) {
    member_id <- members[[member_index]]
    frame <- monthly |>
      dplyr::filter(member == !!member_id) |>
      dplyr::mutate(!!!roll_exprs) |>
      .apply_transformations(selected_weather, observed_roll, climate_ref = climate_ref) |>
      dplyr::filter(timestamp %in% !!targets) |>
      dplyr::arrange(code, year, survname, loc_id, timestamp) |>
      dplyr::collect()
    frame <- .wx_round_weather_values(frame, vars)
    if (has_binning) frame <- .apply_binning(frame, stored_breaks, keep_continuous)
    if (nrow(frame) != expected_output) {
      stop(
        "Forecast member ", member_id,
        " does not contain every selected location for every target month.", call. = FALSE
      )
    }
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
  if (is.null(weather_consumer)) names(output) <- paste0("member_", members)
  attr(output, "forecast_members") <- members
  attr(output, "forecast_window") <- window
  attr(output, "forecast_run") <- run$id
  if (has_binning) attr(output, "stored_breaks") <- stored_breaks
  output
}

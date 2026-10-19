# Step 0/1 data glue ----
# Shiny-free functions that turn the settings of the sample, outcome and
# weather controls into the data the Step 1 tables describe. The module
# servers (mod_1_01 to mod_1_05) call these, and so does the batch pipeline,
# so a batch run and an app session build the same objects from the same
# settings.


# Survey sample ----

#' Surveys available at an endpoint for one unit of analysis
#'
#' The survey list with file names for `unit`, filtered to files that exist at
#' the endpoint (remote sources skip the filter).
#'
#' @param survey_list Survey metadata (`load_overview_metadata()$survey_list`).
#' @param unit `"ind"`, `"hh"` or `"firm"`.
#' @param connection_params Connection parameter list.
#' @param available_files Files at the endpoint; defaults to listing them.
#'
#' @return The filtered survey list with `fname` and `fpath` columns.
#' @noRd
wise_available_surveys <- function(survey_list, unit, connection_params,
                                   available_files = list_available_files(connection_params, unit)) {
  sl <- build_survey_fnames(survey_list, unit, connection_params)
  filter_surveys_to_available(sl, available_files)
}

#' Selected surveys from economy and year choices
#'
#' The batch equivalent of the sample controls: `NULL` countries follow the
#' default economy rule, `NULL` years select every available year.
#'
#' @param survey_list,unit,connection_params See `wise_available_surveys()`.
#' @param countries Character vector of economy codes (`NULL` = default).
#' @param years Named list of survey years per economy code (`NULL` or a
#'   missing code = every available year).
#' @param available_files Passed to `wise_available_surveys()`.
#'
#' @return A data frame of selected surveys, as `build_selected_surveys()`.
#' @noRd
wise_select_surveys <- function(survey_list, unit, connection_params, countries = NULL,
                                years = NULL,
                                available_files = list_available_files(connection_params, unit)) {
  sv <- wise_available_surveys(survey_list, unit, connection_params, available_files)
  codes <- unique(sv$code)
  if (is.null(countries)) countries <- wise_default_economy(codes)
  unknown <- setdiff(countries, codes)
  if (length(unknown)) {
    stop(
      "No ", unit, " surveys available for: ", paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  avail <- get_available_years(sv, countries)
  years_by_code <- lapply(stats::setNames(countries, countries), function(code) {
    yrs <- years[[code]]
    if (is.null(yrs)) wise_default_years(avail[[code]]) else yrs
  })
  out <- build_selected_surveys(sv, years_by_code)
  if (!nrow(out)) stop("No surveys match the selected years.", call. = FALSE)
  out
}


# Survey load and preparation ----

#' Load the microdata of the selected surveys
#'
#' @param selected_surveys Data frame with an `fname` column.
#' @param connection_params Connection parameter list.
#' @return A data frame (all files, schemas unified).
#' @noRd
load_survey_frame <- function(selected_surveys, connection_params) {
  load_data(selected_surveys$fname, connection_params, collect = TRUE, unify_schemas = TRUE)
}

#' Prepare a loaded survey frame for Step 1
#'
#' Time columns, LCU to 2021 PPP conversion, the welfare floor and the derived
#' policy variables, in the order the Survey stats tab applies them.
#'
#' @param df Raw survey frame from `load_survey_frame()`.
#' @param variable_list Variable metadata.
#' @param cpi_ppp CPI and PPP deflators.
#' @return The prepared survey frame.
#' @noRd
prepare_survey_data <- function(df, variable_list, cpi_ppp) {
  df <- add_time_columns(df)
  lcu_vars <- get_lcu_vars(df, variable_list)
  df |>
    assign_data_level() |>
    convert_lcu_to_ppp(cpi_ppp, lcu_vars) |>
    bottom_code_welfare(WISEAPP_WELFARE_FLOOR) |>
    apply_policy_derivations()
}

#' Records without a CPI/PPP deflator in a prepared survey frame
#'
#' CR-BUG-16: LCU values of these records are missing after the conversion.
#'
#' @param df Prepared survey frame.
#' @param variable_list Variable metadata.
#' @return Integer count (0 when the survey has no LCU variables).
#' @noRd
survey_n_no_deflator <- function(df, variable_list) {
  lcu_vars <- get_lcu_vars(df, variable_list)
  if (length(lcu_vars) && all(c("cpi", "ppp2021") %in% names(df))) {
    sum(is.na(df$cpi) | is.na(df$ppp2021))
  } else {
    0L
  }
}


# Location panel ----

#' H3 cell files of the selected surveys
#'
#' @param selected_surveys Data frame with `code`, `year`, `survname`, `source`.
#' @return Character vector of file names, one per survey.
#' @noRd
wise_h3_fnames <- function(selected_surveys) {
  selected_surveys |>
    dplyr::distinct(code, year, survname, source) |>
    dplyr::mutate(fname = paste0(
      "microdata/h3/", code, "/",
      code, "_", year, "_", survname, "_", source, "_h3.parquet"
    )) |>
    dplyr::pull(fname)
}

#' Location panel ids from the H3 cell files
#'
#' Groups survey locations that share H3 cells into panel locations
#' (`loc_id_panel`, the cluster level of the Step 1 models and of the Step 2
#' coefficient uncertainty). One row per survey location.
#'
#' @param h3_local The H3 files as a (preferably materialised) relation with
#'   `code`, `year`, `survname`, `loc_id`, `h3`, `pop_2020`.
#' @return A data frame: `code`, `year`, `survname`, `loc_id`, `loc_id_panel`.
#' @noRd
wise_location_panel <- function(h3_local) {
  panel_map <- loc_panel(h3_local,
    id_col = loc_id, h3_col = h3, weight_col = pop_2020,
    group_cols = c("code", "year", "survname")
  )
  loc_keys <- h3_local |>
    dplyr::distinct(code, year, survname, loc_id) |>
    collect_deterministic(c("code", "year", "survname", "loc_id"))
  # CR-BUG-16: duplicated panel keys error instead of multiplying records.
  dplyr::left_join(loc_keys, panel_map,
    by = c("code", "year", "survname", "loc_id"),
    relationship = "one-to-one"
  )
}

#' Join the location panel onto a survey frame
#'
#' @param df Prepared survey frame.
#' @param panel Result of `wise_location_panel()`.
#' @return `df` with `loc_id_panel`; records without a panel location keep `NA`.
#' @noRd
wise_join_location_panel <- function(df, panel) {
  dplyr::left_join(df, panel,
    by = c("code", "year", "survname", "loc_id"),
    relationship = "many-to-one"
  )
}

#' Load the H3 files and build the location panel (batch)
#'
#' The Survey stats tab does the same steps on its own materialised relation,
#' next to the map data.
#'
#' @param selected_surveys,connection_params See `wise_select_surveys()`.
#' @return Result of `wise_location_panel()`.
#' @noRd
wise_load_location_panel <- function(selected_surveys, connection_params) {
  h3_df <- load_data(wise_h3_fnames(selected_surveys), connection_params)
  .duck_load_ext("h3")
  nm <- basename(tempfile(pattern = "ss_h3_"))
  h3_local <- dplyr::compute(h3_df, name = nm, temporary = TRUE)
  on.exit(
    try(DBI::dbRemoveTable(dbplyr::remote_con(h3_local), nm), silent = TRUE),
    add = TRUE
  )
  wise_location_panel(h3_local)
}


# Statistics variable sets ----

#' Policy-relevant variables shown in the survey statistics
#' @noRd
wise_policy_vars <- function() {
  unique(unlist(lapply(POLICY_DEFINITIONS, `[[`, "vars")))
}

#' Variables behind the survey summary tables
#'
#' The union of the outcome, individual, household, firm and area variables
#' flagged in the variable list and the policy variables, restricted to the
#' columns the survey has.
#'
#' @param variable_list Variable metadata (or `NULL`).
#' @param df Prepared survey frame.
#' @return Character vector.
#' @noRd
wise_stats_vars <- function(variable_list, df) {
  targets <- if (is.null(variable_list)) {
    character(0)
  } else {
    unlist(lapply(c("outcome", "ind", "hh", "firm", "area"), function(fc) {
      if (fc %in% names(variable_list)) variable_list$name[variable_list[[fc]] == 1] else character(0)
    }), use.names = FALSE)
  }
  intersect(unique(c(targets, wise_policy_vars())), names(df))
}


# Outcome ----

#' Survey data with the synthetic `poor` outcome
#'
#' The Outcome stats tab adds `poor` (welfare below the poverty line) when it
#' is the selected outcome and the survey does not carry it.
#'
#' @param df Prepared survey frame.
#' @param info One-row outcome info (`name`, `type`, ...).
#' @param so Selected outcome row from `build_selected_outcome()` (or `NULL`).
#' @return `df`, with a `poor` column when needed.
#' @noRd
wise_outcome_data <- function(df, info, so) {
  oname <- as.character(info$name[1])
  if (identical(oname, "poor") && !"poor" %in% names(df)) {
    pl <- if (!is.null(so) && !is.na(so$povline)) so$povline else 3.00
    if ("welfare" %in% names(df)) {
      line <- .povline_to_ppp(
        pl, df,
        !is.null(so) && !is.na(so$povline) &&
          identical(as.character(so$units[1]), "LCU")
      )
      df$poor <- as.integer(df$welfare < line)
    }
  }
  df
}

#' Selected outcome from run-spec settings
#'
#' Follows the Outcome controls: the currency applies to monetary outcomes
#' only, the poverty line to `poor` only (default from the currency).
#'
#' @param variable_list Variable metadata.
#' @param df Prepared survey frame.
#' @param outcome Outcome name (`NULL` = first available).
#' @param currency `"PPP"` or `"LCU"`.
#' @param poverty_line Poverty line (`NULL` = default).
#' @return A list with `info` (outcome row) and `so` (augmented row).
#' @noRd
wise_selected_outcome <- function(variable_list, df, outcome = NULL, currency = "PPP",
                                  poverty_line = NULL) {
  outs <- filter_outcome_vars(variable_list, colnames(df))
  if (is.null(outcome)) outcome <- wise_default_outcome(outs$name)
  info <- outs[outs$name == outcome, , drop = FALSE]
  if (!nrow(info)) {
    stop("Outcome '", outcome, "' is not available in the selected surveys.", call. = FALSE)
  }
  cur <- if (is_monetary_outcome(info$name[1], info$units[1])) currency else NULL
  pl <- if (identical(as.character(info$name[1]), "poor")) {
    poverty_line %||% wise_default_poverty_line(currency, df)
  }
  list(info = info, so = build_selected_outcome(info, currency = cur, poverty_line = pl))
}


# Weather ----

# Names of the per-variable weather inputs, keyed by spec field.
.WX_INPUT_KEYS <- c(
  ref_period = "relativePeriod", temporal_agg = "temporalAgg",
  transformation = "varConstruction", form = "contOrBinned",
  n_bins = "numBins", binning_method = "binningMethod",
  custom_breaks = "customBreaks", polynomial = "polynomial"
)

#' Weather variable names of a spec's weather section
#' @param weather The spec `weather` list.
#' @noRd
wise_spec_weather_vars <- function(weather) setdiff(names(weather), "hist_years")

#' Selected weather table from the spec's weather section
#'
#' Maps the spec fields to the keyed inputs of the weather controls and calls
#' the same `build_selected_weather()` as the Weather module.
#'
#' @param weather The spec `weather` list (`<var> = list(...)`, `hist_years`).
#' @param variable_list Variable metadata.
#' @return The selected weather tibble (one row per variable).
#' @noRd
wise_selected_weather <- function(weather, variable_list) {
  vl <- get_weather_vars(variable_list)
  vars <- wise_spec_weather_vars(weather)
  if (!length(vars)) vars <- wise_default_weather_var(vl)
  inputs <- list()
  for (v in vars) {
    for (field in names(.WX_INPUT_KEYS)) {
      val <- weather[[v]][[field]]
      if (!is.null(val)) inputs[[paste0(v, "_", .WX_INPUT_KEYS[[field]])]] <- val
    }
  }
  build_selected_weather(vars, vl, inputs)
}

#' Default weather variable: the first in the variable list
#' @param weather_vars Output of `get_weather_vars()`.
#' @noRd
wise_default_weather_var <- function(weather_vars) weather_vars$name[1]

#' Fetch weather for the survey dates and the historical comparison dates
#'
#' @param survey_data Prepared survey frame.
#' @param selected_surveys Selected surveys.
#' @param selected_weather Selected weather table.
#' @param hist_years Named integer vector `c(from =, to =)`.
#' @param connection_params Connection parameter list.
#' @param seed Seed for the K-means bin breaks.
#' @return The `get_weather()` result (list with `historical`, attributes).
#' @noRd
wise_weather_fetch <- function(survey_data, selected_surveys, selected_weather,
                               hist_years, connection_params, seed) {
  survey_dates <- extract_survey_dates(survey_data)
  weather_dates <- sort(unique(c(
    survey_dates,
    expand_hist_dates(survey_dates, hist_years[["from"]], hist_years[["to"]])
  )))
  get_weather(
    survey_data       = survey_data,
    selected_surveys  = selected_surveys,
    selected_weather  = selected_weather,
    dates             = weather_dates,
    connection_params = connection_params,
    seed              = seed
  )
}

#' Continuous and historical companions of a survey-weather merge
#'
#' The slim survey x weather frame with the pre-binning values of binned
#' variables, and the historical weather restricted to the sample's
#' location x calendar-month cells. Plot and statistics inputs only.
#'
#' @param survey_data Prepared survey frame.
#' @param weather_full Result of `wise_weather_fetch()`.
#' @param survey_weather Result of `merge_survey_weather()`.
#' @return A list with `survey_weather_cont` (or `NULL`) and `hist_cells`.
#' @noRd
wise_weather_companions <- function(survey_data, weather_full, survey_weather) {
  loc_wd <- weather_full$historical
  cont_wd <- attr(weather_full, "continuous_weather")
  hist_wd <- loc_wd
  if (!is.null(cont_wd)) {
    weather_keys <- intersect(
      c("code", "year", "survname", "loc_id", "timestamp"),
      intersect(names(hist_wd), names(cont_wd))
    )
    continuous_vars <- setdiff(names(cont_wd), weather_keys)
    hist_wd <- hist_wd |>
      dplyr::select(-dplyr::any_of(continuous_vars)) |>
      dplyr::left_join(
        cont_wd |>
          dplyr::select(dplyr::all_of(c(weather_keys, continuous_vars))),
        by = weather_keys
      )
  }

  survey_cont <- NULL
  if (!is.null(cont_wd)) {
    survey_cont <- tryCatch(
      merge_survey_weather(
        survey_data |> dplyr::select(dplyr::any_of(c(
          "code", "year", "survname", "loc_id", "timestamp",
          "economy", "weight"
        ))),
        cont_wd
      ),
      error = function(e) NULL
    )
  }
  list(
    survey_weather_cont = survey_cont,
    hist_cells = join_hist_sample_cells(hist_wd, survey_weather)
  )
}

#' Load weather and merge it onto the survey
#'
#' The batch composition of `wise_weather_fetch()`, `merge_survey_weather()`
#' and `wise_weather_companions()`; the Weather stats tab calls the same three
#' steps with its own error handling.
#'
#' @inheritParams wise_weather_fetch
#' @return A list: `survey_weather`, `survey_weather_cont`, `hist_cells`,
#'   `stored_breaks`, `n_dropped`.
#' @noRd
wise_load_weather <- function(survey_data, selected_surveys, selected_weather,
                              hist_years, connection_params, seed) {
  weather_full <- wise_weather_fetch(
    survey_data, selected_surveys, selected_weather, hist_years, connection_params, seed
  )
  if (is.null(weather_full$historical)) stop("No weather data was returned.", call. = FALSE)
  survey_wd <- merge_survey_weather(survey_data, weather_full$historical)
  if (is.null(survey_wd)) stop("No survey record matched the weather data.", call. = FALSE)
  c(
    list(survey_weather = survey_wd),
    wise_weather_companions(survey_data, weather_full, survey_wd),
    list(
      stored_breaks = attr(weather_full, "stored_breaks"),
      n_dropped = attr(survey_wd, "n_dropped") %||% 0L
    )
  )
}

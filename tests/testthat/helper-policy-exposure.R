# Shared by test-policy-exposure-mapping.R, test-weather-continuous-companion.R,
# test-policy-central-kernel.R and test-fct_policy_loading.R

test_policy_exposure_fixture <- function() {
  survey <- data.frame(
    hhid = c("h1", "h2", "h3"),
    code = "TST",
    year = c(2020L, 2020L, 2020L),
    survname = c("wave_a", "wave_a", "wave_b"),
    loc_id = "loc1",
    int_month = 1L,
    welfare = c(1, 2, 3),
    weight = c(1, 2, 3),
    stringsAsFactors = FALSE
  )
  weather <- data.frame(
    code = "TST",
    year = 2020L,
    survname = c("wave_a", "wave_a", "wave_b"),
    loc_id = "loc1",
    timestamp = as.POSIXct(
      c("2030-01-01", "2030-01-01", "2031-01-01"), tz = "UTC"
    ),
    exposure = factor(c("dry", "wet", "dry"), levels = c("dry", "wet")),
    stringsAsFactors = FALSE
  )
  train <- data.frame(
    welfare = c(1, 2, 3, 4),
    exposure = factor(c("dry", "wet", "dry", "wet"),
      levels = c("dry", "wet")
    )
  )
  prepared <- survey |>
    dplyr::mutate(year = as.character(year)) |>
    dplyr::select(-welfare)
  cache <- build_weather_join_cache(dplyr::mutate(
    prepared, .svy_row_id = seq_len(nrow(prepared))
  ))
  list(survey = survey, weather = weather, train = train,
       prepared = prepared, cache = cache)
}

.policy_test_attach_exposure <- function(pipeline, baseline, weather_values) {
  ids <- pipeline$svy_row_id
  keys <- c("code", "year", "survname", "loc_id", "int_month")
  table <- baseline[ids, keys, drop = FALSE]
  for (name in names(weather_values)) table[[name]] <- weather_values[[name]]
  table$timestamp <- as.Date(sprintf(
    "%d-%02d-01", pipeline$sim_year, table$int_month
  ))
  pipeline$weather_exposure <- c(
    list(status = "ok", table = table, row_index = seq_along(ids),
         prediction_row_id = seq_along(ids)),
    pipeline[c("svy_row_id", "sim_year", "weight", "id_vec")]
  )
  pipeline
}

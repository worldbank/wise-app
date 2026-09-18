# Focused synthetic benchmark for W1-D / S2-P1 baseline-wave filtering.

pkgload::load_all(quiet = TRUE)

if (!all(vapply(c("arrow", "bit64", "duckdb"), requireNamespace,
                quietly = TRUE, FUN.VALUE = logical(1)))) {
  stop("arrow, bit64, and duckdb are required", call. = FALSE)
}

root <- tempfile("wiseapp-wave-filter-")
dir.create(root, recursive = TRUE)
on.exit(unlink(root, recursive = TRUE), add = TRUE)
cache_root <- file.path(root, "cache")
Sys.setenv(
  WISEAPP_WEATHER_CACHE_DIR = cache_root,
  WISEAPP_WEATHER_CACHE_FORCE = "1",
  WISEAPP_WEATHER_CACHE_DISABLE = "0"
)

con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
tryCatch(DBI::dbExecute(con, "INSTALL h3 FROM community"), error = function(e) NULL)
DBI::dbExecute(con, "LOAD h3")

cells <- DBI::dbGetQuery(con, paste(
  "SELECT h3_h3_to_string(unnest(h3_cell_to_children(",
  "h3_string_to_h3('8428347ffffffff'), 5))) AS h3"
))$h3[1:7]
h3_int <- DBI::dbGetQuery(con, sprintf(
  "SELECT h3_string_to_h3(h3) AS h3 FROM (VALUES %s) t(h3)",
  paste0("('", cells, "')", collapse = ", ")
))$h3

code <- "TST"
h3_dir <- file.path(root, "microdata", "h3", code)
wx_dir <- file.path(root, "hazard", "weather", "historical", code)
dir.create(h3_dir, recursive = TRUE)
dir.create(wx_dir, recursive = TRUE)

years <- 2011:2020
surveys <- do.call(rbind, lapply(years, function(year) data.frame(
  code = code, year = year, survname = "SRV", source = "src"
)))
for (year in years) {
  h3 <- data.frame(
    h3 = rep(cells, each = 100L), code = code, year = year,
    survname = "SRV", loc_id = rep(paste0("loc", 1:7), each = 100L),
    pop_2020 = rep(1L, 700L)
  )
  arrow::write_parquet(h3, file.path(h3_dir, sprintf(
    "%s_%d_SRV_src_h3.parquet", code, year)))
}

timestamps <- seq(as.Date("2018-01-01"), as.Date("2020-12-01"), by = "month")
weather <- expand.grid(h3 = h3_int, timestamp = timestamps)
weather$tx <- seq_len(nrow(weather)) / 10
arrow::write_parquet(weather, file.path(wx_dir, "TST_era5land.parquet"))

survey_data <- expand.grid(timestamp = tail(timestamps, 12L), loc_id = paste0("loc", 1:7))
survey_data$code <- code
survey_data$year <- 2020L
survey_data$survname <- "SRV"
selected_weather <- data.frame(
  name = "tx", ref_start = 1L, ref_end = 3L, temporalAgg = "Mean",
  cont_binned = "Continuous", binning_method = NA_character_,
  num_bins = NA_integer_, transformation = "None"
)
dates <- sort(unique(survey_data$timestamp))
cp <- list(type = "local", path = root)
run <- function(ss) get_weather(survey_data, ss, selected_weather, dates, cp)$historical

clear_cache <- function() {
  unlink(cache_root, recursive = TRUE)
  dir.create(cache_root, recursive = TRUE)
}
clear_cache()
cold_full <- unname(system.time(full <- run(surveys))["elapsed"])
clear_cache()
cold_filtered <- unname(system.time(filtered <- run(tail(surveys, 1L)))["elapsed"])
invisible(run(surveys))
invisible(run(tail(surveys, 1L)))
warm_full <- replicate(5L, unname(system.time(run(surveys))["elapsed"]))
warm_filtered <- replicate(5L, unname(system.time(run(tail(surveys, 1L)))["elapsed"]))
full_baseline <- full[full$year == 2020L, , drop = FALSE]
rownames(full_baseline) <- NULL
rownames(filtered) <- NULL
cat(sprintf(
  paste0("cold_full_seconds=%.4f\ncold_filtered_seconds=%.4f\n",
         "cold_speedup=%.2fx\nwarm_full_median_seconds=%.4f\n",
         "warm_filtered_median_seconds=%.4f\nwarm_speedup=%.2fx\n",
         "full_rows=%d\nfiltered_rows=%d\nparity=%s\n"),
  cold_full, cold_filtered, cold_full / cold_filtered,
  median(warm_full), median(warm_filtered), median(warm_full) / median(warm_filtered),
  nrow(full), nrow(filtered), isTRUE(all.equal(full_baseline, filtered, tolerance = 1e-12))
))

make_forecast_catalogue_fixture <- function() {
  root <- tempfile("forecast-catalogue-")
  dir.create(file.path(root, "hazard/weather/forecasts/BFA"), recursive = TRUE)
  withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
  entries <- lapply(c("2026-05", "2026-10"), function(id) {
    init <- as.Date(paste0(id, "-01"))
    file <- paste0("hazard/weather/forecasts/BFA/BFA_test_", gsub("-", "", id), ".parquet")
    data <- file.path(root, file)
    writeBin(charToRaw(id), data)
    manifest_path <- sub("parquet$", "json", data)
    manifest <- list(
      schema_version = "draft-2", product = "seasonal", lead_unit = "month", initialized_at = format(init),
      observed_through = format(.step2_month_add(init, -1L)), status = "draft", experimental = TRUE,
      adjustment = "additive_mean_bias_only", h3 = list(type = "int64", resolution = 6L),
      members = list(first = 0L, last = 1L), n_members = 2L, leads = 1:6,
      valid_months = format(seq(init, by = "month", length.out = 6L)), variables = "t",
      context_months = 12L, context_source = "era5land;era5land_t",
      model = "test_model", run_id = paste0("BFA_", id),
      output_sha256 = stats::setNames(list(digest::digest(file = data, algo = "sha256")), basename(data))
    )
    jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
    data.frame(id = id, product = "seasonal", lead_unit = "month", label = id, model = "Test",
      init = format(init), released = format(init + 5), next_release = format(.step2_month_add(init, 1L) + 5),
      n_members = 2L, n_leads = 6L, observed_through = manifest$observed_through, context_months = 12L,
      context_source = "era5land;era5land_t", variables = "t", adjustment = "additive_mean_bias_only",
      file = file, data_sha256 = manifest$output_sha256[[1L]],
      manifest_sha256 = digest::digest(file = manifest_path, algo = "sha256"),
      status = "draft", data_version = "test-1")
  })
  catalogue <- file.path(root, "hazard/weather/forecasts/BFA/catalogue.csv")
  utils::write.csv(do.call(rbind, entries), catalogue, row.names = FALSE)
  list(root = root, entries = entries, catalogue = catalogue, cp = list(type = "local", path = root))
}

test_that("local catalogues discover only complete draft-2 runs newest first", {
  fx <- make_forecast_catalogue_fixture()
  runs <- .step2_forecast_runs(scaffold = FALSE, connection_params = fx$cp, code = "BFA")
  expect_named(runs, c("2026-10", "2026-05"))
  expect_identical(runs[[1L]]$members, 0:1)
  expect_identical(runs[[1L]]$init, as.Date("2026-10-01"))
  expect_identical(runs[[1L]]$observed_through, as.Date("2026-09-01"))
  expect_identical(runs[[1L]]$context_months, 12L)
  expect_identical(runs[[1L]]$variables, "t")
  expect_true(runs[[1L]]$experimental)
  expect_false("historical_sha256" %in% names(runs[[1L]]))
  expect_equal(nrow(attr(runs, "skipped")), 0L)
  expect_null(.forecast_catalogue_runs(fx$cp, "GHA"))
  expect_null(.forecast_catalogue_runs(fx$cp, "../BFA"))
  expect_null(.forecast_catalogue_runs(list(type = "s3"), "BFA"))
  window <- .step2_forecast_window(.step2_forecast_months(runs[[1L]]), "2026-11", 3L)
  sig <- .step2_forecast_signature(runs[[1L]], window)
  expect_identical(sig$members, 0:1)
  expect_identical(sig$data_version, "test-1")
  expect_identical(sig$data_sha256, runs[[1L]]$data_sha256)
  expect_false("historical_sha256" %in% names(sig))
  # An incomplete run (manifest is written last) is not offered.
  unlink(sub("parquet$", "json", file.path(fx$root, fx$entries[[2L]]$file)))
  expect_named(.forecast_catalogue_runs(fx$cp, "BFA"), "2026-05")
})

test_that("one invalid run is skipped and reported, not fatal", {
  fx <- make_forecast_catalogue_fixture()
  data <- file.path(fx$root, fx$entries[[2L]]$file)
  manifest_path <- sub("parquet$", "json", data)
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = TRUE)

  manifest$adjustment <- NULL
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  runs <- .forecast_catalogue_runs(fx$cp, "BFA")
  expect_named(runs, "2026-05")
  expect_match(attr(runs, "skipped")$reason, "supported adjustment")
  expect_identical(attr(runs, "skipped")$id, "2026-10")

  manifest$adjustment <- "additive_mean_bias_only"
  manifest$schema_version <- "draft-1"
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  expect_match(attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")$reason, "draft-2")

  manifest$schema_version <- "draft-2"
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  expect_match(attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")$reason, "manifest checksum")

  writeBin(charToRaw("changed bytes"), data)
  entries <- fx$entries
  entries[[2L]]$manifest_sha256 <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  expect_match(attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")$reason, "data checksum")

  entries[[2L]]$file <- "hazard/weather/forecasts/BFA/../outside.parquet"
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  expect_match(attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")$reason, "data path")
})

test_that("the catalogue errors only when no run is valid or the catalogue itself is malformed", {
  fx <- make_forecast_catalogue_fixture()
  entries <- fx$entries
  entries[[1L]]$file <- "hazard/weather/forecasts/BFA/../outside.parquet"
  entries[[2L]]$context_source <- "other"
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  expect_error(.forecast_catalogue_runs(fx$cp, "BFA"), "No valid seasonal forecast run")
  entries[[2L]] <- entries[[1L]]
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  expect_error(.forecast_catalogue_runs(fx$cp, "BFA"), "Invalid seasonal forecast catalogue")
})

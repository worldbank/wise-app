test_that("local catalogues discover only complete adjusted runs newest first", {
  root <- tempfile("forecast-catalogue-")
  dir.create(file.path(root, "hazard/weather/forecasts/BFA"), recursive = TRUE)
  dir.create(file.path(root, "hazard/weather/historical/BFA"), recursive = TRUE)
  withr::defer(unlink(root, recursive = TRUE))
  historical <- file.path(root, "hazard/weather/historical/BFA/BFA_era5land.parquet")
  writeBin(charToRaw("synthetic historical identity"), historical)
  entries <- lapply(c("2026-05", "2026-10"), function(id) {
    init <- as.Date(paste0(id, "-01"))
    file <- paste0("hazard/weather/forecasts/BFA/BFA_test_", gsub("-", "", id), ".parquet")
    data <- file.path(root, file)
    writeBin(charToRaw(id), data)
    manifest <- list(
      country = "BFA", product = "seasonal", lead_unit = "month", initialized_at = format(init),
      observed_through = "2025-12-01", status = "draft", experimental = TRUE,
      adjustment = "additive_mean_bias_only", h3 = list(type = "int64", resolution = 6L),
      members = list(first = 0L, last = 1L), n_members = 2L, leads = 1:6,
      valid_months = format(seq(init, by = "month", length.out = 6L)), variables = "t",
      model = "test_model", run_id = paste0("BFA_", id),
      historical_sha256 = digest::digest(file = historical, algo = "sha256"),
      output_sha256 = stats::setNames(list(digest::digest(file = data, algo = "sha256")), basename(data))
    )
    jsonlite::write_json(manifest, sub("parquet$", "json", data), auto_unbox = TRUE)
    data.frame(id = id, product = "seasonal", lead_unit = "month", label = id, model = "Test",
      init = format(init), released = format(init + 5), next_release = format(.step2_month_add(init, 1L) + 5),
      n_members = 2L, n_leads = 6L, observed_through = "2025-12-01", file = file,
      status = "draft", data_version = "test-1")
  })
  catalogue <- file.path(root, "hazard/weather/forecasts/BFA/catalogue.csv")
  utils::write.csv(do.call(rbind, entries), catalogue, row.names = FALSE)
  cp <- list(type = "local", path = root)
  runs <- .step2_forecast_runs(scaffold = FALSE, connection_params = cp, code = "BFA")
  expect_named(runs, c("2026-10", "2026-05"))
  expect_identical(runs[[1L]]$members, 0:1)
  expect_identical(runs[[1L]]$init, as.Date("2026-10-01"))
  expect_identical(runs[[1L]]$observed_through, as.Date("2025-12-01"))
  expect_true(runs[[1L]]$experimental)
  expect_null(.forecast_catalogue_runs(cp, "GHA"))
  expect_null(.forecast_catalogue_runs(cp, "../BFA"))
  expect_null(.forecast_catalogue_runs(list(type = "s3"), "BFA"))
  window <- .step2_forecast_window(.step2_forecast_months(runs[[1L]]), "2026-11", 3L)
  sig <- .step2_forecast_signature(runs[[1L]], window)
  expect_identical(sig$members, 0:1)
  expect_identical(sig$data_version, "test-1")
  expect_identical(sig$data_sha256, runs[[1L]]$data_sha256)
  data <- file.path(root, entries[[2L]]$file)
  manifest_path <- sub("parquet$", "json", data)
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = TRUE)
  manifest$adjustment <- NULL
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  expect_error(.forecast_catalogue_runs(cp, "BFA"), "mean-bias adjustment")
  manifest$adjustment <- "additive_mean_bias_only"
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  writeBin(charToRaw("changed bytes"), data)
  expect_error(.forecast_catalogue_runs(cp, "BFA"), "checksum")
  unlink(manifest_path)
  expect_named(.forecast_catalogue_runs(cp, "BFA"), "2026-05")
  entries[[1L]]$file <- "hazard/weather/forecasts/BFA/../outside.parquet"
  utils::write.csv(entries[[1L]], catalogue, row.names = FALSE)
  expect_error(.forecast_catalogue_runs(cp, "BFA"), "data path")
})

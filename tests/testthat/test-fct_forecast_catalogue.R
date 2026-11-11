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
      # The pipeline writes a count with the first and last context month and each month's source.
      context_months = list(n = 12L, first = format(.step2_month_add(init, -12L)),
        last = format(.step2_month_add(init, -1L)), sources = list()),
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

test_that("catalogues discover only complete draft-2 runs newest first", {
  fx <- make_forecast_catalogue_fixture()
  runs <- .forecast_catalogue_runs(fx$cp, "BFA")
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
  entries[[2L]]$context_months <- "11"
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  expect_error(.forecast_catalogue_runs(fx$cp, "BFA"), "No valid seasonal forecast run")
  entries[[2L]] <- entries[[1L]]
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  expect_error(.forecast_catalogue_runs(fx$cp, "BFA"), "Invalid seasonal forecast catalogue")
})

test_that("an optional skill file is part of the run identity", {
  fx <- make_forecast_catalogue_fixture()
  expect_true(all(is.na(vapply(.forecast_catalogue_runs(fx$cp, "BFA"), `[[`, "", "skill_file"))))
  data <- file.path(fx$root, fx$entries[[2L]]$file)
  manifest_path <- sub("parquet$", "json", data)
  dir.create(file.path(dirname(data), "skill"))
  skill_path <- file.path(dirname(data), "skill", "ecmwf_seas51_10_1993_2016.parquet")
  writeBin(charToRaw("skill"), skill_path)
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = TRUE)
  manifest$skill_file <- "skill/ecmwf_seas51_10_1993_2016.parquet"
  manifest$output_sha256[["skill/ecmwf_seas51_10_1993_2016.parquet"]] <- digest::digest(file = skill_path, algo = "sha256")
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  entries <- fx$entries
  entries[[2L]]$manifest_sha256 <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  runs <- .forecast_catalogue_runs(fx$cp, "BFA")
  expect_identical(runs[["2026-10"]]$skill_file,
    "hazard/weather/forecasts/BFA/skill/ecmwf_seas51_10_1993_2016.parquet")
  writeBin(charToRaw("changed"), skill_path)
  skipped <- attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")
  expect_match(skipped$reason, "skill file")
  manifest$skill_file <- "../outside.parquet"
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  entries[[2L]]$manifest_sha256 <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(do.call(rbind, entries), fx$catalogue, row.names = FALSE)
  expect_match(attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")$reason, "skill path")
})

test_that("a run with one adjustment per variable is accepted and the adjustments must match the catalogue", {
  fx <- make_forecast_catalogue_fixture()
  data <- file.path(fx$root, fx$entries[[2L]]$file)
  manifest_path <- sub("parquet$", "json", data)
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = TRUE)
  manifest$variables <- c("t", "r")
  manifest$adjustments <- list(t = "additive_mean_bias_only", r = "ratio")
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  cat_rows <- utils::read.csv(fx$catalogue, colClasses = "character")
  hit <- cat_rows$id == "2026-10"
  cat_rows$variables[hit] <- "t;r"
  cat_rows$adjustment[hit] <- "additive_mean_bias_only;ratio"
  cat_rows$manifest_sha256[hit] <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(cat_rows, fx$catalogue, row.names = FALSE)
  runs <- .forecast_catalogue_runs(fx$cp, "BFA")
  expect_identical(runs[["2026-10"]]$variables, c("t", "r"))
  expect_identical(runs[["2026-10"]]$adjustment, "additive_mean_bias_only;ratio")

  manifest$adjustments$r <- "unknown_rule"
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  cat_rows$manifest_sha256[hit] <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(cat_rows, fx$catalogue, row.names = FALSE)
  expect_match(attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")$reason, "supported adjustment")
})

test_that("draft runs are offered on Posit Connect like on any server", {
  fx <- make_forecast_catalogue_fixture()
  testthat::local_mocked_bindings(
    .on_posit_connect = function() TRUE,
    .assert_connection_allowed = function(params) invisible(params)
  )
  expect_named(.forecast_catalogue_runs(fx$cp, "BFA"), c("2026-10", "2026-05"))
  expect_identical(.forecast_catalogue_runs(fx$cp, "BFA")[[1L]]$status, "draft")
})

test_that("non-local sources read the same runs through load_data()", {
  fx <- make_forecast_catalogue_fixture()
  from_files <- .forecast_catalogue_runs(fx$cp, "BFA")
  testthat::local_mocked_bindings(.forecast_is_local = function(connection_params) FALSE)
  from_remote <- .forecast_catalogue_runs(fx$cp, "BFA")
  expect_named(from_remote, names(from_files))
  expect_identical(vapply(from_remote, `[[`, "", "data_sha256"), vapply(from_files, `[[`, "", "data_sha256"))
  expect_identical(vapply(from_remote, `[[`, "", "manifest_sha256"), vapply(from_files, `[[`, "", "manifest_sha256"))
  expect_null(.forecast_catalogue_runs(fx$cp, "GHA"))
})

test_that("a missing run file is skipped on the remote path too", {
  fx <- make_forecast_catalogue_fixture()
  unlink(file.path(fx$root, fx$entries[[2L]]$file))
  testthat::local_mocked_bindings(.forecast_is_local = function(connection_params) FALSE)
  runs <- .forecast_catalogue_runs(fx$cp, "BFA")
  expect_named(runs, "2026-05")
  expect_match(attr(runs, "skipped")$reason, "missing")
})

test_that("remote reads treat a 404 as a missing file and raise other errors", {
  cp <- list(type = "s3", bucket = "bucket")
  testthat::local_mocked_bindings(load_data = function(...) {
    stop("HTTP Error: HTTP GET error on 'https://x/y.csv' (HTTP 404)")
  })
  expect_null(.forecast_file_text(cp, "hazard/weather/forecasts/BFA/catalogue.csv"))
  testthat::local_mocked_bindings(load_data = function(...) stop("401 Unauthorized"))
  expect_error(.forecast_file_text(cp, "hazard/weather/forecasts/BFA/catalogue.csv"), "401 Unauthorized")
})

test_that("a remote run file is hashed once per process while its checksum matches", {
  fx <- make_forecast_catalogue_fixture()
  calls <- 0L
  testthat::local_mocked_bindings(
    .forecast_is_local = function(connection_params) FALSE,
    .forecast_remote_sha256 = function(connection_params, rel) {
      calls <<- calls + 1L
      digest::digest(file = file.path(fx$root, rel), algo = "sha256")
    }
  )
  expect_length(.forecast_catalogue_runs(fx$cp, "BFA"), 2L)
  first <- calls
  expect_length(.forecast_catalogue_runs(fx$cp, "BFA"), 2L)
  expect_identical(calls, first)
})

test_that("the DuckDB sha256 of a blob matches the file checksum", {
  fx <- make_forecast_catalogue_fixture()
  rel <- fx$entries[[2L]]$file
  expect_identical(.forecast_remote_sha256(fx$cp, rel), digest::digest(file = file.path(fx$root, rel), algo = "sha256"))
  expect_null(.forecast_remote_sha256(fx$cp, "hazard/weather/forecasts/BFA/absent.parquet"))
})

test_that("a run may carry any well-formed variable name and the names must be column-like", {
  fx <- make_forecast_catalogue_fixture()
  data <- file.path(fx$root, fx$entries[[2L]]$file)
  manifest_path <- sub("parquet$", "json", data)
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = TRUE)
  manifest$variables <- c("t", "r", "tn", "tx")
  manifest$adjustments <- list(t = "additive_mean_bias_only", r = "ratio", tn = "additive_mean_bias_only",
    tx = "additive_mean_bias_only")
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  cat_rows <- utils::read.csv(fx$catalogue, colClasses = "character")
  hit <- cat_rows$id == "2026-10"
  cat_rows$variables[hit] <- "t;r;tn;tx"
  cat_rows$adjustment[hit] <- "additive_mean_bias_only;ratio;additive_mean_bias_only;additive_mean_bias_only"
  cat_rows$manifest_sha256[hit] <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(cat_rows, fx$catalogue, row.names = FALSE)
  runs <- .forecast_catalogue_runs(fx$cp, "BFA")
  expect_named(runs, c("2026-10", "2026-05"))
  expect_identical(runs[["2026-10"]]$variables, c("t", "r", "tn", "tx"))

  # A newly published variable needs no change in the app.
  manifest$variables <- c("t", "q_new")
  manifest$adjustments$q_new <- "ratio"
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  cat_rows$variables[hit] <- "t;q_new"
  cat_rows$adjustment[hit] <- "additive_mean_bias_only;ratio"
  cat_rows$manifest_sha256[hit] <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(cat_rows, fx$catalogue, row.names = FALSE)
  expect_identical(.forecast_catalogue_runs(fx$cp, "BFA")[["2026-10"]]$variables, c("t", "q_new"))

  # Names that are not column-like are refused.
  manifest$variables <- c("t", "Bad Name")
  manifest$adjustments[["Bad Name"]] <- "ratio"
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
  cat_rows$variables[hit] <- "t;Bad Name"
  cat_rows$manifest_sha256[hit] <- digest::digest(file = manifest_path, algo = "sha256")
  utils::write.csv(cat_rows, fx$catalogue, row.names = FALSE)
  expect_match(attr(.forecast_catalogue_runs(fx$cp, "BFA"), "skipped")$reason, "disagree")
})

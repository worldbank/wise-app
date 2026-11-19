# Batch runner pieces that need no targets run: stage items, the data digest,
# the table writer and the reproducibility check of the project template.

test_that("stage items hold their own spec sections and the stamp of the files they read", {
  spec <- wise_spec(weather = list(tx = list()), model = list(), sim = list(), policy = list(sp = list()))
  ids <- wise_spec_ids(spec)
  runs <- tibble::tibble(
    data_id = ids$data_id, weather_id = ids$weather_id, fit_id = ids$fit_id,
    sim_id = ids$sim_id, policy_id = ids$policy_id, wxvar_ids = list(ids$wxvar_ids), spec = list(spec)
  )
  grid <- list(runs = runs, source = list(metadata_digest = "m"))
  data_specs <- wise_batch_unique(grid, "data")
  expect_setequal(names(data_specs[[1]]$spec), c("schema_version", "source", "sample", "outcome", "stats"))

  data_file <- withr::local_tempfile(fileext = ".qs2")
  writeLines("a", data_file)
  frame_specs <- wise_batch_unique(grid, "frame", data_specs, data_file)
  expect_setequal(names(frame_specs[[1]]$spec), c("source", "weather", "seed"))
  wx <- wise_batch_unique(grid, "weather", data_specs, data_file)
  expect_setequal(names(wx[[1]]$spec$weather), c("tx", "hist_years"))

  # A rebuilt data file changes the items that read it, so their branches rerun.
  before <- list(frame_specs, wx)
  writeLines("a rebuilt file", data_file)
  expect_false(identical(wise_batch_unique(grid, "frame", data_specs, data_file), before[[1]]))
  expect_false(identical(wise_batch_unique(grid, "weather", data_specs, data_file), before[[2]]))

  frame_file <- withr::local_tempfile(fileext = ".qs2")
  writeLines("f", frame_file)
  fit_specs <- wise_batch_unique(grid, "fit", data_specs, data_file, frame_specs, frame_file)
  expect_setequal(names(fit_specs[[1]]$spec), c("sample", "model", "seed"))
  fit_before <- fit_specs
  writeLines("a rebuilt frame", frame_file)
  expect_false(identical(
    wise_batch_unique(grid, "fit", data_specs, data_file, frame_specs, frame_file), fit_before
  ))
})

test_that("the data digest hashes the files of the runs' economies and reuses cached digests", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "microdata"))
  for (f in c("BFA_2021_a.parquet", "BFA_2018_a.parquet", "MWI_2019_a.parquet")) {
    writeLines(f, file.path(root, "microdata", f))
  }
  runs <- tibble::tibble(spec = list(list(sample = list(countries = "BFA"))))

  d <- .batch_data_digest(root, runs)
  expect_identical(d$file, c("BFA_2018_a.parquet", "BFA_2021_a.parquet"))
  expect_identical(d$dir, rep("microdata", 2L))
  expect_identical(
    d$sha256[2], digest::digest(file = file.path(root, "microdata", "BFA_2021_a.parquet"), algo = "sha256")
  )

  # Weather files of the economy are listed under their own folders.
  for (f in c("historical/BFA/BFA_era5land.parquet", "projections/BFA/BFA_cmip6_ssp370.parquet")) {
    dir.create(file.path(root, "hazard", "weather", dirname(f)), recursive = TRUE)
    writeLines(f, file.path(root, "hazard", "weather", f))
  }
  w <- .batch_data_digest(root, runs)
  expect_identical(w$dir, c(rep("microdata", 2L), .BATCH_WEATHER_DIRS))
  expect_identical(w$file[3:4], c("BFA/BFA_era5land.parquet", "BFA/BFA_cmip6_ssp370.parquet"))
  unlink(file.path(root, "hazard"), recursive = TRUE)
  expect_match(d$sha256, "^[0-9a-f]{64}$")

  # No local folder, no microdata folder or no file of the economy: no digest.
  expect_null(.batch_data_digest("", runs))
  expect_null(.batch_data_digest(withr::local_tempdir(), runs))
  expect_null(.batch_data_digest(root, tibble::tibble(spec = list(list(sample = list(countries = "SEN"))))))

  # A cached digest is reused while size and time are unchanged, and dropped when
  # the file changes.
  cache <- file.path(root, "digest.rds")
  first <- .batch_data_digest(root, runs, cache_file = cache)
  expect_identical(first, d)
  stored <- readRDS(cache)
  stored[["microdata/BFA_2021_a.parquet"]]$sha256 <- strrep("0", 64)
  saveRDS(stored, cache)
  expect_identical(.batch_data_digest(root, runs, cache_file = cache)$sha256[2], strrep("0", 64))
  writeLines("changed content", file.path(root, "microdata", "BFA_2021_a.parquet"))
  expect_false(identical(.batch_data_digest(root, runs, cache_file = cache)$sha256[2], strrep("0", 64)))
})

test_that("a table is replaced as a whole and an empty table removes the old one", {
  skip_if_not_installed("arrow")
  out <- withr::local_tempdir()
  tab <- data.frame(code = c("BFA", "MWI"), value = 1:2)
  .write_table(tab, out, "t")
  expect_setequal(list.files(file.path(out, "tables")), "t")
  expect_identical(nrow(arrow::open_dataset(file.path(out, "tables", "t")) |> dplyr::collect()), 2L)
  .write_table(tab[1, ], out, "t")
  expect_identical(nrow(arrow::open_dataset(file.path(out, "tables", "t")) |> dplyr::collect()), 1L)
  expect_setequal(list.files(file.path(out, "tables")), "t")
  .write_table(NULL, out, "t")
  expect_length(list.files(file.path(out, "tables")), 0L)
})

test_that("the reproducibility check runs on a manifest with unrecorded values", {
  skip_on_cran()
  skip_if_not_installed("pkgload")
  root <- testthat::test_path("..", "..")
  skip_if(!file.exists(file.path(root, "inst", "batch", "check_reproducibility.R")), "source tree only")
  proj <- withr::local_tempdir()
  dir.create(file.path(proj, "results"))
  # The commit and the renv lock hash are null when the run could not record them.
  writeLines(
    '{"wiseapp_version":"0.3.0","wiseapp_git_sha":null,"r_version":"4.5.3","duckdb_version":"1.5.6","renv_lock_sha256":null}',
    file.path(proj, "results", "manifest.json")
  )
  code <- sprintf(
    "pkgload::load_all('%s', quiet = TRUE); source('%s')",
    normalizePath(root), normalizePath(file.path(root, "inst", "batch", "check_reproducibility.R"))
  )
  out <- withr::with_dir(proj, suppressWarnings(
    system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)), stdout = TRUE, stderr = TRUE)
  ))
  txt <- paste(out, collapse = "\n")
  expect_false(grepl("differing number of rows", txt))
  expect_match(txt, "wiseapp commit")
  expect_match(txt, "renv.lock")
})

test_that("the data work item carries the fingerprints of its countries' survey files", {
  spec <- wise_spec(sample = list(countries = "BFA"))
  ids <- wise_spec_ids(spec)
  runs <- tibble::tibble(
    data_id = ids$data_id, weather_id = ids$weather_id, fit_id = ids$fit_id,
    sim_id = ids$sim_id, policy_id = ids$policy_id, wxvar_ids = list(ids$wxvar_ids), spec = list(spec)
  )
  files <- function(sha) {
    data.frame(
      dir = "microdata", file = c("BFA/BFA_2018_EHCVM_hh.parquet", "NER/NER_2018_X_hh.parquet"),
      sha256 = c(sha, "n")
    )
  }
  item <- function(sha) {
    wise_batch_unique(list(runs = runs, source = list(metadata_digest = "m"), data_files = files(sha)), "data")
  }
  expect_identical(item("a"), item("a"))
  expect_false(identical(item("a"), item("b")))
  expect_identical(item("a")[[1]]$survey_files$file, "BFA/BFA_2018_EHCVM_hh.parquet")

  # Another country's file does not rerun this item.
  other <- files("a")
  other$sha256[2] <- "changed"
  expect_identical(
    item("a"),
    wise_batch_unique(list(runs = runs, source = list(metadata_digest = "m"), data_files = other), "data")
  )
})

test_that("weather items carry the fingerprints of their countries' weather files", {
  spec <- wise_spec(sample = list(countries = "BFA"), weather = list(tx = list()), model = list(), sim = list())
  ids <- wise_spec_ids(spec)
  runs <- tibble::tibble(
    data_id = ids$data_id, weather_id = ids$weather_id, fit_id = ids$fit_id,
    sim_id = ids$sim_id, policy_id = ids$policy_id, wxvar_ids = list(ids$wxvar_ids), spec = list(spec)
  )
  files <- function(hist, proj, survey = "s") {
    data.frame(
      dir = c("microdata", .BATCH_WEATHER_DIRS, .BATCH_WEATHER_DIRS),
      file = c(
        "hh/BFA/BFA_2018_X_hh.parquet", "BFA/BFA_era5land.parquet", "BFA/BFA_cmip6_ssp370.parquet",
        "NER/NER_era5land.parquet", "NER/NER_cmip6_ssp370.parquet"
      ),
      sha256 = c(survey, hist, proj, "n", "n")
    )
  }
  data_file <- withr::local_tempfile(fileext = ".qs2")
  writeLines("a", data_file)
  grid <- function(...) list(runs = runs, source = list(metadata_digest = "m"), data_files = files(...))
  stages <- function(g) {
    ds <- wise_batch_unique(g, "data")
    list(
      data = ds,
      weather = wise_batch_unique(g, "weather", ds, data_file),
      frame = wise_batch_unique(g, "frame", ds, data_file)
    )
  }
  base <- stages(grid("h1", "p1"))
  expect_identical(base$weather[[1]]$weather_files$file, "BFA/BFA_era5land.parquet")

  # A rebuilt historical file reruns the weather and frame items, not the data item.
  hist <- stages(grid("h2", "p1"))
  expect_identical(hist$data, base$data)
  expect_false(identical(hist$weather, base$weather))
  expect_false(identical(hist$frame, base$frame))

  # A rebuilt projection file reaches the simulation items only.
  proj <- stages(grid("h1", "p2"))
  expect_identical(proj, base)

  # A rebuilt survey file reruns the data item.
  expect_false(identical(stages(grid("h1", "p1", survey = "s2"))$data, base$data))
})

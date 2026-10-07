
# CR-PERF-09: list only the selected unit's folder.
test_that("list_available_files restricts the listing to microdata/<unit>/", {
  root <- withr::local_tempdir()
  for (f in c("microdata/hh/BFA/a.parquet", "microdata/ind/BFA/b.parquet", "other/c.csv")) {
    dir.create(file.path(root, dirname(f)), recursive = TRUE, showWarnings = FALSE)
    file.create(file.path(root, f))
  }
  cp <- list(type = "local", path = root)
  expect_setequal(list_available_files(cp, "hh"), "microdata/hh/BFA/a.parquet")
  expect_identical(list_available_files(cp, "firm"), character(0))
  expect_length(list_available_files(cp), 3L)
  sl <- data.frame(code = "BFA", year = 2018, survname = "x", source = "y", level = "hh")
  sv <- build_survey_fnames(sl, "hh", cp)
  expect_identical(nrow(filter_surveys_to_available(sv, list_available_files(cp, "hh"))), 0L)
  dir.create(dirname(file.path(root, sv$fname)), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(root, sv$fname))
  expect_identical(nrow(filter_surveys_to_available(sv, list_available_files(cp, "hh"))), 1L)
})

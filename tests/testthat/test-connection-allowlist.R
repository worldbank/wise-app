library(testthat)

# CR-SEC-02: server-side allowlists for sources and user-entered locations.

test_that("every source is enabled for local and dev runs", {
  withr::local_envvar(c(RSTUDIO_PRODUCT = "", WISEAPP_DATA_SOURCE = "",
                        WISEAPP_ALLOWED_SOURCES = ""))
  expect_setequal(.allowed_connection_types(),
                  c("local", "s3", "gcs", "azure", "hf", "databricks"))
})

test_that("Posit Connect defaults to Databricks only", {
  withr::local_envvar(c(RSTUDIO_PRODUCT = "CONNECT", WISEAPP_DATA_SOURCE = "",
                        WISEAPP_ALLOWED_SOURCES = ""))
  expect_identical(.allowed_connection_types(), "databricks")
  expect_error(build_connection_params("local", path = "/tmp"), "not enabled")
  expect_false(validate_connection_params(list(type = "s3", bucket = "b")))
})

test_that("a configured automatic source is the only enabled type", {
  withr::local_envvar(c(RSTUDIO_PRODUCT = "", WISEAPP_DATA_SOURCE = "s3",
                        WISEAPP_ALLOWED_SOURCES = ""))
  expect_identical(.allowed_connection_types(), "s3")
})

test_that("WISEAPP_ALLOWED_SOURCES overrides the defaults", {
  withr::local_envvar(c(RSTUDIO_PRODUCT = "CONNECT", WISEAPP_DATA_SOURCE = "",
                        WISEAPP_ALLOWED_SOURCES = "databricks, s3"))
  expect_setequal(.allowed_connection_types(), c("databricks", "s3"))
})

test_that("UI locations are checked against the allowlists", {
  withr::local_envvar(c(
    RSTUDIO_PRODUCT = "", WISEAPP_DATA_SOURCE = "", WISEAPP_ALLOWED_SOURCES = "",
    WISEAPP_ALLOWED_LOCAL_ROOTS = "/srv/data",
    WISEAPP_ALLOWED_BUCKETS = "wise-ok",
    WISEAPP_ALLOWED_VOLUME_ROOTS = "/Volumes/cat/sch/vol"
  ))
  ui <- function(type, ...) build_connection_params(type, ...)

  expect_silent(.assert_connection_allowed(ui("local", path = "/srv/data/bfa")))
  expect_error(.assert_connection_allowed(ui("local", path = "/etc")), "folder")
  expect_error(.assert_connection_allowed(ui("local", path = "/srv/data/../etc")),
               "\\.\\.")
  expect_error(.assert_connection_allowed(ui("local", path = "/srv/database")),
               "folder")

  expect_silent(.assert_connection_allowed(ui("s3", s3_bucket = "wise-ok")))
  expect_error(.assert_connection_allowed(ui("s3", s3_bucket = "other")), "bucket")

  expect_silent(.assert_connection_allowed(ui(
    "databricks", db_workspace = "https://x.cloud.databricks.com",
    db_volume_path = "/Volumes/cat/sch/vol/microdata")))
  expect_error(.assert_connection_allowed(ui(
    "databricks", db_workspace = "https://x.cloud.databricks.com",
    db_volume_path = "/Volumes/cat/sch/volume2")), "volume")
  expect_error(.assert_connection_allowed(ui("s3", s3_bucket = "wise-ok",
    s3_prefix = "a\nb")), "control")
  expect_false(validate_connection_params(ui("s3", s3_bucket = "other")))
})

test_that("environment-origin connections are operator configuration", {
  withr::local_envvar(c(
    RSTUDIO_PRODUCT = "", WISEAPP_DATA_SOURCE = "", WISEAPP_ALLOWED_SOURCES = "",
    WISEAPP_ALLOWED_BUCKETS = "wise-ok", S3_BUCKET = "operator-bucket"
  ))
  params <- build_connection_params("s3")
  expect_identical(params$origin, "env")
  expect_silent(.assert_connection_allowed(params))
})

test_that("load_data refuses a disallowed UI connection before reading", {
  withr::local_envvar(c(RSTUDIO_PRODUCT = "", WISEAPP_DATA_SOURCE = "",
                        WISEAPP_ALLOWED_SOURCES = "",
                        WISEAPP_ALLOWED_LOCAL_ROOTS = "/srv/data"))
  expect_error(
    load_data("x.csv", build_connection_params("local", path = "/etc")),
    "not allowed"
  )
})

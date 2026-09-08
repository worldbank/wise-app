# ============================================================================ #
# tests/testthat/test-fct_weather_pipeline.R                                   #
# Weather pipeline card: spec row -> stage labels/glyphs, and the assembled    #
# card rows (no "div" leak, stage order, history row).                         #
# ============================================================================ #

library(testthat)

make_wx_row <- function(...) {
  args <- list(
    name = "tx", label = "Monthly max temperature", units = "degC",
    ref_start = 1L, ref_end = 6L, temporalAgg = "Mean",
    transformation = "Deviation from mean", cont_binned = "Binned",
    num_bins = 5L, binning_method = "Equal width",
    custom_breaks = list(numeric(0)), polynomial = list(character(0))
  )
  args[names(list(...))] <- list(...)
  tibble::tibble(!!!args)
}

test_that("weather_ref_label formats single and ranged windows", {
  expect_identical(weather_ref_label(1, 1), "1 month before interview")
  expect_identical(weather_ref_label(2, 2), "2 months before interview")
  expect_identical(weather_ref_label(1, 6), "1-6 months before interview")
  expect_true(is.na(weather_ref_label(NA_integer_, 3)))
})

test_that("weather_form_label covers bins, custom breaks and polynomials", {
  expect_identical(
    weather_form_label("Binned", 5L, "Equal width"),
    "5 equal-width bins"
  )
  expect_identical(
    weather_form_label("Binned", 5L, "Equal frequency"),
    "5 equal-frequency bins"
  )
  expect_identical(
    weather_form_label("Binned", NA, "Custom", custom_breaks = c(20, 25, 30)),
    "4 custom bins"
  )
  expect_identical(weather_form_label("Continuous", NA, NA), "continuous")
  expect_identical(
    weather_form_label("Continuous", NA, NA, polynomial = "2"),
    "continuous \u00B7 quadratic"
  )
  expect_identical(
    weather_form_label("Continuous", NA, NA, polynomial = c("3", "2")),
    "continuous \u00B7 quadratic + cubic"
  )
})

test_that("weather_pipeline_stages maps spec row to window-agg-transform-form", {
  st <- weather_pipeline_stages(make_wx_row())
  expect_length(st, 4)
  expect_identical(st[[1]]$label, "1-6 months before interview")
  expect_identical(st[[2]]$label, "Mean")
  expect_identical(st[[2]]$symbol, "x\u0304")
  expect_identical(st[[3]]$label, "Deviation from mean")
  expect_true(inherits(st[[1]]$glyph, c("shiny.tag", "html")))
  expect_true(inherits(st[[4]]$glyph, c("shiny.tag", "html")))
  expect_identical(st[[4]]$label, "5 equal-width bins")

  # Single-month window: aggregation stage is dropped (a 1-month window has
  # nothing to aggregate), transformation "None" skipped.
  st2 <- weather_pipeline_stages(make_wx_row(
    ref_start = 1L, ref_end = 1L, temporalAgg = "Sum",
    transformation = "None", cont_binned = "Continuous",
    polynomial = list("2")
  ))
  expect_length(st2, 2)
  expect_identical(st2[[1]]$label, "1 month before interview")
  expect_identical(st2[[2]]$label, "continuous \u00B7 quadratic")

  # Multi-month + standardized anomaly picks the band glyph, custom breaks
  # size the steps.
  st3 <- weather_pipeline_stages(make_wx_row(
    transformation = "Standardized anomaly",
    cont_binned = "Binned", binning_method = "Custom",
    custom_breaks = list(c(20, 25))
  ))
  expect_length(st3, 4)
  expect_identical(st3[[3]]$label, "Standardized anomaly")
  expect_identical(st3[[4]]$label, "3 custom bins")
})

test_that("weather_pipeline_rows builds one row per variable, no history row", {
  sw <- dplyr::bind_rows(
    make_wx_row(),
    make_wx_row(name = "pr", label = "Monthly precipitation", units = "mm",
                ref_end = 1L, temporalAgg = "Sum",
                transformation = "Standardized anomaly",
                cont_binned = "Continuous", polynomial = list("2")),
    make_wx_row(name = "spei6", label = "Monthly SPEI-6", units = NA_character_)
  )
  rows <- weather_pipeline_rows(sw)
  expect_length(rows, 3)
  html <- paste(as.character(rows), collapse = " ")
  expect_match(html, "Max temperature", fixed = TRUE)   # "Monthly" stripped
  expect_match(html, "Precipitation", fixed = TRUE)
  expect_match(html, "tx \u00B7 degC", fixed = TRUE)
  # NA units fall back to the raw name only
  expect_match(html, "spei6", fixed = TRUE)
  expect_false(grepl("NA \u00B7|\\bNA\\b", html))
  expect_match(html, "selection-card-stage", fixed = TRUE)
  expect_false(grepl(">div<", html))
})

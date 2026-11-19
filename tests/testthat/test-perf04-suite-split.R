# R2-PERF-04: line-free and line-dependent metrics are cached as separate suites.

.perf04_pipeline <- function(n = 60L, years = 2030:2033) {
  set.seed(4)
  ids <- rep(seq_len(n), times = length(years))
  list(
    y_point = rnorm(length(ids), log(4), 0.4), F_loading = NULL,
    sim_year = rep(years, each = n), weight = runif(length(ids), 0.5, 2),
    id_vec = ids, svy_row_id = ids
  )
}

.perf04_suite <- function(methods, pov) {
  aggregate_pipeline_tables_multi(
    pipelines = .perf04_pipeline(), methods = methods, weighted = TRUE,
    pov_lines = setNames(lapply(methods, function(m) pov), methods),
    residuals = "none", is_log = TRUE, band_q = c(lo = 0.10, hi = 0.90),
    skip_coef = TRUE, model_ids = "Historical", scenario = "Historical"
  )
}

test_that("suite groups follow the metric registry", {
  all_methods <- c("mean", "median", "total", "headcount_ratio", "gap", "fgt2",
    "gini", "prosperity_gap", "avg_poverty")
  free <- .aggregation_suite_group("mean", all_methods)
  expect_false(free$poverty_dependent)
  expect_setequal(free$methods, c("mean", "median", "total", "gini", "avg_poverty", "prosperity_gap"))
  dep <- .aggregation_suite_group("gap", all_methods)
  expect_true(dep$poverty_dependent)
  expect_setequal(dep$methods, c("headcount_ratio", "gap", "fgt2"))
})

test_that("split suites are bit-identical to the full suite", {
  all_methods <- c("mean", "median", "total", "headcount_ratio", "gap", "fgt2",
    "gini", "prosperity_gap", "avg_poverty")
  full <- .perf04_suite(all_methods, 3)
  for (method in c("mean", "gap")) {
    group <- .aggregation_suite_group(method, all_methods)
    split <- .perf04_suite(group$methods, 3)
    for (m in group$methods) expect_identical(split[[m]], full[[m]], info = m)
  }
})

test_that("a poverty-line change leaves the line-free group unchanged", {
  all_methods <- c("mean", "median", "total", "headcount_ratio", "gap", "fgt2",
    "gini", "prosperity_gap", "avg_poverty")
  free <- .aggregation_suite_group("mean", all_methods)$methods
  expect_identical(.perf04_suite(free, 3), .perf04_suite(free, 5))
  expect_false(identical(.perf04_suite("headcount_ratio", 3)$headcount_ratio,
    .perf04_suite("headcount_ratio", 5)$headcount_ratio))
})

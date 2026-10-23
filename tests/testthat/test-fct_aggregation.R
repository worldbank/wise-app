# R2-PERF-04: the per-year table is built in one tibble() call. It must equal
# the row-wise tibble()/bind_rows() construction it replaced.

legacy_rows_table <- function(rows, method, weighted, scenario = NULL) {
  built <- lapply(rows, function(r) {
    if (is.null(r)) return(NULL)
    row <- tibble::tibble(
      sim_year     = r$sim_year,
      value        = r$value,
      model_id     = list(r$model_id),
      value_all    = list(r$value_all),
      value_all_sd = list(r$value_all_sd),
      F_agg_all    = list(r$F_agg_all),
      var_within   = r$var_within,
      var_across   = r$var_across,
      agg_method   = method,
      weighted     = weighted
    )
    if (!is.null(scenario)) row$scenario <- scenario
    row
  })
  dplyr::bind_rows(Filter(Negate(is.null), built))
}

make_row <- function(year, n_models, with_gradient) {
  ids <- paste0("m", seq_len(n_models))
  vals <- stats::setNames(seq_len(n_models) + year / 1000, ids)
  list(
    sim_year = year,
    value = mean(vals),
    model_id = ids,
    value_all = vals,
    value_all_sd = stats::setNames(sqrt(vals), ids),
    F_agg_all = if (with_gradient) {
      matrix(seq_len(n_models * 3L) / 7, nrow = n_models)
    } else {
      NULL
    },
    var_within = 0.5 + year / 1e4,
    var_across = if (n_models > 1L) 0.25 else 0
  )
}

test_that(".aggregation_assemble_rows equals the row-wise construction", {
  years <- 2030:2034
  for (gradient in c(FALSE, TRUE)) {
    rows <- lapply(years, make_row, n_models = 3L, with_gradient = gradient)
    for (scenario in list(NULL, "SSP2-4.5 / 2030-2034")) {
      expect_identical(
        .aggregation_assemble_rows(rows, "mean", TRUE, scenario),
        legacy_rows_table(rows, "mean", TRUE, scenario)
      )
    }
  }
})

test_that(".aggregation_assemble_rows handles a single row, skipped years and none", {
  one <- list(make_row(2030L, 1L, FALSE))
  expect_identical(
    .aggregation_assemble_rows(one, "gini", FALSE),
    legacy_rows_table(one, "gini", FALSE)
  )
  gappy <- list(make_row(2030L, 2L, TRUE), NULL, make_row(2032L, 2L, FALSE))
  expect_identical(
    .aggregation_assemble_rows(gappy, "gap", TRUE, "S"),
    legacy_rows_table(gappy, "gap", TRUE, "S")
  )
  expect_identical(
    .aggregation_assemble_rows(list(NULL, NULL), "mean", TRUE),
    legacy_rows_table(list(NULL, NULL), "mean", TRUE)
  )
  expect_equal(nrow(.aggregation_assemble_rows(list(), "mean", TRUE)), 0L)
})

test_that("shared aggregation cache keys differ by seed, default 123", {
  key <- function(...) {
    shared_aggregation_cache_key(list(run = 1), 3, 0.05, TRUE, "normal",
      FALSE, TRUE, c("mean", "gini"), ...)
  }
  expect_identical(key(), key(seed = 123L))
  expect_false(identical(key(seed = 123L), key(seed = 7L)))
})

test_that("a precomputed resid_pos gives the same residuals as the id match", {
  ta <- data.frame(hhid = c(10L, 20L, 30L), .resid = c(0.1, -0.2, 0.3))
  lookup <- .residual_lookup(ta, "hhid")
  ids <- c(30L, 99L, 10L, NA, 20L, 98L, 10L)
  pos <- match(as.character(ids), names(lookup))
  direct <- draw_residuals_vec("original", ta, length(ids), ids, "hhid",
    resid_lookup = lookup)
  viaPos <- draw_residuals_vec("original", ta, length(ids), ids, "hhid",
    resid_lookup = lookup, resid_pos = pos)
  expect_identical(viaPos, direct)
  expect_equal(direct[c(1L, 3L, 5L)], c(0.3, 0.1, -0.2))
})

test_that("preparation rows are the ascending row indices of each year", {
  pipe <- list(
    sim_year = c(2031L, 2030L, 2031L, 2030L, 2032L, 2030L),
    y_point = log(c(1, 2, 3, 4, 5, 6)), weight = rep(1, 6),
    id_vec = 1:6, id_col = "hhid"
  )
  ta <- data.frame(hhid = 1:6, .resid = rep(0, 6))
  prep <- .aggregation_prepare_pipeline(pipe, ta, "hhid", "original", 1L, TRUE)
  expect_identical(prep$years, c(2030L, 2031L, 2032L))
  expect_identical(prep$rows, list(c(2L, 4L, 6L), c(1L, 3L), 5L))
})

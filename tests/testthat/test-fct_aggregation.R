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

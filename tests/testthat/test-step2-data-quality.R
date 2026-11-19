# Step 2 tells the user how many rows were left out of the results.
test_that("data-quality tally counts NA predictions, NA weights and bad loadings", {
  dq <- list(n_predictions = 0, n_na_predictions = 0, n_na_weight = 0, n_bad_loading = 0)
  hist <- list(y_point = c(1, NA, 3, 4), weight = c(1, 1, NA, 1),
               F_loading = matrix(c(1, 2, 3, NA, 1, 1, 1, 1), 4, 2))
  member <- list(y_point = c(1, 2, NA, NA), weight = c(NA, NA, NA, NA),
                 F_loading = matrix(1, 4, 2))
  dq <- .step2_data_quality_add(dq, hist, TRUE)
  dq <- .step2_data_quality_add(dq, member, FALSE)
  expect_identical(dq$n_predictions, 8)
  expect_identical(dq$n_na_predictions, 3)
  expect_identical(dq$n_na_weight, 1)  # historical pipeline only
  expect_identical(dq$n_bad_loading, 1)
})

test_that("the notice is NULL when clean and names each exclusion otherwise", {
  clean <- list(n_predictions = 100, n_na_predictions = 0, n_na_weight = 0, n_bad_loading = 0)
  expect_null(step2_data_quality_notice(clean))
  expect_null(step2_data_quality_notice(NULL))
  msg <- step2_data_quality_notice(list(
    n_predictions = 31e6, n_na_predictions = 735150, n_na_weight = 12, n_bad_loading = 5
  ))
  expect_match(msg, "735,150 household-year predictions \\(2.4%\\)")
  expect_match(msg, "12 survey rows with a missing weight")
  expect_match(msg, "5 rows have missing coefficient loadings")
})

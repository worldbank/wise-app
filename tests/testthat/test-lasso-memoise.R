# R2-PERF-11: identical LASSO inputs reuse the previous selection.
test_that(".memoise_last recomputes only when the key changes", {
  cache <- new.env(parent = emptyenv())
  calls <- 0L
  f <- function() { calls <<- calls + 1L; calls }
  expect_identical(.memoise_last(cache, "a", f), 1L)
  expect_identical(.memoise_last(cache, "a", f), 1L)
  expect_identical(.memoise_last(cache, "b", f), 2L)
  expect_identical(.memoise_last(cache, "a", f), 3L)
  expect_error(.memoise_last(cache, "c", function() stop("boom")), "boom")
  expect_identical(.memoise_last(cache, "a", f), 3L)
})

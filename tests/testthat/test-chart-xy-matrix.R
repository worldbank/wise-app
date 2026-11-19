# CR-PERF-08: large point series are [x, y] matrices (JSON arrays of pairs).
test_that(".e_xy_matrix gives an unnamed two-column numeric matrix", {
  m <- .e_xy_matrix(c(a = 1, b = 2L), c(3, NA))
  expect_identical(dim(m), c(2L, 2L))
  expect_null(dimnames(m))
  expect_match(as.character(htmlwidgets:::toJSON(m)), "^\\[\\[1,3\\],\\[2,null\\]\\]$")
})

test_that("residual panels serialise points as pairs and thin the trend line", {
  set.seed(3)
  n <- 2000
  d <- data.frame(y = rnorm(n), x = rnorm(n), g = sample(letters, n, TRUE))
  ch <- echart_residual_panels(fixest::feols(y ~ x | g, d))
  s <- ch$x$opts$series
  expect_true(is.matrix(s[[1]]$data))
  expect_identical(dim(s[[1]]$data), c(as.integer(n), 2L))
  trend <- Filter(function(z) identical(z$name, "Trend"), s)[[1]]
  expect_lte(nrow(trend$data), 300L)
  expect_true(is.matrix(s[[length(s)]]$data))
  expect_match(as.character(htmlwidgets:::toJSON(s[[1]]$data)), "^\\[\\[")
})

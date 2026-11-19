# wise_math() must be served from inst/math_cache.json so the deployed app
# does not need {katex}/V8. Regenerate with dev/make_math_cache.R.

math_literals <- function() {
  files <- list.files(testthat::test_path("..", "..", "R"), "\\.R$", full.names = TRUE)
  unique(unlist(lapply(files, function(f) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    m <- regmatches(txt, gregexpr("wise_math\\(\"(?:[^\"\\\\]|\\\\.)*\"", txt, perl = TRUE))[[1]]
    vapply(m, function(s) eval(parse(text = sub("^wise_math\\(", "", s))), character(1))
  })))
}

fresh_math_cache <- function() {
  rm(list = ls(wiseapp:::.katex_cache, all.names = TRUE), envir = wiseapp:::.katex_cache)
  wiseapp:::.math_cache_load()
  sort(ls(wiseapp:::.katex_cache, all.names = TRUE))
}

test_that("every wise_math() string is in the pre-rendered cache", {
  skip_if_not(dir.exists(testthat::test_path("..", "..", "R")))
  before <- fresh_math_cache()
  for (tex in math_literals()) wise_math(tex)
  welfare_equation_ui(FALSE)
  welfare_equation_ui(TRUE)
  expect_identical(sort(ls(wiseapp:::.katex_cache, all.names = TRUE)), before)
})

test_that("cached HTML matches a live katex render", {
  skip_if_not_installed("katex")
  fresh_math_cache()
  out <- as.character(wise_math("X_{ijt}"))
  live <- as.character(katex::katex_html("X_{ijt}", displayMode = FALSE, include_css = FALSE))
  expect_identical(out, live)
})

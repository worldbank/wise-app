# CR-SEC-09: the app's own code carries no inline script, so a CSP can drop
# 'unsafe-inline' from script-src. Handlers live in inst/app/www/custom.js
# (delegated listeners on data attributes).
test_that("R sources emit no inline script or inline event handler", {
  files <- list.files(testthat::test_path("..", "..", "R"), pattern = "\\.R$", full.names = TRUE)
  skip_if(!length(files), "R/ sources not available (installed package)")
  hits <- unlist(lapply(files, function(f) {
    lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
    lines <- lines[!grepl("^\\s*#", lines)]
    bad <- grepl("tags\\$script\\(|<script|\\bon(click|change|input|load|mouse[a-z]*|key[a-z]*|focus|blur)\\s*=", lines)
    if (any(bad)) paste0(basename(f), ": ", trimws(lines[bad]))
  }))
  expect_identical(hits, NULL)
})

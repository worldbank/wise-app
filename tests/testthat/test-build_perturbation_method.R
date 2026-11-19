test_that("perturbation method is set by variable name, with a unit fallback", {
  sw <- data.frame(
    name = c("t", "tn", "tx", "r", "rx5day", "r20", "tx35", "tr", "mrsos", "spei6"),
    units = c("°C", "°C", "°C", "mm/day", "mm", "days", "days", "days", "kg m-2", NA),
    stringsAsFactors = FALSE
  )
  m <- build_perturbation_method(sw)
  expect_identical(names(m), sw$name)
  expect_identical(unname(m), c("additive", "additive", "additive", "multiplicative", "multiplicative",
    "multiplicative_days", "multiplicative_days", "multiplicative_days", "additive", "additive"))
})

test_that("rainfall is multiplicative whatever its unit is written as", {
  for (u in c("mm/day", "mm", "mm d-1", NA, "")) {
    expect_identical(unname(build_perturbation_method(data.frame(name = "r", units = u))), "multiplicative")
  }
})

test_that("unlisted names fall back to their unit", {
  sw <- data.frame(name = c("pr", "amount", "hot", "temp", "other"),
                   units = c("mm", "mm/day", "days", "degC", "index"), stringsAsFactors = FALSE)
  expect_identical(unname(build_perturbation_method(sw)),
                   c("multiplicative", "multiplicative", "multiplicative_days", "additive", "additive"))
})


test_that("survey_identification_notes flags few locations and missing months (DOC-02)", {
  ok <- data.frame(
    economy = "AAA", year = 2020L, loc_id = rep(1:40, each = 2),
    timestamp = as.Date("2020-01-15") + rep(c(0, 40), 40)
  )
  expect_length(survey_identification_notes(ok), 0L)

  coarse <- ok[ok$loc_id <= 5, ]
  expect_match(survey_identification_notes(coarse), "only 5 location", all = FALSE)

  one_month <- ok
  one_month$timestamp <- as.Date("2020-03-01")
  expect_match(survey_identification_notes(one_month), "single interview month")

  no_month <- ok
  no_month$timestamp <- as.Date(NA)
  expect_match(survey_identification_notes(no_month), "no interview month")
})

skill_fixture <- function() {
  data.frame(
    init_month = c(10L, 10L, 10L, 10L, 5L), lead_month = c(1:4, 1L), level = "country",
    acc = c(0.5, 0.3, 0.1, 0, 0.9), crpss = c(0.2, 0.05, -0.02, -0.05, 0.9), skill_flag = c("useful", "weak", "none", "none", "useful")
  )
}
run <- list(init = as.Date("2026-10-01"))

test_that("the target months map to leads and the worst flag leads the reading", {
  out <- .forecast_skill_summary(skill_fixture()[1:4, ], run, "2026-11", 3L)
  expect_identical(out$months$lead_month, 2:4)
  expect_identical(out$months$skill_flag, c("weak", "none", "none"))
  expect_identical(out$flag, "none")
  expect_true(out$assessed)
  expect_match(out$text, "^No demonstrated hindcast skill: none for Dec 2026, Jan 2027; weak for Nov 2026\\.$")
  # A window crossing the year uses leads 3 to 5 by calendar, not by position.
  one <- .forecast_skill_summary(skill_fixture()[1:4, ], run, "2026-10", 1L)
  expect_identical(one$flag, "useful")
  expect_match(one$text, "^Hindcast skill is useful for Oct 2026\\.$")
})

test_that("a missing table or a missing lead is reported as not assessed", {
  expect_false(.forecast_skill_summary(NULL, run, "2026-11", 3L)$assessed)
  expect_match(.forecast_skill_summary(NULL, run, "2026-11", 3L)$text, "not assessed for this run")
  partial <- .forecast_skill_summary(skill_fixture()[1:2, ], run, "2026-11", 3L)
  expect_false(partial$assessed)
  expect_match(partial$text, "every target month")
})

test_that("the skill table is read for the run's initialization month and the country level", {
  skip_if_not_installed("arrow")
  root <- tempfile("skill-")
  dir.create(file.path(root, "hazard/weather/forecasts/BFA/skill"), recursive = TRUE)
  withr::defer(unlink(root, recursive = TRUE))
  rel <- "hazard/weather/forecasts/BFA/skill/ecmwf_seas51_10_1993_2016.parquet"
  tbl <- rbind(skill_fixture(), transform(skill_fixture()[1, ], level = "BF46", skill_flag = "none"))
  arrow::write_parquet(tbl, file.path(root, rel))
  cp <- list(type = "local", path = root)
  got <- .forecast_skill_table(cp, list(init = as.Date("2026-10-01"), skill_file = rel))
  expect_identical(nrow(got), 4L)
  expect_true(all(got$init_month == 10L & got$level == "country"))
  expect_null(.forecast_skill_table(cp, list(init = as.Date("2026-10-01"), skill_file = NA_character_)))
  expect_null(.forecast_skill_table(cp, list(init = as.Date("2026-10-01"), skill_file = "hazard/weather/forecasts/BFA/skill/none.parquet")))
  expect_null(.forecast_skill_table(cp, list(init = as.Date("2026-07-01"), skill_file = rel)))
})

test_that("a table with several variables is read per variable; the worst flag leads", {
  both <- rbind(
    transform(skill_fixture()[1:2, ], variable = "t"),
    transform(skill_fixture()[1:2, ], variable = "r", skill_flag = c("none", "none"))
  )
  both_out <- .forecast_skill_summary(both, run, "2026-10", 2L)
  expect_identical(both_out$flag, "none")
  expect_identical(unique(both_out$months$variable), c("t", "r"))
  expect_match(both_out$text, "^t: Hindcast skill is weak for Nov 2026; useful for Oct 2026\\. r: No demonstrated")
  # Only the model's own variables count.
  t_only <- .forecast_skill_summary(both, run, "2026-10", 2L, variables = "t")
  expect_identical(t_only$flag, "weak")
  expect_false("variable" %in% names(t_only$months))
})

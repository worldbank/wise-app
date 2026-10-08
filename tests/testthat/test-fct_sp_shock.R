# ============================================================================ #
# tests/testthat/test-fct_sp_shock.R                                           #
# Shock-responsive SP: spec validation (P1-1) and trigger thresholds (P1-2).   #
# ============================================================================ #

library(testthat)

shock_sp <- function(...) {
  utils::modifyList(
    list(sp_type = "shock", transfer_amount_usd = 30, payments_per_activation = 2L,
         trigger_type = "weather", trigger_variable = "temp",
         trigger_direction = "above", trigger_value = 35,
         trigger_return_period_years = NA_real_, payout_scope = "local",
         national_k_pct = 0),
    list(...)
  )
}

# Exposure: two locations x two interview months, `n` years each; temp is
# 1..n shifted per cell so quantiles are hand-checkable.
shock_exposure <- function(n = 30L) {
  g <- expand.grid(loc_id = c("a", "b"), int_month = c(3L, 9L),
                   sim_year = seq_len(n), stringsAsFactors = FALSE)
  g$code <- "BFA"
  g$year <- 2018L
  g$survname <- "EHCVM"
  g$timestamp <- as.Date("2000-01-01") + g$sim_year
  g$temp <- g$sim_year + ifelse(g$loc_id == "b", 100, 0) + g$int_month / 100
  g$cat <- factor(ifelse(g$sim_year > 10, "hot", "mild"))
  g$.policy_exposure_id <- seq_len(nrow(g))
  g
}

# Spec validation (P1-1) ----

test_that("a complete shock spec is valid and has_sp_change is TRUE", {
  expect_null(.sp_shock_problem(shock_sp()))
  expect_true(has_sp_change(shock_sp()))
  expect_null(.sp_shock_problem(shock_sp(
    trigger_type = "return_period", trigger_return_period_years = 10,
    trigger_value = NA_real_, payout_scope = "national_all", national_k_pct = 25
  )))
})

test_that("shock validation names what is missing", {
  expect_match(.sp_shock_problem(shock_sp(trigger_variable = NA_character_)), "variable")
  expect_match(.sp_shock_problem(shock_sp(trigger_value = NA_real_)), "threshold")
  expect_match(.sp_shock_problem(shock_sp(trigger_direction = "left")), "above or below")
  expect_match(
    .sp_shock_problem(shock_sp(trigger_type = "return_period")), "return period"
  )
  expect_match(.sp_shock_problem(shock_sp(payout_scope = "everyone")), "scope")
  expect_match(
    .sp_shock_problem(shock_sp(payout_scope = "national_all", national_k_pct = 140)),
    "between 0 and 100"
  )
  # The gate share is not consulted for local payouts
  expect_null(.sp_shock_problem(shock_sp(national_k_pct = 140)))
})

test_that("shock mode needs amount, payments and a valid trigger", {
  expect_false(has_sp_change(shock_sp(transfer_amount_usd = 0)))
  expect_false(has_sp_change(shock_sp(payments_per_activation = 0L)))
  expect_false(has_sp_change(shock_sp(trigger_value = NA_real_)))
  # Budget mode is ignored in shock mode (decision 12)
  expect_true(has_sp_change(shock_sp(budget_mode = "budget_first", budget_fixed = 0)))
  # Regular programs are unchanged
  reg <- list(budget_mode = "transfer_first", transfer_amount_usd = 20,
              transfer_n_payments = 6L)
  expect_true(has_sp_change(reg))
  expect_false(has_sp_change(utils::modifyList(reg, list(transfer_amount_usd = 0))))
})

test_that("the SP module spec carries the shock fields with safe defaults", {
  svy <- data.frame(welfare = 1:4, weight = 1)
  testServer(mod_3_01_sp_server, args = list(
    id = "sp_shock", survey_weather = shiny::reactiveVal(svy),
    variable_list = shiny::reactiveVal(data.frame()),
    analysis_unit = shiny::reactiveVal("hh"),
    hist_sim = shiny::reactiveVal(NULL)
  ), {
    spec <- sp_scenario_spec()
    expect_identical(spec$trigger_type, "weather")
    expect_true(is.na(spec$trigger_variable))
    expect_identical(spec$trigger_direction, "above")
    expect_true(is.na(spec$trigger_value))
    expect_true(is.na(spec$trigger_return_period_years))
    expect_identical(spec$payout_scope, "local")
    expect_equal(spec$national_k_pct, 0)
    expect_equal(spec$payments_per_activation, 1L)
    # Until the run path applies shock transfers the program stays regular
    session$setInputs(sp_type = "shock")
    expect_identical(sp_scenario_spec()$sp_type, "regular")
  })
})

test_that("changing any shock field changes the policy signature input", {
  base <- shock_sp()
  variants <- list(
    base, shock_sp(trigger_type = "return_period"), shock_sp(trigger_variable = "rain"),
    shock_sp(trigger_direction = "below"), shock_sp(trigger_value = 36),
    shock_sp(trigger_return_period_years = 10), shock_sp(payout_scope = "national_all"),
    shock_sp(national_k_pct = 10), shock_sp(payments_per_activation = 3L)
  )
  sigs <- vapply(variants, function(sp) rlang::hash(.sig_plain(list(sp = sp))), character(1))
  expect_equal(length(unique(sigs)), length(variants))
})

# Trigger thresholds (P1-2) ----

test_that("only continuous weather columns are trigger variables", {
  expect_identical(.sp_trigger_variables(shock_exposure()), "temp")
  expect_identical(.sp_trigger_variables(NULL), character())
  expect_error(
    sp_trigger_thresholds(shock_exposure(), shock_sp(trigger_variable = "cat")),
    "continuous weather variable"
  )
})

test_that("a weather trigger returns the common value", {
  th <- sp_trigger_thresholds(shock_exposure(), shock_sp(trigger_value = 41.5))
  expect_identical(th$type, "weather")
  expect_equal(th$value, 41.5)
  expect_identical(th$direction, "above")
})

test_that("return-period thresholds equal the hand-computed quantile per cell", {
  ex <- shock_exposure(30L)
  th <- sp_trigger_thresholds(ex, shock_sp(
    trigger_type = "return_period", trigger_return_period_years = 10,
    trigger_value = NA_real_
  ))
  tbl <- th$table
  expect_equal(nrow(tbl), 4L)
  expect_true(all(tbl$n_years == 30L & tbl$supported))
  # Cell a / month 3 holds temp = 1.03 .. 30.03, so the 0.9 quantile is 27.13
  row <- tbl[tbl$loc_id == "a" & tbl$int_month == 3L, ]
  expect_equal(row$threshold, unname(stats::quantile(1:30 + 0.03, 0.9)))
  expect_equal(row$threshold, 27.13)
  row_b <- tbl[tbl$loc_id == "b" & tbl$int_month == 9L, ]
  expect_equal(row_b$threshold, unname(stats::quantile(1:30 + 100.09, 0.9)))
  # Same activation probability everywhere: 3 of 30 years sit at or above it
  for (i in seq_len(nrow(tbl))) {
    cell <- ex[ex$loc_id == tbl$loc_id[i] & ex$int_month == tbl$int_month[i], ]
    expect_equal(sum(cell$temp >= tbl$threshold[i]), 3L)
  }
})

test_that("direction below mirrors above", {
  ex <- shock_exposure(40L)
  sp <- shock_sp(trigger_type = "return_period", trigger_return_period_years = 20,
                 trigger_value = NA_real_)
  up <- sp_trigger_thresholds(ex, sp)$table
  ex_neg <- ex
  ex_neg$temp <- -ex$temp
  down <- sp_trigger_thresholds(ex_neg, utils::modifyList(sp, list(trigger_direction = "below")))
  expect_identical(down$direction, "below")
  expect_equal(down$table$threshold, -up$threshold)
  # Low tail: at or below the threshold in 1 in 20 years of a 40-year record
  cell <- ex[ex$loc_id == "a" & ex$int_month == 3L, ]
  low <- sp_trigger_thresholds(ex, utils::modifyList(sp, list(trigger_direction = "below")))$table
  thr <- low$threshold[low$loc_id == "a" & low$int_month == 3L]
  expect_equal(sum(cell$temp <= thr), 2L)
})

test_that("a 1-in-N trigger needs N finite historical years", {
  ex <- shock_exposure(15L)
  sp <- shock_sp(trigger_type = "return_period", trigger_return_period_years = 20,
                 trigger_value = NA_real_)
  expect_error(sp_trigger_thresholds(ex, sp), "needs at least 20 historical years")
  # N equal to the record length is allowed
  ok <- sp_trigger_thresholds(ex, utils::modifyList(sp, list(trigger_return_period_years = 15)))
  expect_true(all(ok$table$supported))
  # Non-finite years do not count; short cells get NA and never fire
  ex$temp[ex$loc_id == "a" & ex$int_month == 3L & ex$sim_year <= 5L] <- NA
  mixed <- sp_trigger_thresholds(ex, utils::modifyList(sp, list(trigger_return_period_years = 15)))$table
  short <- mixed[mixed$loc_id == "a" & mixed$int_month == 3L, ]
  expect_equal(short$n_years, 10L)
  expect_false(short$supported)
  expect_true(is.na(short$threshold))
  expect_equal(sum(mixed$supported), 3L)
})

test_that("an invalid spec is refused with its message", {
  expect_error(
    sp_trigger_thresholds(shock_exposure(), shock_sp(trigger_value = NA_real_)),
    "threshold value"
  )
})

test_that("thresholds do not depend on row order", {
  ex <- shock_exposure(30L)
  sp <- shock_sp(trigger_type = "return_period", trigger_return_period_years = 10,
                 trigger_value = NA_real_)
  a <- sp_trigger_thresholds(ex, sp)$table
  b <- sp_trigger_thresholds(ex[rev(seq_len(nrow(ex))), ], sp)$table
  key <- function(t) t[order(t$loc_id, t$int_month), c("loc_id", "int_month", "threshold", "n_years")]
  expect_equal(key(a), key(b), ignore_attr = TRUE)
})

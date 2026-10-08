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

# Static eligibility in shock mode (P1-4) ----

shock_svy <- function(n = 600, seed = 21) {
  set.seed(seed)
  data.frame(
    welfare = rlnorm(n, 0.6, 0.7), hhsize = sample(1:8, n, replace = TRUE),
    weight = runif(n, 50, 150), proxy = rnorm(n)
  )
}

shock_targeting <- function(...) {
  shock_sp(targeting = "exante_poor", targeting_threshold = 25,
           inclusion_error_pct = 15, exclusion_error_pct = 10,
           transfer_n_payments = 6L, ...)
}

test_that("shock mode writes eligibility and no transfer", {
  svy <- shock_svy()
  out <- apply_policy_to_svy(svy, sp = shock_targeting(), seed = 5L)
  expect_false(SP_TRANSFER_COL %in% names(out))
  expect_type(out[[SP_ELIGIBLE_COL]], "logical")
  expect_equal(length(out[[SP_ELIGIBLE_COL]]), nrow(svy))
  expect_true(any(out[[SP_ELIGIBLE_COL]]) && !all(out[[SP_ELIGIBLE_COL]]))
})

test_that("shock eligibility equals the regular program's for the same seed", {
  svy <- shock_svy()
  reg <- apply_policy_to_svy(
    svy, sp = shock_targeting(sp_type = "regular", budget_mode = "transfer_first"),
    seed = 5L
  )
  shk <- apply_policy_to_svy(svy, sp = shock_targeting(), seed = 5L)
  expect_identical(shk[[SP_ELIGIBLE_COL]], reg[[SP_TRANSFER_COL]] > 0)
  # Deterministic per seed, and the seed matters
  again <- apply_policy_to_svy(svy, sp = shock_targeting(), seed = 5L)
  other <- apply_policy_to_svy(svy, sp = shock_targeting(), seed = 6L)
  expect_identical(shk[[SP_ELIGIBLE_COL]], again[[SP_ELIGIBLE_COL]])
  expect_false(identical(shk[[SP_ELIGIBLE_COL]], other[[SP_ELIGIBLE_COL]]))
})

test_that("an invalid shock spec writes nothing, and regular mode is unchanged", {
  svy <- shock_svy()
  bad <- apply_policy_to_svy(svy, sp = shock_targeting(trigger_value = NA_real_), seed = 5L)
  expect_false(any(c(SP_TRANSFER_COL, SP_ELIGIBLE_COL) %in% names(bad)))
  reg <- apply_policy_to_svy(
    svy, sp = shock_targeting(sp_type = "regular", budget_mode = "transfer_first"),
    seed = 5L
  )
  expect_true(SP_TRANSFER_COL %in% names(reg))
  expect_false(SP_ELIGIBLE_COL %in% names(reg))
})

test_that("a shock program with eligible households counts as an effect", {
  svy <- shock_svy()
  out <- apply_policy_to_svy(svy, sp = shock_targeting(), seed = 5L)
  expect_true(.scenario_has_effect(svy, out))
  expect_false(.scenario_has_effect(svy, svy))
})

# Trigger state (P1-3) ----

# Three locations, two years; temps and weights chosen so the exposed share is
# 0.3 in year 1 (only a) and 0.7 in year 2 (a and b).
state_exposure <- function() {
  data.frame(
    loc_id = rep(c("a", "b", "c"), 2), sim_year = rep(1:2, each = 3),
    temp = c(36, 30, 30, 36, 40, 20), weight = rep(c(30, 40, 30), 2)
  )
}

state_run <- function(scope, k = 0, ex = state_exposure()) {
  spec <- shock_sp(payout_scope = scope, national_k_pct = k)
  th <- sp_trigger_thresholds(ex[rep(1, 30), ], spec) # weather type: value only
  sp_trigger_state(ex, th, ex$weight, spec)
}

test_that("exposed share is weighted and by simulation year", {
  st <- state_run("local")
  expect_equal(unname(st$share), c(0.3, 0.7))
  expect_identical(names(st$share), c("1", "2"))
  expect_identical(st$exceeds, c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE))
  # Equal weights when none are given
  spec <- shock_sp()
  th <- sp_trigger_thresholds(state_exposure()[rep(1, 30), ], spec)
  eq <- sp_trigger_state(state_exposure(), th, NULL, spec)
  expect_equal(unname(eq$share), c(1 / 3, 2 / 3))
})

test_that("payout scope truth table, gate fired or not by row exceeds or not", {
  # k = 50: gate fires in year 2 only
  local <- state_run("local", 50)
  expect_identical(local$in_scope, c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE))
  expect_false(any(local$gate))
  trig <- state_run("national_triggered", 50)
  expect_identical(unname(trig$gate), c(FALSE, TRUE))
  expect_identical(trig$in_scope, c(FALSE, FALSE, FALSE, TRUE, TRUE, FALSE))
  all_hh <- state_run("national_all", 50)
  expect_identical(all_hh$in_scope, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE))
  # A gate above the exposed share never fires
  expect_false(any(state_run("national_all", 80)$in_scope))
})

test_that("k = 0 makes national_triggered identical to local", {
  expect_identical(
    state_run("national_triggered", 0)$in_scope, state_run("local")$in_scope
  )
  # The gate needs some exposure, so a year with none stays unpaid
  ex <- state_exposure()
  ex$temp[ex$sim_year == 1] <- 10
  expect_identical(unname(state_run("national_triggered", 0, ex)$gate), c(FALSE, TRUE))
  expect_match(
    .sp_shock_problem(shock_sp(payout_scope = "national_all", national_k_pct = 0)),
    "above 0"
  )
})

test_that("below mirrors above and non-finite values never exceed", {
  ex <- state_exposure()
  ex$temp[2] <- NA
  spec <- shock_sp(trigger_direction = "below", trigger_value = 30)
  th <- sp_trigger_thresholds(ex[rep(1, 30), ], spec)
  st <- sp_trigger_state(ex, th, ex$weight, spec)
  expect_identical(st$exceeds, c(FALSE, FALSE, TRUE, FALSE, FALSE, TRUE))
})

test_that("return-period state fires in 1 of N years per cell and ignores row order", {
  ex <- shock_exposure(30L)
  ex$weight <- 100
  spec <- shock_sp(trigger_type = "return_period", trigger_return_period_years = 10,
                   trigger_value = NA_real_)
  th <- sp_trigger_thresholds(ex, spec)
  st <- sp_trigger_state(ex, th, ex$weight, spec)
  # 4 cells x 3 of 30 years
  expect_equal(sum(st$exceeds), 12L)
  cells <- paste(ex$loc_id, ex$int_month)
  expect_true(all(tapply(st$exceeds, cells, sum) == 3L))
  # Cells without a supported threshold never exceed
  th2 <- th
  th2$table$threshold[th2$table$loc_id == "a" & th2$table$int_month == 3L] <- NA
  st2 <- sp_trigger_state(ex, th2, ex$weight, spec)
  expect_false(any(st2$exceeds[ex$loc_id == "a" & ex$int_month == 3L]))
  # Row order does not change which rows exceed
  ord <- sample(nrow(ex))
  st3 <- sp_trigger_state(ex[ord, ], th, ex$weight[ord], spec)
  expect_identical(st3$exceeds, st$exceeds[ord])
  expect_equal(st3$share, st$share)
})

test_that("trigger state refuses an exposure without what it needs", {
  spec <- shock_sp()
  th <- sp_trigger_thresholds(shock_exposure(), spec)
  expect_error(sp_trigger_state(data.frame(temp = 1), th, NULL, spec), "sim_year")
  rp <- shock_sp(trigger_type = "return_period", trigger_return_period_years = 10,
                 trigger_value = NA_real_)
  th_rp <- sp_trigger_thresholds(shock_exposure(), rp)
  expect_error(
    sp_trigger_state(data.frame(sim_year = 1, temp = 1), th_rp, NULL, rp), "key columns"
  )
  expect_error(
    sp_trigger_state(state_exposure(), th, NULL, shock_sp(payout_scope = "x")), "payout scope"
  )
})

# Dynamic transfer (P1-5) ----

# State for `n_years` years over `n` survey rows, every row in scope or none.
dyn_state <- function(n, n_years = 1L, on = TRUE) {
  list(in_scope = rep(on, n * n_years))
}

dyn_reference <- function(svy, sp, unit = "hh", seed = 5L) {
  reg <- apply_policy_to_svy(
    svy, sp = utils::modifyList(sp, list(sp_type = "regular", budget_mode = "transfer_first",
      transfer_n_payments = sp$payments_per_activation)),
    analysis_unit = unit, seed = seed
  )
  shk <- apply_policy_to_svy(svy, sp = sp, analysis_unit = unit, seed = seed)
  list(transfer = reg[[SP_TRANSFER_COL]], eligible = shk[[SP_ELIGIBLE_COL]])
}

test_that("a trigger that never fires pays nothing", {
  svy <- shock_svy()
  ref <- dyn_reference(svy, shock_targeting())
  out <- sp_dynamic_transfer(dyn_state(nrow(svy), 3L, on = FALSE), ref$eligible,
    shock_targeting(), svy, "hh", rep(seq_len(nrow(svy)), 3L))
  expect_true(all(out == 0))
  expect_equal(length(out), 3L * nrow(svy))
})

test_that("an always-on trigger reproduces the regular program's transfer", {
  svy <- shock_svy()
  svy$ppp2021 <- runif(nrow(svy), 0.8, 1.2)
  variants <- list(
    shock_targeting(),
    shock_targeting(payments_per_activation = 4L, transfer_amount_usd = 55),
    shock_targeting(amount_basis = "per_capita"),
    shock_targeting(currency = "LCU", transfer_amount_usd = 20000)
  )
  for (sp in variants) {
    ref <- dyn_reference(svy, sp)
    ids <- rep(seq_len(nrow(svy)), 2L)
    out <- sp_dynamic_transfer(dyn_state(nrow(svy), 2L), ref$eligible, sp, svy, "hh", ids)
    expect_equal(out, rep(ref$transfer, 2L))
  }
  # Individual analysis units
  sp <- shock_targeting()
  ref <- dyn_reference(svy, sp, unit = "ind")
  out <- sp_dynamic_transfer(dyn_state(nrow(svy)), ref$eligible, sp, svy, "ind",
    seq_len(nrow(svy)))
  expect_equal(out, ref$transfer)
})

test_that("only in-scope rows of eligible households are paid", {
  svy <- shock_svy(n = 6)
  elig <- c(TRUE, TRUE, FALSE, TRUE, NA, FALSE)
  sp <- shock_sp(transfer_amount_usd = 36.5, payments_per_activation = 10L,
                 amount_basis = "per_capita")
  state <- list(in_scope = c(TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE))
  # Prediction rows 1..7 map to survey rows 1,2,3,4,5,6,1
  out <- sp_dynamic_transfer(state, elig, sp, svy, "hh", c(1:6, 1L))
  # 36.5 * 10 / 365 = 1 per person per day
  expect_equal(out, c(1, 0, 0, 1, 0, 0, 1))
  # Per household divides by hhsize
  sp2 <- utils::modifyList(sp, list(amount_basis = "per_household"))
  out2 <- sp_dynamic_transfer(state, elig, sp2, svy, "hh", c(1:6, 1L))
  expect_equal(out2[1], 1 / svy$hhsize[1])
})

test_that("the dynamic transfer rejects misaligned inputs", {
  svy <- shock_svy(n = 5)
  sp <- shock_sp()
  expect_error(sp_dynamic_transfer(dyn_state(5), rep(TRUE, 4), sp, svy, "hh", 1:5),
    "one value per survey row")
  expect_error(sp_dynamic_transfer(dyn_state(5), rep(TRUE, 5), sp, svy, "hh", 1:4),
    "map to survey rows")
  expect_error(sp_dynamic_transfer(dyn_state(5), rep(TRUE, 5), sp, svy, "hh", c(1:4, 9L)),
    "map to survey rows")
})

test_that("the dynamic effect uses the predicted level for log outcomes", {
  y <- log(c(100, 50, NA, NA))
  tr <- c(20, 0, 10, 0)
  eff <- sp_dynamic_effect(y, tr, is_log = TRUE)
  expect_equal(eff[1], log(120) - log(100))
  expect_equal(eff[2], 0)
  expect_true(is.na(eff[3]))
  expect_equal(eff[4], 0)
  # A smaller predicted level gains more in logs for the same transfer
  expect_gt(sp_dynamic_effect(log(50), 20, TRUE), sp_dynamic_effect(log(100), 20, TRUE))
  # Identity outcomes add the transfer directly
  expect_equal(sp_dynamic_effect(c(100, 50), c(20, 0), is_log = FALSE), c(20, 0))
})

test_that("shock transfers equal the regular program's welfare effect (identity outcome)", {
  svy <- shock_svy()
  sp <- shock_targeting()
  ref <- dyn_reference(svy, sp)
  out <- sp_dynamic_transfer(dyn_state(nrow(svy)), ref$eligible, sp, svy, "hh", seq_len(nrow(svy)))
  expect_equal(
    sp_dynamic_effect(svy$welfare, out, FALSE),
    sp_dynamic_effect(svy$welfare, ref$transfer, FALSE)
  )
})

# ============================================================================ #
# tests/testthat/test-sp-design-options.R                                      #
# Social protection design options (plan: review/sp_shock_responsive_plan.md): #
#   P0-2 administration cost, P0-3 per-person amounts, P0-4 error placement.   #
# Defaults must reproduce the earlier behaviour exactly, the preview must      #
# equal the run, and each option must change numbers in the stated direction.  #
# ============================================================================ #

library(testthat)

dsgn_svy <- function(n = 800, seed = 11, weights = TRUE) {
  set.seed(seed)
  df <- data.frame(
    welfare = rlnorm(n, 0.6, 0.7),
    hhsize  = sample(1:8, n, replace = TRUE),
    proxy   = rnorm(n)
  )
  if (weights) df$weight <- runif(n, 50, 150)
  df
}

dsgn_sp <- function(...) {
  utils::modifyList(
    list(budget_mode = "transfer_first", targeting = "exante_poor",
         targeting_threshold = 25, inclusion_error_pct = 15,
         exclusion_error_pct = 10, transfer_amount_usd = 40,
         transfer_n_payments = 6L, budget_fixed = 500000),
    list(...)
  )
}

# The error draw as it was written before error_concentration existed.
dsgn_legacy_eligibility <- function(svy, sp, seed) {
  withr::with_seed(wise_seed(seed, "policy", "sp"), {
    q <- .sp_welfare_quantile(svy$welfare, svy[["weight"]],
                              sp$targeting_threshold / 100)
    eligible <- !is.na(svy$welfare) & svy$welfare <= q
    non_elig <- which(!eligible)
    elig <- which(eligible)
    n_flip <- round(length(non_elig) * sp$inclusion_error_pct / 100)
    eligible[non_elig[sample.int(length(non_elig), min(n_flip, length(non_elig)))]] <- TRUE
    n_flip <- round(length(elig) * sp$exclusion_error_pct / 100)
    eligible[elig[sample.int(length(elig), min(n_flip, length(elig)))]] <- FALSE
    eligible
  })
}

dsgn_run <- function(svy, sp, unit = "hh", seed = 5L) {
  policy <- apply_policy_to_svy(svy, sp = sp, analysis_unit = unit, seed = seed)
  list(
    policy = policy,
    reach = .sp_scenario_reach(svy, sp, unit, seed = seed),
    totals = .sp_transfer_totals(policy, unit, "PPP", .sp_admin_share(sp))
  )
}

# Administration cost (P0-2) ----

test_that("admin cost 0 or absent reproduces the earlier numbers exactly", {
  svy <- dsgn_svy()
  for (mode in c("transfer_first", "budget_first")) {
    base <- dsgn_run(svy, dsgn_sp(budget_mode = mode))
    zero <- dsgn_run(svy, dsgn_sp(budget_mode = mode, admin_cost_pct = 0))
    expect_identical(zero$policy[[SP_TRANSFER_COL]], base$policy[[SP_TRANSFER_COL]])
    expect_identical(zero$reach, base$reach)
    expect_equal(base$reach$admin_cost, 0)
    expect_equal(base$reach$transfer_total, base$totals$total)
  }
})

test_that("amount per payment: admin raises cost, not the transfer", {
  svy <- dsgn_svy()
  a <- 0.20
  base <- dsgn_run(svy, dsgn_sp())
  adm <- dsgn_run(svy, dsgn_sp(admin_cost_pct = 20))
  expect_identical(adm$policy[[SP_TRANSFER_COL]], base$policy[[SP_TRANSFER_COL]])
  net <- base$totals$total
  expect_equal(adm$reach$transfer_cost, net)
  expect_equal(adm$reach$transfer_total, net / (1 - a))
  expect_equal(adm$reach$admin_cost, net * a / (1 - a))
  # The identity: total = transfers + administration, admin = share of total.
  expect_equal(adm$reach$transfer_total, adm$reach$transfer_cost + adm$reach$admin_cost)
  expect_equal(adm$reach$admin_cost / adm$reach$transfer_total, a)
})

test_that("total budget: the budget is total spend and recipients get the net", {
  svy <- dsgn_svy()
  budget <- 600000
  base <- dsgn_run(svy, dsgn_sp(budget_mode = "budget_first", budget_fixed = budget))
  adm <- dsgn_run(svy, dsgn_sp(budget_mode = "budget_first", budget_fixed = budget,
                               admin_cost_pct = 25))
  expect_equal(base$reach$transfer_total, budget)
  expect_equal(adm$reach$transfer_total, budget)
  expect_equal(adm$reach$admin_cost, budget * 0.25)
  v0 <- base$policy[[SP_TRANSFER_COL]]
  v1 <- adm$policy[[SP_TRANSFER_COL]]
  expect_equal(v1, v0 * 0.75)
  # Never exceeds the envelope, also without weights.
  uw <- dsgn_run(dsgn_svy(weights = FALSE),
                 dsgn_sp(budget_mode = "budget_first", budget_fixed = budget,
                         admin_cost_pct = 25))
  expect_equal(uw$reach$transfer_total, budget)
})

test_that("the preview equals the run with admin cost, and admin is clamped", {
  svy <- dsgn_svy()
  sp <- dsgn_sp(admin_cost_pct = 15)
  r <- dsgn_run(svy, sp)
  expect_equal(r$reach$transfer_total, r$totals$total_cost)
  expect_equal(.sp_admin_share(list(admin_cost_pct = -5)), 0)
  expect_equal(.sp_admin_share(list(admin_cost_pct = NA)), 0)
  expect_equal(.sp_admin_share(list(admin_cost_pct = 400)), 0.9)
  expect_equal(.sp_admin_share(list()), 0)
})

# Per-person amounts (P0-3) ----

test_that("per household is the default and equals an explicit setting", {
  svy <- dsgn_svy()
  base <- dsgn_run(svy, dsgn_sp())
  expl <- dsgn_run(svy, dsgn_sp(amount_basis = "per_household"))
  expect_identical(expl$policy[[SP_TRANSFER_COL]], base$policy[[SP_TRANSFER_COL]])
  expect_identical(expl$reach, base$reach)
  expect_identical(.sp_amount_basis(list()), "per_household")
})

test_that("per person: each member receives the amount, cost grows with size", {
  svy <- dsgn_svy()
  amount <- 40; n_pay <- 6
  pc <- dsgn_run(svy, dsgn_sp(amount_basis = "per_capita"))
  ph <- dsgn_run(svy, dsgn_sp())
  v_pc <- pc$policy[[SP_TRANSFER_COL]]
  v_ph <- ph$policy[[SP_TRANSFER_COL]]
  rec <- v_pc > 0
  # Same recipients, welfare gain per person is the whole amount.
  expect_identical(rec, v_ph > 0)
  expect_equal(v_pc[rec], rep(amount * n_pay / 365, sum(rec)))
  expect_equal(v_ph[rec] * svy$hhsize[rec], v_pc[rec])
  # Larger households gain more per household, never less per person.
  expect_gt(pc$reach$transfer_total, ph$reach$transfer_total)
  expect_equal(pc$reach$transfer_per_person, amount * n_pay)
})

test_that("per person with a total budget shares the budget over people", {
  budget <- 500000
  for (weights in c(TRUE, FALSE)) {
    svy <- dsgn_svy(weights = weights)
    r <- dsgn_run(svy, dsgn_sp(budget_mode = "budget_first", budget_fixed = budget,
                               amount_basis = "per_capita", admin_cost_pct = 10))
    expect_equal(r$reach$transfer_total, budget)
    v <- r$policy[[SP_TRANSFER_COL]]
    expect_equal(length(unique(round(v[v > 0], 12))), 1L)
  }
})

test_that("the basis has no effect outside household analysis", {
  svy <- dsgn_svy()
  for (unit in c("ind", "firm")) {
    a <- dsgn_run(svy, dsgn_sp(), unit)
    b <- dsgn_run(svy, dsgn_sp(amount_basis = "per_capita"), unit)
    expect_identical(b$policy[[SP_TRANSFER_COL]], a$policy[[SP_TRANSFER_COL]])
  }
})

# Where targeting errors fall (P0-4) ----

test_that("concentration 0 or absent reproduces the earlier draw exactly", {
  svy <- dsgn_svy(1500)
  seed <- 20260101L
  sp <- dsgn_sp()
  legacy <- dsgn_legacy_eligibility(svy, sp, seed)
  for (spx in list(sp, utils::modifyList(sp, list(error_concentration = 0)))) {
    now <- withr::with_seed(wise_seed(seed, "policy", "sp"),
                            .determine_sp_eligibility(svy, spx))
    expect_identical(now, legacy)
  }
})

test_that("concentration keeps the exact error counts and the seed stream", {
  svy <- dsgn_svy(2000)
  sp <- dsgn_sp(inclusion_error_pct = 20, exclusion_error_pct = 10)
  ideal <- .determine_sp_eligibility(svy, sp, apply_errors = FALSE)
  n_incl <- round(sum(!ideal) * 0.20)
  n_excl <- round(sum(ideal) * 0.10)
  draw <- function(conc, seed = 3L) {
    withr::with_seed(wise_seed(seed, "policy", "sp"),
      .determine_sp_eligibility(svy, utils::modifyList(sp, list(error_concentration = conc))))
  }
  for (conc in c(0, 5, 20)) {
    e <- draw(conc)
    expect_equal(sum(e & !ideal), n_incl)
    expect_equal(sum(!e & ideal), n_excl)
    expect_identical(draw(conc), e)
  }
  expect_false(identical(draw(20, 3L), draw(20, 4L)))
})

test_that("concentration moves flips toward the cutoff", {
  svy <- dsgn_svy(4000)
  sp <- dsgn_sp(inclusion_error_pct = 20, exclusion_error_pct = 20)
  ideal <- .determine_sp_eligibility(svy, sp, apply_errors = FALSE)
  dist <- .sp_cutoff_distance(svy, sp, "exante_poor")
  mean_flip_dist <- function(conc) {
    e <- withr::with_seed(wise_seed(9L, "policy", "sp"),
      .determine_sp_eligibility(svy, utils::modifyList(sp, list(error_concentration = conc))))
    mean(dist[e != ideal])
  }
  d0 <- mean_flip_dist(0); d5 <- mean_flip_dist(5); d20 <- mean_flip_dist(20)
  expect_lt(d5, d0)
  expect_lt(d20, d5)
})

test_that("flips stay uniform where no distance exists", {
  svy <- dsgn_svy(1000)
  svy$flag <- rep(c(0, 1), length.out = nrow(svy))
  sp_bin <- dsgn_sp(targeting = "pmt", pmt_variable = "flag", pmt_cutoff = 1)
  expect_null(.sp_cutoff_distance(svy, sp_bin, "pmt"))
  expect_null(.sp_cutoff_distance(svy, dsgn_sp(targeting = "universal"), "universal"))
  draw <- function(conc) {
    withr::with_seed(7L, .determine_sp_eligibility(
      svy, utils::modifyList(sp_bin, list(error_concentration = conc))))
  }
  expect_identical(draw(20), draw(0))
  # A continuous proxy does get a distance, zero at the cutoff.
  sp_cont <- dsgn_sp(targeting = "pmt", pmt_variable = "proxy", pmt_cutoff = 0)
  d <- .sp_cutoff_distance(svy, sp_cont, "pmt")
  expect_true(all(d >= 0 & d <= 1, na.rm = TRUE))
  expect_lt(min(d), 0.01)
  expect_equal(.sp_error_concentration(list(error_concentration = -3)), 0)
  expect_equal(.sp_error_concentration(list(error_concentration = 900)), 50)
})

test_that("the preview equals the run with concentration on", {
  svy <- dsgn_svy()
  sp <- dsgn_sp(error_concentration = 20, admin_cost_pct = 5,
                amount_basis = "per_capita")
  r <- dsgn_run(svy, sp)
  expect_equal(r$reach$transfer_total, r$totals$total_cost)
  expect_equal(r$reach$n_pop, sum(svy$weight[r$policy[[SP_TRANSFER_COL]] > 0]))
})

# Diagnostics and the module spec ----

test_that("the diagnostics snapshot and its table carry the admin split", {
  svy <- dsgn_svy()
  sp <- dsgn_sp(admin_cost_pct = 20)
  policy <- apply_policy_to_svy(svy, sp = sp, analysis_unit = "hh", seed = 5L)
  snap <- .policy_diagnostics_snapshot(svy, policy, analysis_unit = "hh", sp = sp)
  expect_equal(snap$admin_share, 0.2)
  expect_equal(snap$total_cost_sum, snap$transfer_sum / 0.8)
  expect_equal(snap$admin_sum, snap$total_cost_sum - snap$transfer_sum)
  rows <- .policy_transfer_summary_rows(snap)
  expect_equal(nrow(rows), 4L)
  expect_equal(rows$Value[[3]], snap$total_cost_sum)

  sp0 <- dsgn_sp()
  snap0 <- .policy_diagnostics_snapshot(
    svy, apply_policy_to_svy(svy, sp = sp0, analysis_unit = "hh", seed = 5L),
    analysis_unit = "hh", sp = sp0
  )
  rows0 <- .policy_transfer_summary_rows(snap0)
  expect_equal(nrow(rows0), 2L)
  expect_match(rows0$Type[[1]], "^Estimated annual cost \\(")
  expect_equal(rows0$Value, c(snap0$transfer_sum, snap0$transfer_pp))
})

test_that("the SP module spec carries the new fields with safe defaults", {
  svy <- data.frame(welfare = 1:4, weight = 1)
  testServer(mod_3_01_sp_server, args = list(
    id = "sp_spec", survey_weather = shiny::reactiveVal(svy),
    variable_list = shiny::reactiveVal(data.frame()),
    analysis_unit = shiny::reactiveVal("hh"),
    hist_sim = shiny::reactiveVal(NULL)
  ), {
    spec <- sp_scenario_spec()
    expect_equal(spec$admin_cost_pct, 0)
    expect_identical(spec$amount_basis, "per_household")
    expect_equal(spec$error_concentration, 0)

    session$setInputs(admin_cost_pct = 12, amount_basis = "per_capita",
                      error_concentration = "20")
    spec <- sp_scenario_spec()
    expect_equal(spec$admin_cost_pct, 12)
    expect_identical(spec$amount_basis, "per_capita")
    expect_equal(spec$error_concentration, 20)
  })
  testServer(mod_3_01_sp_server, args = list(
    id = "sp_spec_ind", survey_weather = shiny::reactiveVal(svy),
    variable_list = shiny::reactiveVal(data.frame()),
    analysis_unit = shiny::reactiveVal("ind"),
    hist_sim = shiny::reactiveVal(NULL)
  ), {
    session$setInputs(amount_basis = "per_capita")
    expect_identical(sp_scenario_spec()$amount_basis, "per_household")
  })
})

test_that("new SP inputs travel in the config and the flyout toggles do not (P0-6)", {
  keep <- c("step3-sp-admin_cost_pct", "step3-sp-amount_basis",
            "step3-sp-error_concentration")
  drop <- c("step3-sp-targeting_toggle", "step3-sp-payment_toggle")
  expect_true(all(.export_keep_input(keep)))
  expect_false(any(.export_keep_input(drop)))
})

test_that("changing any new SP field changes the policy signature input (P0-6)", {
  # The Step 3 run signature hashes the whole SP list, so every field counts.
  base <- dsgn_sp()
  sigs <- vapply(
    list(base, dsgn_sp(admin_cost_pct = 5), dsgn_sp(amount_basis = "per_capita"),
         dsgn_sp(error_concentration = 5)),
    function(sp) rlang::hash(.sig_plain(list(sp = sp))), character(1)
  )
  expect_equal(length(unique(sigs)), 4L)
})

# Cost and targeting effectiveness (P0-5) ----

test_that("effectiveness metrics match a hand calculation", {
  # Four households, equal weights of 100 people, household size 2 each.
  base <- data.frame(
    welfare = c(1, 2, 4, 6), hhsize = 2, weight = 100
  )
  pol <- base
  # Recipients: hh 1 (poor), hh 2 (poor), hh 3 (not poor). Daily per-capita
  # transfers 0.5, 1 and 1.
  pol[[SP_TRANSFER_COL]] <- c(0.5, 1, 1, 0)
  res <- sp_effectiveness(base, pol, poverty_line = 3, analysis_unit = "hh",
                          eligibility = c(TRUE, TRUE, FALSE, TRUE))
  m <- stats::setNames(res$metrics$value, res$metrics$metric)
  expect_equal(res$status, "ok")
  expect_true(res$has_line)
  # Poor: hh 1 and 2 (welfare < 3); both receive: coverage 100%.
  expect_equal(m[["Coverage of the poor"]], 1)
  # Spending = transfer * weight: 50 + 100 + 100; non-poor share = 100 / 250.
  expect_equal(m[["Leakage to the non-poor"]], 100 / 250)
  # Adequacy: spend to poor recipients 150 over gaps 100*(3-1) + 100*(3-2) = 300.
  expect_equal(m[["Adequacy for poor recipients"]], 150 / 300)
  # Realised errors against the ideal rule: hh 3 is included in error (100 of
  # 300 recipient people); hh 4 is eligible but unpaid (100 of 300 eligible).
  expect_equal(m[["Inclusion error (realised)"]], 100 / 300)
  expect_equal(m[["Exclusion error (realised)"]], 100 / 300)
  # Cost per person: annual cost 250 * 365 over 400 people.
  expect_equal(m[["Annual cost per person in the population"]], 250 * 365 / 400)
})

test_that("effectiveness handles admin, missing line, weights and LCU", {
  base <- data.frame(welfare = c(1, 2, 4, 6), hhsize = 2, weight = 100)
  pol <- base
  pol[[SP_TRANSFER_COL]] <- c(0.5, 1, 1, 0)
  # Administration enters the cost per person only.
  a <- sp_effectiveness(base, pol, 3, admin_share = 0.2)
  b <- sp_effectiveness(base, pol, 3)
  cost <- function(r) r$metrics$value[r$metrics$metric == "Annual cost per person in the population"]
  expect_equal(cost(a), cost(b) / 0.8)
  # No line: line-based figures are NA, cost and admin stay.
  nl <- sp_effectiveness(base, pol, NULL)
  expect_false(nl$has_line)
  expect_true(all(is.na(nl$metrics$value[grepl("Coverage|Leakage|Adequacy", nl$metrics$metric)])))
  expect_true(is.finite(cost(nl)))
  # Unweighted household rows count household members.
  uw <- sp_effectiveness(base[c("welfare", "hhsize")], pol[c("welfare", "hhsize", SP_TRANSFER_COL)], 3)
  expect_equal(uw$status, "ok")
  # An LCU line is converted per row with ppp2021.
  lcu_base <- cbind(base, ppp2021 = 2)
  lcu_pol <- cbind(pol, ppp2021 = 2)
  lcu <- sp_effectiveness(lcu_base, lcu_pol, 6, currency = "LCU")
  ppp <- sp_effectiveness(base, pol, 3)
  expect_equal(lcu$metrics$value[lcu$metrics$metric == "Coverage of the poor"],
               ppp$metrics$value[ppp$metrics$metric == "Coverage of the poor"])
  # No transfer: nothing to evaluate.
  none <- sp_effectiveness(base, base, 3)
  expect_equal(none$status, "no_transfer")
  expect_equal(nrow(.sp_effectiveness_display(none)), 0L)
})

test_that("the effectiveness table formats money and percentages", {
  base <- data.frame(welfare = c(1, 2, 4, 6), hhsize = 2, weight = 100)
  pol <- base
  pol[[SP_TRANSFER_COL]] <- c(0.5, 1, 1, 0)
  disp <- .sp_effectiveness_display(sp_effectiveness(base, pol, 3), "PPP")
  expect_named(disp, c("Metric", "Value", "Note"))
  expect_match(disp$Value[disp$Metric == "Coverage of the poor"], "^100\\.0%$")
  expect_match(disp$Value[disp$Metric == "Annual cost per person in the population"], "^\\$")
  nl <- .sp_effectiveness_display(sp_effectiveness(base, pol, NULL))
  expect_equal(nl$Value[nl$Metric == "Coverage of the poor"], "Not available")
})

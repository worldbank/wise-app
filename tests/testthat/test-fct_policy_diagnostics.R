test_that("policy_decile_movement reports the weighted share moving over one decile (DOC-03)", {
  y <- seq(1, 100, length.out = 1000)
  ctx <- list(
    engine = "rif", F_hat = stats::ecdf(y), y_baseline = y,
    delta_main = c(rep(50, 200), rep(0, 800)),
    svy_baseline = data.frame(weight = rep(1, 1000))
  )
  mv <- policy_decile_movement(ctx)
  # The bottom 200 households (deciles 1-2) move to 51-70 (deciles 5-7)
  expect_equal(mv$share, 0.2, tolerance = 0.01)
  expect_gte(mv$share_any, mv$share)

  ctx$delta_main <- rep(0, 1000)
  expect_equal(policy_decile_movement(ctx)$share, 0)

  # weights change the share
  ctx$delta_main <- c(rep(60, 100), rep(0, 900))
  ctx$svy_baseline$weight <- c(rep(5, 100), rep(1, 900))
  expect_equal(policy_decile_movement(ctx)$share, 500 / 1400, tolerance = 0.01)

  expect_null(policy_decile_movement(NULL))
  ctx$engine <- "fixest"
  expect_null(policy_decile_movement(ctx))
})

test_that(".policy_display_name turns identifiers into title-case labels", {
  expect_equal(.policy_display_name("hh_size"), "Hh Size")
  expect_equal(.policy_display_name("urban.rural"), "Urban Rural")
  expect_equal(.policy_display_name("headAge"), "Head Age")
})

test_that(".policy_changed_counts counts changed values and NA flips", {
  base <- data.frame(a = c(1, 2, NA, 4), b = c("x", "y", "z", NA))
  pol <- data.frame(a = c(1, 3, 5, 4), b = c("x", "y", "q", NA))
  expect_equal(.policy_changed_counts(base, pol, c("a", "b")), c(a = 2, b = 1))
  expect_equal(.policy_changed_counts(base, base, "a"), c(a = 0))
})

test_that(".policy_decile_move_cards states the movement and flags large shares", {
  expect_null(.policy_decile_move_cards(NULL))
  expect_null(.policy_decile_move_cards(list(share = NA_real_, warn_at = 0.1)))
  small <- .policy_decile_move_cards(list(share = 0.05, warn_at = 0.1))
  expect_length(small, 1L)
  expect_equal(small[[1]]$label, "Households moving more than one decile")
  expect_equal(small[[1]]$value, "5.0%")
  expect_match(small[[1]]$note, "stays close to the observed positions")
  large <- .policy_decile_move_cards(list(share = 0.25, warn_at = 0.1))
  expect_match(large[[1]]$note, "extrapolation")
})

test_that(".policy_treatment_explanation_base words each targeting rule", {
  expect_match(.policy_treatment_explanation_base(NULL), "counterfactual assignment")
  expect_match(.policy_treatment_explanation_base(list(targeting = "universal")),
    "applies no targeting errors")
  poor <- .policy_treatment_explanation_base(list(
    targeting = "exante_poor", targeting_threshold = 30,
    inclusion_error_pct = 5, exclusion_error_pct = 10
  ))
  expect_match(poor, "bottom 30% by baseline welfare")
  expect_match(poor, "5% inclusion error")
  expect_match(poor, "10% exclusion error")
  expect_false(grepl("near the cutoff", poor))
  near <- .policy_treatment_explanation_base(list(targeting = "pmt", error_concentration = 2))
  expect_match(near, "proxy variable and cutoff")
  expect_match(near, "near the cutoff")
})

test_that(".format_policy_component_table formats counts, shares and cost", {
  expect_null(.format_policy_component_table(NULL))
  df <- data.frame(
    component = "Cash transfer", n_affected = 12, weighted_affected = 12345.6,
    population_share = 0.256, realized_cost = 9876.5, weighted_households = 3000
  )
  out <- .format_policy_component_table(df, "hh", currency = "PPP")
  expect_named(out, c(
    "Policy component", "Sample households affected / covered",
    "Households represented", "Population represented", "Population share",
    "Realized cost"
  ))
  expect_equal(out$`Population share`, "25.6%")
  expect_equal(out$`Households represented`, fmt_num(3000, digits = 0))
  person <- .format_policy_component_table(df, "person")
  expect_true("Sample observations affected / covered" %in% names(person))
  expect_false("Households represented" %in% names(person))
})

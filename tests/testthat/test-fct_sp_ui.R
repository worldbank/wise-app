# Direct tests of the pure helpers of the social protection panel. The rendered
# reach card is also covered through the module in test-fct_sp_shock.R.

test_that(".sp_unit_word words each analysis unit and defaults to households", {
  expect_equal(.sp_unit_word(), "households")
  expect_equal(.sp_unit_word(plural = FALSE, au = "ind"), "individual")
  expect_equal(.sp_unit_word(au = "ind"), "individuals")
  expect_equal(.sp_unit_word(au = "firm", capitalize = TRUE), "Firms")
  expect_equal(.sp_unit_word(plural = FALSE, au = ""), "household")
  expect_equal(.sp_unit_word(plural = FALSE, au = "other"), "household")
})

test_that(".sp_amount_currency_label keeps PPP and relabels LCU to 2021 prices", {
  expect_equal(.sp_amount_currency_label("PPP"), "PPP")
  expect_equal(.sp_amount_currency_label(NA_character_), "PPP")
  expect_equal(.sp_amount_currency_label(""), "PPP")
  expect_equal(.sp_amount_currency_label("LCU"), "2021 LCU")
})

test_that(".sp_targeting_summary is empty for universal targeting", {
  expect_equal(.sp_targeting_summary("universal", 0, 10, 10), "")
  expect_equal(.sp_targeting_summary("exante_poor", 0, 5, 15), "errors 5% / 15%")
  expect_equal(.sp_targeting_summary("pmt", 2, 10, 10), "Proxy rule; errors 10% / 10%, near cutoff")
  expect_equal(.sp_targeting_summary("pmt", "x", 10, 10), "Proxy rule; errors 10% / 10%")
})

test_that(".sp_payment_summary joins payments, amount basis and administration", {
  expect_equal(.sp_payment_summary(0, "per_household", 6L, "hh"), "6 payments/year, per household")
  expect_equal(.sp_payment_summary(5, "per_capita", NULL, "hh"), "per person, admin 5%")
  expect_equal(.sp_payment_summary(0, "per_household", 12, "ind"), "12 payments/year, per individual")
  expect_equal(.sp_payment_summary("bad", "per_household", NULL, "firm"), "per firm")
})

test_that(".sp_reach_card shows a not-available card without a reach", {
  html <- as.character(.sp_reach_card(NULL, list(sp_type = "regular"), "hh", "regular", NULL, "hh"))
  expect_match(html, "Regular")
  expect_match(html, "Recipient households")
  expect_match(html, "Not available")
  shock <- as.character(.sp_reach_card(NULL, list(sp_type = "shock"), "ind", "shock", NULL, "ind"))
  expect_match(shock, "Shock-responsive")
  expect_match(shock, "Recipient individuals")
})

test_that(".sp_reach_card reports recipients, cost and administration", {
  r <- list(
    weighted = TRUE, n_rows = 20, n_total = 100, n_recipient_units = 20, n_pop = 90,
    share_pct = 20, amount_basis = "per_household", transfer_per_unit = 5,
    transfer_per_person = 1, transfer_total = 1000, admin_cost = 100, on_baseline = TRUE
  )
  spec <- list(sp_type = "regular", targeting = "universal", currency = "PPP", budget_rule = "x")
  html <- as.character(.sp_reach_card(r, spec, "hh", "regular", NULL, "hh"))
  expect_match(html, "People represented")
  expect_match(html, "Estimated annual cost")
  expect_match(html, "Of which administration")
  expect_match(html, "Annual transfer per household")
  expect_match(html, "Universal targeting reaches all sampled units")
  expect_false(grepl("Before Step 2 runs", html))
  r$on_baseline <- FALSE
  r$amount_basis <- "per_capita"
  r$transfer_total <- 0
  r$admin_cost <- 0
  html2 <- as.character(.sp_reach_card(r, spec, "hh", "regular", NULL, "ind"))
  expect_match(html2, "Population represented")
  expect_match(html2, "Annual transfer per person")
  expect_match(html2, "No transfer is configured yet")
  expect_match(html2, "Before Step 2 runs")
  expect_false(grepl("Of which administration", html2))
  shock_html <- as.character(.sp_reach_card(
    r, utils::modifyList(spec, list(sp_type = "shock")), "hh", "shock",
    list(problem = "No exposure"), "hh"
  ))
  expect_match(shock_html, "Annual cost in a year it pays")
  expect_match(shock_html, "No exposure")
})

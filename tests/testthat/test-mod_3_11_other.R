# Tests for mod_3_11_other_server(): levers of groups without a module of their
# own are found from the variable list and controlled like the other levers.

other_vl <- function() {
  data.frame(
    name = c("income_idx", "clean_fuel", "elec_access", "ttime_city"),
    label = c("Income index", "Clean cooking fuel", "Electricity", "Travel time to city"),
    type = c("numeric", "logical", "logical", "numeric"),
    ind = 0L, hh = c(1L, 1L, 1L, 0L), firm = 0L, area = c(0L, 0L, 0L, 1L),
    policy = c("income", "clean_cooking", "electricity", "city_access"),
    policy_group = c("livelihoods", "", "infrastructure", "mobility"),
    stringsAsFactors = FALSE
  )
}

other_args <- function(covariates = character(0), svy = NULL, vl = other_vl()) {
  list(
    selected_model = shiny::reactive(list(hh_covariates = covariates)),
    survey_data = shiny::reactive(svy),
    variable_list = shiny::reactive(vl)
  )
}

test_that("without levers of other groups the module offers nothing", {
  shiny::testServer(mod_3_11_other_server, args = other_args(vl = NULL), {
    sc <- session$returned$other_scenario()
    expect_length(sc$lever_vars, 0L)
    expect_match(output$placeholder_ui$html, "No other policy levers")
    expect_false(has_infra_change(sc))
  })
})

test_that("levers of unknown or blank groups get controls, titled by their group", {
  shiny::testServer(
    mod_3_11_other_server, args = other_args(c("income_idx", "clean_fuel", "elec_access", "ttime_city")), {
      html <- output$levers_ui$html
      expect_match(html, "income_pct", fixed = TRUE)
      expect_match(html, "clean_cooking_universal", fixed = TRUE)
      expect_match(html, "city_access_pct", fixed = TRUE)
      # titled by the group text; blank group is "Other"
      expect_match(html, "Livelihoods", fixed = TRUE)
      expect_match(html, ">Other<", fixed = TRUE)
      expect_match(html, "Mobility", fixed = TRUE)
      # a lever of a group with its own module is not here
      expect_false(grepl("electricity", html, fixed = TRUE))
    }
  )
})

test_that("the scenario is by lever code and runs with the infrastructure scenario", {
  shiny::testServer(mod_3_11_other_server, args = other_args(), {
    session$setInputs(income_pct = 20, clean_cooking_universal = TRUE)
    sc <- session$returned$other_scenario()
    expect_equal(sc$income_value_change_pct, 20)
    expect_true(sc$clean_cooking_universal)
    expect_identical(sc$lever_vars$income, "income_idx")
    expect_identical(sc$lever_groups$income, "livelihoods")
    expect_true(has_infra_change(sc))
    merged <- step3_merge_access(wise_infra_config(list(electricity_pct = 5), policy_registry(other_vl())), sc)
    expect_identical(merged$lever_vars$electricity, "elec_access")
    expect_identical(merged$lever_vars$income, "income_idx")
  })
})

test_that("levers not in the model are left out with the reason", {
  shiny::testServer(mod_3_11_other_server, args = other_args("income_idx"), {
    html <- output$levers_ui$html
    expect_match(html, "income_pct", fixed = TRUE)
    expect_false(grepl("clean_cooking_universal", html, fixed = TRUE))
    expect_match(html, "Clean cooking fuel (variable not in the Step 1 model)", fixed = TRUE)
  })
})

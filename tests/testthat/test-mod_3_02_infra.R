# Tests for mod_3_02_infra_server(): scenario returned to Step 3 and which
# levers are shown for a given Step 1 model. Controls come from the lever
# registry (mod_3_levers.R); ids are `<lever code>_universal` / `_pct`.

infra_args <- function(covariates = character(0), svy = NULL, vl = NULL) {
  list(
    selected_model = shiny::reactive(list(hh_covariates = covariates)),
    survey_data = shiny::reactive(svy),
    variable_list = shiny::reactive(vl)
  )
}

test_that("default scenario is no change for every lever", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args(), {
    sc <- session$returned$infra_scenario()
    for (v in c("electricity", "water", "sanitation", "piped", "piped_to_prem", "water_sanitation")) {
      expect_false(sc[[paste0(v, "_universal")]])
      expect_identical(sc[[paste0(v, "_access_change_pct")]], 0L)
    }
    expect_identical(sc$health_mode, "pct")
    expect_identical(sc$health_travel_pct, 0L)
    expect_identical(sc$health_travel_max, 60L)
    expect_identical(sc$lever_vars$water, "imp_wat_rec")
  })
})

test_that("slider values and universal toggles flow into the scenario", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args(), {
    session$setInputs(
      electricity_universal = TRUE, electricity_pct = 35,
      water_universal = FALSE, water_pct = 40,
      piped_pct = -10,
      health_mode = "max", health_travel_pct = -25, health_travel_max = 90
    )
    sc <- session$returned$infra_scenario()
    # Universal overrides the slider
    expect_true(sc$electricity_universal)
    expect_identical(sc$electricity_access_change_pct, 100L)
    expect_false(sc$water_universal)
    expect_equal(sc$water_access_change_pct, 40)
    expect_equal(sc$piped_access_change_pct, -10)
    expect_identical(sc$sanitation_access_change_pct, 0L)
    expect_identical(sc$health_mode, "max")
    expect_equal(sc$health_travel_pct, -25)
    expect_equal(sc$health_travel_max, 90)
  })
})

test_that("a lever is only rendered when its variable is in the model", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args(c("electricity", "ttime_health")), {
    html <- output$levers_ui$html
    expect_match(html, "electricity_universal", fixed = TRUE)
    expect_match(html, "health_mode", fixed = TRUE)
    for (absent in c("water_universal", "sanitation_universal", "piped_universal",
                     "piped_to_prem_universal", "water_sanitation_universal")) {
      expect_false(grepl(absent, html, fixed = TRUE), info = absent)
    }
    # levers left out are listed, with the reason
    expect_match(html, "Not available:", fixed = TRUE)
    expect_match(html, "Access to improved water (variable not in the Step 1 model)", fixed = TRUE)
  })
})

test_that("interaction terms count as the lever being in the model", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args(c("imp_wat_rec:Haz_t")), {
    html <- output$levers_ui$html
    expect_match(html, "water_universal", fixed = TRUE)
    expect_false(grepl("electricity_universal", html, fixed = TRUE))
  })
})

test_that("a lever whose variable is not in the survey says so", {
  shiny::testServer(
    mod_3_02_infra_server,
    args = infra_args(c("electricity", "imp_wat_rec"), data.frame(electricity = c(0, 1))), {
      expect_match(output$levers_ui$html, "Access to improved water (variable not in the selected survey)", fixed = TRUE)
    }
  )
})

test_that("levers follow the variable list: renamed variable, new lever in the group", {
  vl <- data.frame(
    name = c("elec_access", "clean_fuel", "income_idx"),
    label = c("Electricity", "Clean cooking fuel", "Income index"),
    type = c("logical", "logical", "numeric"),
    ind = 0L, hh = 1L, firm = 0L, area = 0L,
    policy = c("electricity", "clean_cooking", "income"),
    policy_group = c("infrastructure", "infrastructure", "infrastructure"),
    stringsAsFactors = FALSE
  )
  shiny::testServer(
    mod_3_02_infra_server, args = infra_args(c("elec_access", "clean_fuel", "income_idx"), vl = vl), {
      html <- output$levers_ui$html
      expect_match(html, "electricity_universal", fixed = TRUE)
      expect_match(html, "clean_cooking_universal", fixed = TRUE)
      expect_match(html, "income_pct", fixed = TRUE)
      expect_false(grepl("income_universal", html, fixed = TRUE))
      # levers the list does not have are not offered
      expect_false(grepl("water_universal", html, fixed = TRUE))
      session$setInputs(electricity_pct = 20, clean_cooking_universal = TRUE, income_pct = 10)
      sc <- session$returned$infra_scenario()
      expect_equal(sc$electricity_access_change_pct, 20)
      expect_true(sc$clean_cooking_universal)
      expect_equal(sc$income_value_change_pct, 10)
      expect_identical(sc$lever_vars$electricity, "elec_access")
      expect_null(sc$water_universal)
    }
  )
})

test_that("placeholder: hidden when a variable is in the model, warning when survey lacks them", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args("electricity"), {
    expect_false(isTRUE(nzchar(output$placeholder_ui$html)))
  })
  shiny::testServer(mod_3_02_infra_server, args = infra_args("other", data.frame(x = 1)), {
    expect_match(output$placeholder_ui$html, "No infrastructure variables found")
  })
  shiny::testServer(mod_3_02_infra_server, args = infra_args("other", data.frame(electricity = c(0, 1))), {
    html <- output$placeholder_ui$html
    expect_false(grepl("No infrastructure variables found", html))
    expect_match(html, "infrastructure")
  })
})

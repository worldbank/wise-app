# Tests for mod_3_02_infra_server(): scenario returned to Step 3 and which
# levers are shown for a given Step 1 model.

infra_args <- function(covariates = character(0), svy = NULL) {
  list(
    selected_model = shiny::reactive(list(hh_covariates = covariates)),
    survey_data = shiny::reactive(svy),
    variable_list = shiny::reactive(NULL)
  )
}

test_that("default scenario is no change for every lever", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args(), {
    sc <- session$returned$infra_scenario()
    for (v in c("elec", "water", "sanitation", "piped", "piped_to_prem", "imp_wat_san")) {
      expect_false(sc[[paste0(v, "_universal")]])
      expect_identical(sc[[paste0(v, "_access_change_pct")]], 0L)
    }
    expect_identical(sc$health_mode, "pct")
    expect_identical(sc$health_travel_pct, 0L)
    expect_identical(sc$health_travel_max, 60L)
  })
})

test_that("slider values and universal toggles flow into the scenario", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args(), {
    session$setInputs(
      elec_universal = TRUE, elec_pct = 35,
      water_universal = FALSE, water_pct = 40,
      piped_pct = -10,
      health_mode = "max", health_travel_pct = -25, health_travel_max = 90
    )
    sc <- session$returned$infra_scenario()
    # Universal overrides the slider
    expect_true(sc$elec_universal)
    expect_identical(sc$elec_access_change_pct, 100L)
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
    expect_match(output$elec_ui$html, "elec_universal", fixed = TRUE)
    expect_match(output$health_ui$html, "health_mode", fixed = TRUE)
    expect_error(output$water_ui, class = "shiny.silent.error")
    expect_error(output$sanitation_ui, class = "shiny.silent.error")
    expect_error(output$piped_ui, class = "shiny.silent.error")
    expect_error(output$piped_to_prem_ui, class = "shiny.silent.error")
    expect_error(output$imp_wat_san_ui, class = "shiny.silent.error")
  })
})

test_that("interaction terms count as the lever being in the model", {
  shiny::testServer(mod_3_02_infra_server, args = infra_args(c("imp_wat_rec:Haz_t")), {
    expect_match(output$water_ui$html, "water_universal", fixed = TRUE)
    expect_error(output$elec_ui, class = "shiny.silent.error")
  })
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

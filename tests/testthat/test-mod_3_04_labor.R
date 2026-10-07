# Tests for mod_3_04_labor_server(): scenario returned to Step 3 and which
# levers are shown for a given Step 1 model. Sector-slider defaults are covered
# in test-policy-labor-sectors.R.

labor_args <- function(covariates = character(0), svy = NULL) {
  list(
    selected_model = shiny::reactive(list(hh_covariates = covariates)),
    survey_data = shiny::reactive(svy),
    variable_list = shiny::reactive(NULL)
  )
}

test_that("default scenario is no change", {
  shiny::testServer(mod_3_04_labor_server, args = labor_args(), {
    sc <- session$returned$labor_scenario()
    expect_identical(sc$employment_change_pp, 0)
    expect_null(sc$sector_manufacturing)
    expect_null(sc$sector_services)
    expect_identical(sc$sector_agriculture, 100)
  })
})

test_that("agriculture is derived as the remainder of manufacturing + services", {
  shiny::testServer(mod_3_04_labor_server, args = labor_args(), {
    session$setInputs(labor_emp = -4, sector_manufacturing = 30, sector_services = 45)
    sc <- session$returned$labor_scenario()
    expect_identical(sc$employment_change_pp, -4)
    expect_equal(sc$sector_manufacturing, 30)
    expect_equal(sc$sector_services, 45)
    expect_equal(sc$sector_agriculture, 25)
    expect_no_match(output$sector_agri_display$html, "clamped")
  })
})

test_that("agriculture clamps to 0 and the display says so when shares exceed 100", {
  shiny::testServer(mod_3_04_labor_server, args = labor_args(), {
    session$setInputs(sector_manufacturing = 70, sector_services = 50)
    expect_equal(session$returned$labor_scenario()$sector_agriculture, 0)
    html <- output$sector_agri_display$html
    expect_match(html, "Manufacturing + services = 120%", fixed = TRUE)
    expect_match(html, "clamped")
  })
})

test_that("employment slider needs an employment variable; sector sliders need all three", {
  shiny::testServer(mod_3_04_labor_server, args = labor_args("selfemployed"), {
    expect_match(output$labor_emp_ui$html, "labor_emp", fixed = TRUE)
    expect_error(output$labor_sector_ui, class = "shiny.silent.error")
  })
  shiny::testServer(mod_3_04_labor_server, args = labor_args(c("agriculture", "industry")), {
    expect_error(output$labor_emp_ui, class = "shiny.silent.error")
    expect_error(output$labor_sector_ui, class = "shiny.silent.error")
  })
  shiny::testServer(mod_3_04_labor_server, args = labor_args(c("agriculture", "industry", "services")), {
    expect_match(output$labor_sector_ui$html, "sector_manufacturing", fixed = TRUE)
    expect_match(output$labor_sector_ui$html, "sector_services", fixed = TRUE)
  })
})

test_that("placeholder: hidden when a variable is in the model, warning when survey lacks them", {
  shiny::testServer(mod_3_04_labor_server, args = labor_args("employed"), {
    expect_false(isTRUE(nzchar(output$placeholder_ui$html)))
  })
  shiny::testServer(mod_3_04_labor_server, args = labor_args("other", data.frame(x = 1)), {
    expect_match(output$placeholder_ui$html, "No labour market variables found")
  })
  shiny::testServer(mod_3_04_labor_server, args = labor_args("other", data.frame(employed = c(0, 1))), {
    html <- output$placeholder_ui$html
    expect_false(grepl("No labour market variables found", html))
    expect_match(html, "labor market")
  })
})

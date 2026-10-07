# Tests for mod_3_03_digital_server(): scenario returned to Step 3 and which
# levers are shown for a given Step 1 model.

digital_args <- function(covariates = character(0), svy = NULL) {
  list(
    selected_model = shiny::reactive(list(hh_covariates = covariates)),
    survey_data = shiny::reactive(svy),
    variable_list = shiny::reactive(NULL)
  )
}

test_that("default scenario is no change", {
  shiny::testServer(mod_3_03_digital_server, args = digital_args(), {
    sc <- session$returned$digital_scenario()
    expect_false(sc$internet_universal)
    expect_identical(sc$internet_access_change_pct, 0L)
    expect_false(sc$mobile_universal)
    expect_identical(sc$mobile_access_change_pct, 0L)
  })
})

test_that("slider values and universal toggles flow into the scenario", {
  shiny::testServer(mod_3_03_digital_server, args = digital_args(), {
    session$setInputs(internet_universal = TRUE, internet_pct = 25, mobile_pct = -15)
    sc <- session$returned$digital_scenario()
    expect_true(sc$internet_universal)
    expect_identical(sc$internet_access_change_pct, 100L)
    expect_false(sc$mobile_universal)
    expect_equal(sc$mobile_access_change_pct, -15)

    session$setInputs(internet_universal = FALSE)
    expect_equal(session$returned$digital_scenario()$internet_access_change_pct, 25)
  })
})

test_that("a lever is only rendered when its variable is in the model", {
  shiny::testServer(mod_3_03_digital_server, args = digital_args("internet"), {
    expect_match(output$internet_ui$html, "internet_universal", fixed = TRUE)
    expect_error(output$mobile_ui, class = "shiny.silent.error")
  })
  shiny::testServer(mod_3_03_digital_server, args = digital_args("cellphone:Haz_t"), {
    expect_match(output$mobile_ui$html, "mobile_universal", fixed = TRUE)
    expect_error(output$internet_ui, class = "shiny.silent.error")
  })
})

test_that("placeholder: hidden when a variable is in the model, warning when survey lacks them", {
  shiny::testServer(mod_3_03_digital_server, args = digital_args("internet"), {
    expect_false(isTRUE(nzchar(output$placeholder_ui$html)))
  })
  shiny::testServer(mod_3_03_digital_server, args = digital_args("other", data.frame(x = 1)), {
    expect_match(output$placeholder_ui$html, "No digital inclusion variables found")
  })
  shiny::testServer(mod_3_03_digital_server, args = digital_args("other", data.frame(internet = c(0, 1))), {
    html <- output$placeholder_ui$html
    expect_false(grepl("No digital inclusion variables found", html))
    expect_match(html, "digital inclusion")
  })
})

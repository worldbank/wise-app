# Tests for mod_3_05_education_server(): scenario returned to Step 3 and which
# levers are shown for a given Step 1 model.

education_args <- function(covariates = character(0), svy = NULL) {
  list(
    selected_model = shiny::reactive(list(hh_covariates = covariates)),
    survey_data = shiny::reactive(svy),
    variable_list = shiny::reactive(NULL)
  )
}

test_that("default scenario is no change for every level", {
  shiny::testServer(mod_3_05_education_server, args = education_args(), {
    sc <- session$returned$education_scenario()
    for (v in c("primary", "secondary", "postsec")) {
      expect_false(sc[[paste0(v, "_universal")]])
      expect_identical(sc[[paste0(v, "_access_change_pct")]], 0L)
    }
  })
})

test_that("slider values and universal toggles flow into the scenario", {
  shiny::testServer(mod_3_05_education_server, args = education_args(), {
    session$setInputs(
      primary_universal = TRUE, primary_pct = 20,
      secondary_pct = 45, postsec_pct = -5
    )
    sc <- session$returned$education_scenario()
    expect_true(sc$primary_universal)
    expect_identical(sc$primary_access_change_pct, 100L)
    expect_equal(sc$secondary_access_change_pct, 45)
    expect_equal(sc$postsec_access_change_pct, -5)
    expect_false(sc$secondary_universal)
  })
})

test_that("a level is only rendered when its variable is in the model", {
  shiny::testServer(mod_3_05_education_server, args = education_args(c("educ_com1_hh", "educ_com3_hh")), {
    expect_match(output$primary_ui$html, "primary_universal", fixed = TRUE)
    expect_match(output$postsec_ui$html, "postsec_universal", fixed = TRUE)
    expect_error(output$secondary_ui, class = "shiny.silent.error")
  })
  shiny::testServer(mod_3_05_education_server, args = education_args("educ_com2_hh:Haz_t"), {
    expect_match(output$secondary_ui$html, "secondary_universal", fixed = TRUE)
    expect_error(output$primary_ui, class = "shiny.silent.error")
  })
})

test_that("placeholder: hidden when a variable is in the model, warning when survey lacks them", {
  shiny::testServer(mod_3_05_education_server, args = education_args("educ_com1_hh"), {
    expect_false(isTRUE(nzchar(output$placeholder_ui$html)))
  })
  shiny::testServer(mod_3_05_education_server, args = education_args("other", data.frame(x = 1)), {
    expect_match(output$placeholder_ui$html, "No education variables found")
  })
  shiny::testServer(mod_3_05_education_server, args = education_args("other", data.frame(educ_com1_hh = c(0, 1))), {
    html <- output$placeholder_ui$html
    expect_false(grepl("No education variables found", html))
    expect_match(html, "education")
  })
})

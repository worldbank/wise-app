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
    for (v in c("educ_primary", "educ_secondary", "educ_postsec")) {
      expect_false(sc[[paste0(v, "_universal")]])
      expect_identical(sc[[paste0(v, "_access_change_pct")]], 0L)
    }
    expect_identical(sc$lever_vars$educ_primary, "educ_com1_hh")
  })
})

test_that("slider values and universal toggles flow into the scenario", {
  shiny::testServer(mod_3_05_education_server, args = education_args(), {
    session$setInputs(
      educ_primary_universal = TRUE, educ_primary_pct = 20,
      educ_secondary_pct = 45, educ_postsec_pct = -5
    )
    sc <- session$returned$education_scenario()
    expect_true(sc$educ_primary_universal)
    expect_identical(sc$educ_primary_access_change_pct, 100L)
    expect_equal(sc$educ_secondary_access_change_pct, 45)
    expect_equal(sc$educ_postsec_access_change_pct, -5)
    expect_false(sc$educ_secondary_universal)
  })
})

test_that("a level is only rendered when its variable is in the model", {
  shiny::testServer(mod_3_05_education_server, args = education_args(c("educ_com1_hh", "educ_com3_hh")), {
    html <- output$levers_ui$html
    expect_match(html, "educ_primary_universal", fixed = TRUE)
    expect_match(html, "educ_postsec_universal", fixed = TRUE)
    expect_false(grepl("educ_secondary_universal", html, fixed = TRUE))
    # the education wording
    expect_match(html, "gaining attainment", fixed = TRUE)
  })
  shiny::testServer(mod_3_05_education_server, args = education_args("educ_com2_hh:Haz_t"), {
    expect_match(output$levers_ui$html, "educ_secondary_universal", fixed = TRUE)
    expect_false(grepl("educ_primary_universal", output$levers_ui$html, fixed = TRUE))
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

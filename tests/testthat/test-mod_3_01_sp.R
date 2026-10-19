testthat::test_that("a restored impact level the survey lacks falls back to National with a notice", {
  notes <- character()
  testthat::local_mocked_bindings(
    showNotification = function(ui, ...) {
      notes <<- c(notes, as.character(ui))
      invisible("notification")
    },
    .package = "shiny"
  )
  svy_no_geo <- data.frame(hh = 1:4, weight = 1)
  frame <- shiny::reactiveVal(NULL)

  shiny::testServer(mod_3_01_sp_server, args = list(hist_sim = shiny::reactive(frame())), {
    session$setInputs(trigger_level = "location")
    session$flushReact()
    testthat::expect_length(notes, 0L)

    frame(list(svy = svy_no_geo))
    session$flushReact()
    testthat::expect_true(any(grepl("Impact level 'location' is not available", notes)))
  })
})

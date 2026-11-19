# Tests for mod_1_08_modelfit_server(): diagnostics outputs bound to the
# fit-time snapshot, export registration, and the one-time "Model fit" tab.

make_modelfit_fixture <- function(seed = 3) {
  withr::with_seed(seed, {
    n <- 120
    d <- data.frame(tx = rnorm(n), g = rep(1:4, each = n / 4))
    d$welfare <- 10 + 2 * d$tx + g_eff(d$g) + rnorm(n, sd = 0.5)
  })
  fit <- fixest::feols(welfare ~ tx | g, data = d, notes = FALSE)
  list(
    engine = "fixest",
    model_type = "Linear regression",
    y_var = "welfare",
    weather_terms = "tx",
    taus = NULL,
    train_data = d,
    fit3 = fit,
    .snap = list(
      model = list(engine = "fixest", model_type = "Linear regression"),
      outcome = data.frame(name = "welfare", label = "Welfare (fit)"),
      weather = data.frame(
        name = "tx", label = "Max temp", units = "deg C",
        cont_binned = "Continuous", stringsAsFactors = FALSE
      ),
      variable_list = data.frame(
        name = c("tx", "welfare"), label = c("Max temp", "Welfare (fit)")
      ),
      survey_weather = d
    )
  )
}
g_eff <- function(g) c(0, 1, -1, 2)[g]

modelfit_args <- function(mf, stale = FALSE) {
  list(
    id = "mf",
    model_fit = shiny::reactiveVal(mf),
    tabset_id = "step1_tabs",
    fit_stale = shiny::reactiveVal(stale),
    tabset_session = NULL
  )
}

test_that("fit statistics table is computed from the full model", {
  fx <- make_modelfit_fixture()
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    tab <- additional_stats_df()
    expect_identical(tab$Statistic[[1]], "Observations")
    expect_equal(tab$Value[[1]], "120")
    expect_true("Within R²" %in% tab$Statistic)
    expect_false(is.null(output$additional_stats))
  })
})

test_that("raw model summary prints the native summary of the fitted model", {
  fx <- make_modelfit_fixture()
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    txt <- model_summary_text()
    expect_match(paste(txt, collapse = "\n"), "OLS estimation")
    expect_match(paste(txt, collapse = "\n"), "tx")
    expect_match(paste(output$model_summary, collapse = "\n"), "OLS estimation")
  })
})

test_that("RIF summary is prefixed with the median-quantile label", {
  fx <- make_modelfit_fixture()
  fx$engine <- "rif"
  fx$fit3 <- list(fx$fit3, fx$fit3, fx$fit3, fx$fit3, fx$fit3)
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    expect_match(model_summary_text()[[1]], "Median quantile (tau = 0.5)", fixed = TRUE)
  })
})

test_that("model card uses snapshot labels and stale banner follows the flag", {
  fx <- make_modelfit_fixture()
  stale <- shiny::reactiveVal(FALSE)
  args <- modelfit_args(fx)
  args$fit_stale <- stale
  shiny::testServer(mod_1_08_modelfit_server, args = args, {
    card <- output$selected_model_card$html
    expect_match(card, "Selected model", fixed = TRUE)
    expect_match(card, "Welfare (fit)", fixed = TRUE)
    expect_false(isTRUE(nzchar(output$fit_stale_banner$html)))
    stale(TRUE)
    session$flushReact()
    expect_match(output$fit_stale_banner$html, "Step 1 model diagnostics", fixed = TRUE)
  })
})

test_that("with no fit, outputs stay silent instead of erroring", {
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(NULL), {
    expect_error(output$selected_model_card, class = "shiny.silent.error")
    expect_error(output$pred_welf_dist, class = "shiny.silent.error")
    expect_error(output$residual_panels, class = "shiny.silent.error")
    expect_error(output$model_summary, class = "shiny.silent.error")
    expect_error(output$resid_weather_layout, class = "shiny.silent.error")
  })
})

test_that("charts render for a linear fit; second residual panel needs a second weather term", {
  fx <- make_modelfit_fixture()
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    expect_false(is.null(output$resid_weather1))
    expect_false(is.null(output$pred_welf_dist))
    expect_false(is.null(output$importance_plot))
    expect_false(is.null(output$residual_panels))
    expect_error(output$resid_weather2, class = "shiny.silent.error")
  })
})

test_that("residual axis label carries units and 'bins' for binned weather", {
  fx <- make_modelfit_fixture()
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    expect_identical(resid_axis_lab("tx"), "Max temp (deg C)")
  })
  fx$.snap$weather$cont_binned <- "Binned"
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    expect_identical(resid_axis_lab("tx"), "Max temp bins (deg C)")
  })
  fx$.snap$weather$units <- NA_character_
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    expect_identical(resid_axis_lab("tx"), "Max temp bins")
  })
})

test_that("diagnostics are registered for export under stable keys", {
  fx <- make_modelfit_fixture()
  shiny::testServer(mod_1_08_modelfit_server, args = modelfit_args(fx), {
    keys <- names(wise_export_items(session))
    expect_true(all(c(
      "model_fit_statistics", "model_summary", "residuals_vs_weather_1",
      "residuals_vs_weather_2", "predicted_vs_actual_welfare",
      "r2_contribution", "model_diagnostics"
    ) %in% keys))
  })
})

test_that("the Model fit tab is appended once, however often the fit changes", {
  fx <- make_modelfit_fixture()
  calls <- 0L
  local_mocked_bindings(
    appendTab = function(...) calls <<- calls + 1L,
    .package = "shiny"
  )
  args <- modelfit_args(NULL)
  mf <- args$model_fit
  shiny::testServer(mod_1_08_modelfit_server, args = args, {
    # The first change is consumed as the session-init event (ignoreInit).
    mf(fx); session$flushReact()
    mf(make_modelfit_fixture(seed = 4)); session$flushReact()
    expect_identical(calls, 1L)
    mf(make_modelfit_fixture(seed = 5)); session$flushReact()
    expect_identical(calls, 1L)
    expect_true(modelfit_tab_added())
  })
})

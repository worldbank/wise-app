# The Step 3 input glue: lever configurations from control values, the spec
# defaults against the initial values of the controls, and parity of the lever
# modules with the spec route.

# The initial value of control `id` in rendered module HTML: the checked radio,
# the selected option, the checkbox state, or the number the control starts at.
ui_initial <- function(html, id) {
  attr <- function(tag, name) {
    m <- regmatches(tag, regexec(paste0(" ", name, "=\"([^\"]*)\""), tag))[[1L]]
    if (length(m) > 1L) m[[2L]]
  }
  # A select keeps its options in the body.
  sel <- regmatches(html, regexec(
    paste0("(?s)<select[^>]*id=\"[^\"]*-", id, "\"[^>]*>.*?</select>"), html, perl = TRUE
  ))[[1L]]
  if (length(sel)) {
    opt <- regmatches(sel, gregexpr("<option[^>]*selected[^>]*>", sel))[[1L]]
    return(if (length(opt)) attr(opt[[1L]], "value"))
  }
  tags <- regmatches(html, gregexpr("<input[^>]*>", html))[[1L]]
  own <- function(tag) {
    nm <- attr(tag, "id") %||% attr(tag, "name")
    !is.null(nm) && grepl(paste0("-", id, "$"), nm)
  }
  mine <- Filter(own, tags)
  if (!length(mine)) {
    return(NULL)
  }
  kind <- attr(mine[[1L]], "type")
  if (identical(kind, "radio")) {
    on <- Filter(function(t) grepl("checked", t), mine)
    return(if (length(on)) attr(on[[1L]], "value"))
  }
  if (identical(kind, "checkbox")) {
    return(grepl("checked", mine[[1L]]))
  }
  attr(mine[[1L]], "data-from") %||% attr(mine[[1L]], "value")
}

as_default <- function(x, like) {
  if (is.logical(like)) x else if (is.numeric(like)) as.numeric(x) else x
}

test_that("the spec defaults of the social protection levers are the initial values of its controls", {
  hs <- list(
    svy = data.frame(hh = 1:4, weight = 1, tx = c(1, 2, 3, 4)),
    pipeline = list(weather_exposure = list(weather_columns = "tx"))
  )
  d <- wise_default_policy()$sp
  shiny::testServer(mod_3_01_sp_server, args = list(
    selected_outcome = shiny::reactive(data.frame(name = "welfare", units = "PPP")),
    analysis_unit = shiny::reactive("hh"), hist_sim = shiny::reactive(hs),
    survey_weather = shiny::reactive(hs$svy), variable_list = shiny::reactive(NULL)
  ), {
    session$flushReact()
    html <- paste(vapply(
      c("sp_type_ui", "sp_trigger_ui", "sp_targeting_ui", "sp_budget_amount_ui", "sp_timing_ui", "amount_basis_ui"),
      function(o) output[[o]]$html, ""
    ), collapse = "\n")
    for (id in names(d)) {
      got <- ui_initial(html, id)
      expect_false(is.null(got), info = id)
      expect_identical(as_default(got, d[[id]]), d[[id]], info = id)
    }
  })
})

test_that("the spec defaults of the access levers are the initial values of their controls", {
  shown <- shiny::reactive(list(hh_covariates = c(
    "electricity", "imp_wat_rec", "imp_san_rec", "piped", "piped_to_prem", "imp_wat_san_rec",
    "ttime_health", "internet", "cellphone", "educ_com1_hh", "educ_com2_hh", "educ_com3_hh"
  )))
  check <- function(server, outputs, defaults) {
    shiny::testServer(server, args = list(
      selected_model = shown, survey_data = shiny::reactive(NULL), variable_list = shiny::reactive(NULL)
    ), {
      html <- paste(vapply(outputs, function(o) output[[o]]$html, ""), collapse = "\n")
      for (id in names(defaults)) {
        got <- ui_initial(html, id)
        expect_false(is.null(got), info = id)
        expect_identical(as_default(got, defaults[[id]]), defaults[[id]], info = id)
      }
    })
  }
  d <- wise_default_policy()
  check(mod_3_02_infra_server, c(
    "elec_ui", "water_ui", "sanitation_ui", "piped_ui", "piped_to_prem_ui", "imp_wat_san_ui", "health_ui"
  ), d$infra)
  check(mod_3_03_digital_server, c("internet_ui", "mobile_ui"), d$digital)
  check(mod_3_05_education_server, c("primary_ui", "secondary_ui", "postsec_ui"), d$education)
})

test_that("the lever modules return what the spec route builds from the same control values", {
  so <- list(units = "PPP", povline = 3)
  # Social protection: the module with every control at an explicit value.
  sp_values <- list(
    sp_type = "shock", budget_mode = "transfer_first", targeting = "exante_poor",
    targeting_threshold_pct = 30, inclusion_error_pct = 5, exclusion_error_pct = 15,
    error_concentration = 5, transfer_amount_usd = 70, amount_basis = "per_capita",
    admin_cost_pct = 8, trigger_type = "return_period", trigger_variable = "tx",
    trigger_direction = "below", trigger_return_period_years = 5, trigger_metric = "weather",
    payout_scope = "national_triggered", national_k_pct = 30, payments_per_activation = 2,
    dyn_geo = "worst_share", dyn_geo_pct = 40, dyn_welfare = TRUE, budget_rule = "loss_share",
    loss_share_pct = 60, annual_cap = 5e6, loss_event_pct = 12, transfer_timing = "anticipatory",
    forecast_pod_pct = 80, forecast_far_pct = 10, effect_multiplier = 1.4, trigger_pov_line = 3
  )
  spec <- wise_spec(model = list(), sim = list(), policy = list(sp = sp_values))
  expect_no_error(spec)
  shiny::testServer(mod_3_01_sp_server, args = list(
    selected_outcome = shiny::reactive(data.frame(name = "welfare", units = "PPP")),
    analysis_unit = shiny::reactive("hh")
  ), {
    do.call(session$setInputs, sp_values)
    from_module <- session$returned$sp_scenario()
    # The module leaves the fields it does not read for a shock program (a regular
    # program's timing) at its own fallbacks; the spec route fills the control
    # defaults. Both are the configuration of the same settings.
    from_spec <- wise_policy_configs(spec$policy, so, "hh")$sp
    for (f in names(sp_values)) {
      key <- switch(f, targeting_threshold_pct = "targeting_threshold", f)
      expect_equal(from_spec[[key]], from_module[[key]], info = f)
    }
    expect_identical(from_spec$transfer_n_payments, from_module$transfer_n_payments)
    expect_identical(from_spec$currency, from_module$currency)
  })

  # The access levers.
  infra <- list(elec_universal = TRUE, water_pct = 25, health_mode = "max", health_travel_max = 45)
  shiny::testServer(mod_3_02_infra_server, args = list(
    selected_model = shiny::reactive(list(hh_covariates = character(0))),
    survey_data = shiny::reactive(NULL), variable_list = shiny::reactive(NULL)
  ), {
    do.call(session$setInputs, infra)
    spec <- wise_spec(model = list(), sim = list(), policy = list(infra = infra))
    expect_equal(wise_policy_configs(spec$policy, so)$infra, session$returned$infra_scenario())
  })
  shiny::testServer(mod_3_03_digital_server, args = list(
    selected_model = shiny::reactive(list(hh_covariates = character(0))),
    survey_data = shiny::reactive(NULL), variable_list = shiny::reactive(NULL)
  ), {
    session$setInputs(mobile_universal = TRUE, internet_pct = -5)
    spec <- wise_spec(model = list(), sim = list(), policy = list(
      digital = list(mobile_universal = TRUE, internet_pct = -5)
    ))
    expect_equal(wise_policy_configs(spec$policy, so)$digital, session$returned$digital_scenario())
  })
  shiny::testServer(mod_3_05_education_server, args = list(
    selected_model = shiny::reactive(list(hh_covariates = character(0))),
    survey_data = shiny::reactive(NULL), variable_list = shiny::reactive(NULL)
  ), {
    session$setInputs(primary_pct = 20, postsec_universal = TRUE)
    spec <- wise_spec(model = list(), sim = list(), policy = list(
      education = list(primary_pct = 20, postsec_universal = TRUE)
    ))
    expect_equal(wise_policy_configs(spec$policy, so)$education, session$returned$education_scenario())
  })
  svy <- data.frame(
    agriculture = c(1, 1, 0, 0, 0), industry = c(0, 0, 1, 0, 0), services = c(0, 0, 0, 1, 1),
    weight = 1
  )
  shiny::testServer(mod_3_04_labor_server, args = list(
    selected_model = shiny::reactive(list(hh_covariates = c("agriculture", "industry", "services", "employed"))),
    survey_data = shiny::reactive(svy), variable_list = shiny::reactive(NULL)
  ), {
    session$setInputs(labor_emp = -3, sector_manufacturing = 35, sector_services = 40)
    spec <- wise_spec(model = list(), sim = list(), policy = list(
      labor = list(labor_emp = -3, sector_manufacturing = 35, sector_services = 40)
    ))
    expect_equal(
      wise_policy_configs(spec$policy, so, "hh", step3_sector_defaults(svy))$labor,
      session$returned$labor_scenario()
    )
    # Untouched sector sliders are "unchanged" on both routes.
    session$setInputs(sector_manufacturing = sector_defaults()[["industry"]], sector_services = sector_defaults()[["services"]])
    expect_null(session$returned$labor_scenario()$sector_manufacturing)
    expect_null(wise_policy_configs(list(labor = list(labor_emp = 0)), so, "hh", step3_sector_defaults(svy))$labor$sector_manufacturing)
  })
})

test_that("the step 3 input list has the arguments step3_compute() takes", {
  input <- wise_step3_input(svy = data.frame(a = 1), mf = list(engine = "fixest"), model_vars = "x", seed = 9L)
  expect_setequal(
    names(input),
    setdiff(names(formals(step3_compute)), c("hs", "ss", "progress"))
  )
  expect_identical(input$seed, 9L)
  expect_null(input$infra_cfg)
})

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
      expect_identical(outputs, "levers_ui")
      for (id in names(defaults)) {
        got <- ui_initial(html, id)
        expect_false(is.null(got), info = id)
        expect_identical(as_default(got, defaults[[id]]), defaults[[id]], info = id)
      }
    })
  }
  d <- wise_default_policy()
  check(mod_3_02_infra_server, "levers_ui", d$infra)
  check(mod_3_03_digital_server, "levers_ui", d$digital)
  check(mod_3_05_education_server, "levers_ui", d$education)
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
    forecast_pod_pct = 80, forecast_far_pct = 10, effect_multiplier = 1.4, trigger_pov_line = 3,
    timeliness_weeks = 4, delay_loss_pct_per_week = 5
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
    # Equal NA on both sides proves nothing (SP-09): the timing must be set.
    for (cfg in list(from_module, from_spec)) {
      expect_identical(cfg$transfer_timing, "anticipatory")
      expect_equal(cfg$timeliness_weeks, 4)
      expect_equal(cfg$delay_loss_pct_per_week, 5)
    }
  })

  # A percentile amount: the module and the spec route read the same baseline survey.
  svy <- data.frame(welfare = seq(1, 30, length.out = 200), weight = rep(c(1, 2), 100), hhsize = 4)
  pct_values <- list(
    sp_type = "regular", budget_mode = "transfer_first", targeting = "exante_poor",
    targeting_threshold_pct = 40, transfer_amount_mode = "pctile", transfer_pctile = 5,
    transfer_n_payments = 12, amount_basis = "per_household"
  )
  pct_spec <- wise_spec(model = list(), sim = list(), policy = list(sp = pct_values))
  shiny::testServer(mod_3_01_sp_server, args = list(
    selected_outcome = shiny::reactive(data.frame(name = "welfare", units = "PPP")),
    analysis_unit = shiny::reactive("hh"), hist_sim = shiny::reactive(list(svy = svy)),
    survey_weather = shiny::reactive(svy)
  ), {
    do.call(session$setInputs, pct_values)
    from_module <- session$returned$sp_scenario()
    from_spec <- wise_policy_configs(pct_spec$policy, so, "hh", svy = svy)$sp
    expect_identical(from_module$amount_resolved$status, "ok")
    expect_equal(from_module$transfer_amount_usd, from_spec$transfer_amount_usd)
    expect_equal(from_module$amount_resolved, from_spec$amount_resolved)
    expect_true(has_sp_change(from_module))
    expect_match(output$transfer_amount_resolved, "P5 of daily welfare")
  })

  # The access levers.
  infra <- list(electricity_universal = TRUE, water_pct = 25, health_mode = "max", health_travel_max = 45)
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
    session$setInputs(educ_primary_pct = 20, educ_postsec_universal = TRUE)
    spec <- wise_spec(model = list(), sim = list(), policy = list(
      education = list(educ_primary_pct = 20, educ_postsec_universal = TRUE)
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

test_that("wise_sp_config keeps the timing of a shock program and drops it for a regular one", {
  shock <- wise_sp_config(list(
    sp_type = "shock", transfer_timing = "anticipatory", forecast_pod_pct = 70, forecast_far_pct = 20,
    effect_multiplier = 1.5, timeliness_weeks = 4, delay_loss_pct_per_week = 5
  ))
  expect_identical(shock$transfer_timing, "anticipatory")
  expect_equal(shock$timeliness_weeks, 4)
  expect_equal(shock$forecast_pod_pct, 70)
  expect_equal(shock$delay_loss_pct_per_week, 5)
  expect_identical(shock$transfer_frequency, "oneoff")
  # Without timing controls a shock program is ex post with no delay.
  plain <- wise_sp_config(list(sp_type = "shock"))
  expect_identical(plain$transfer_timing, "expost")
  expect_equal(plain$timeliness_weeks, 0)
  # A regular program has no timing, whatever the controls hold.
  reg <- wise_sp_config(list(sp_type = "regular", transfer_timing = "anticipatory", timeliness_weeks = 4))
  expect_identical(reg$transfer_timing, NA_character_)
  expect_identical(reg$timeliness_weeks, NA_integer_)
  expect_identical(reg$transfer_frequency, "regular")
  expect_identical(wise_sp_config(list())$transfer_timing, NA_character_)
  # The delay reaches the plan: 4 weeks at 5 percent a week leaves 80 percent of the effect.
  delayed <- wise_sp_config(list(sp_type = "shock", timeliness_weeks = 4, delay_loss_pct_per_week = 5))
  expect_equal(.sp_timing_plan(delayed, NULL, 1L)$delay, 0.8)
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

# A weighted percentile of `welfare` with linear interpolation of the cumulative
# weight, as the legacy batch scripts took it (`.resolve_transfer_amount()`).
legacy_percentile <- function(welfare, weight, p) {
  o <- order(welfare)
  welfare <- welfare[o]
  weight <- weight[o]
  cw <- cumsum(weight) / sum(weight)
  idx <- which(cw >= p)[1L]
  welfare[idx - 1L] + (p - cw[idx - 1L]) / (cw[idx] - cw[idx - 1L]) * (welfare[idx] - welfare[idx - 1L])
}

test_that("wise_sp_resolve_amount sets the amount from the weighted welfare percentile", {
  set.seed(7)
  svy <- data.frame(welfare = rlnorm(2000, 1, 0.6), weight = runif(2000, 1, 5), ppp2021 = 3)
  sp <- wise_sp_config(list(transfer_amount_mode = "pctile", transfer_pctile = 10, transfer_n_payments = 12))
  r <- wise_sp_resolve_amount(sp, svy)
  expect_identical(r$amount_resolved$status, "ok")
  expect_equal(
    r$transfer_amount_usd,
    unname(collapse::fquantile(svy$welfare, 0.1, w = svy$weight)) * 365 / 12
  )
  # The same distribution as the ex-ante poor cutoff of the targeting.
  expect_equal(r$amount_resolved$daily_value, .sp_welfare_quantile(svy$welfare, svy$weight, 0.1))
  # Close to the legacy estimator (they differ in the weighted interpolation).
  legacy <- legacy_percentile(svy$welfare, svy$weight, 0.1) * 365 / 12
  expect_equal(r$transfer_amount_usd, legacy, tolerance = 0.01)
  expect_identical(r$amount_resolved$n_obs, 2000L)
  # LCU: percentile of welfare in local currency units.
  lcu <- wise_sp_resolve_amount(
    wise_sp_config(
      list(transfer_amount_mode = "pctile", transfer_pctile = 10, transfer_n_payments = 12),
      currency = "LCU"
    ),
    svy
  )
  expect_equal(lcu$transfer_amount_usd, 3 * r$transfer_amount_usd)
  # More payments, smaller payments, same year.
  p6 <- wise_sp_resolve_amount(
    wise_sp_config(list(transfer_amount_mode = "pctile", transfer_pctile = 10, transfer_n_payments = 6)), svy
  )
  expect_equal(p6$transfer_amount_usd * 6, r$transfer_amount_usd * 12)
  # Unusable rows are skipped; too few leave the lever inactive.
  svy$welfare[1:50] <- NA
  expect_identical(wise_sp_resolve_amount(sp, svy)$amount_resolved$n_obs, 1950L)
  few <- wise_sp_resolve_amount(sp, svy[1:9, ])
  expect_identical(few$amount_resolved$status, "unavailable")
  expect_identical(few$transfer_amount_usd, 0)
  expect_false(has_sp_change(few))
  # A fixed amount is untouched; a shock or budget-first program never uses a percentile.
  fixed <- wise_sp_config(list(transfer_amount_usd = 25))
  expect_identical(wise_sp_resolve_amount(fixed, svy), fixed)
  expect_identical(
    wise_sp_config(list(transfer_amount_mode = "pctile", sp_type = "shock"))$transfer_amount_mode, "fixed"
  )
  expect_identical(
    wise_sp_config(list(transfer_amount_mode = "pctile", budget_mode = "budget_first"))$transfer_amount_mode,
    "fixed"
  )
})

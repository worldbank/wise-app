# Step 1 model glue and tables for the batch pipeline: the core functions give
# the objects the Model and Results modules build, and the model tables hold
# the numbers the app's own tables show.

# Fixture ----

# A survey-weather frame with a known structure: welfare rises with household
# size and electricity access, and with temperature up to a turning point.
model_fixture <- function(n = 240L) {
  withr::with_seed(1L, {
    hhsize <- sample(1:9, n, replace = TRUE)
    electricity <- sample(0:1, n, replace = TRUE)
    tx <- stats::rnorm(n, 30, 3)
    sw <- data.frame(
      code = "TST", year = factor(rep(c(2018, 2019), each = n / 2)), survname = "SRV",
      welfare = exp(1.3 + 0.15 * hhsize + 0.4 * electricity - 0.002 * (tx - 30)^2 + stats::rnorm(n, 0, 0.2)),
      tx = tx, hhsize = hhsize, urban = sample(0:1, n, replace = TRUE),
      electricity = electricity, gaul1_code = rep(paste0("r", 1:4), length.out = n),
      loc_id_panel = rep(1:8, length.out = n), weight = 1, stringsAsFactors = FALSE
    )
  })
  vl <- batch_fixture_variable_list()
  vl$interact[vl$name == "urban"] <- 1
  vl <- rbind(vl, data.frame(
    name = c("year", "gaul1_code"), label = c("Year", "Region"), type = "character", units = "",
    id = NA_character_, outcome = 0, hazard = 0, ind = 0, hh = 0, firm = 0, area = 0, interact = 0,
    fe = 1
  ))
  so <- data.frame(
    name = "welfare", label = "Welfare", type = "numeric", units = "USD", transform = "log",
    povline = NA_real_, stringsAsFactors = FALSE
  )
  list(sw = sw, vl = vl, so = so)
}

model_fixture_weather <- function(vl, polynomial = "2", form = "Continuous") {
  wise_selected_weather(
    list(tx = utils::modifyList(
      wise_weather_var_defaults("degC"), list(form = form, polynomial = polynomial)
    )),
    vl
  )
}

# Fit through the core, as the batch pipeline and the Results tab do.
core_fit <- function(fx, type = "Linear regression", covs = list(hh = "hhsize"), swx = NULL,
                     outcome = fx$so, seed = 123L) {
  swx <- swx %||% model_fixture_weather(fx$vl)
  sm <- wise_selected_model(
    type, character(0), c("year", "gaul1_code"), "User-defined", covs,
    cluster = "loc_id_panel"
  )
  wise_fit(fx$sw, NULL, outcome, swx, sm, fx$vl, seed)
}

# The Results module on the same inputs, after one fit; `fun` gets the module's
# fit, its export items and the settings it was driven with.
drive_results <- function(fx, fun, type = "Linear regression", covs = list(hh = "hhsize"),
                          swx = NULL) {
  swx <- swx %||% model_fixture_weather(fx$vl)
  sm <- wise_selected_model(
    type, character(0), c("year", "gaul1_code"), "User-defined", covs,
    cluster = "loc_id_panel"
  )
  shiny::testServer(
    mod_1_07_results_server,
    args = list(
      id = "r", variable_list = shiny::reactiveVal(fx$vl),
      selected_surveys = shiny::reactiveVal(data.frame()),
      selected_outcome = shiny::reactiveVal(fx$so), selected_weather = shiny::reactiveVal(swx),
      survey_weather = shiny::reactiveVal(fx$sw), selected_model = shiny::reactiveVal(sm),
      run_model = shiny::reactiveVal(0L), tabset_id = "tabs"
    ),
    {
      settle <- function() {
        session$elapse(500)
        session$flushReact()
      }
      run_model(1L)
      settle()
      run_model(2L)
      settle()
      fun(model_fit_val(), wise_export_items(session))
    }
  )
}

# Small pieces ----

test_that("lasso settings fill the Model tab defaults and read the control labels", {
  d <- wise_default_lasso()
  expect_identical(wise_lasso_settings(), d)
  expect_false(wise_lasso_settings(standardize = "Do not standardize")$standardize)
  expect_true(wise_lasso_settings(standardize = "Standardize")$standardize)
  expect_false(wise_lasso_settings(standardize = FALSE)$standardize)
  expect_identical(wise_lasso_settings(alpha = 0.5, nfolds = 5L)$alpha, 0.5)
  expect_identical(wise_lasso_settings(alpha = 0.5, nfolds = 5L)$mi_m, d$mi_m)
})

test_that("lasso covariates join the level of their role flag, with forced variables applied", {
  vl <- data.frame(
    name = c("a", "b", "c", "d"), hh = c(1, 1, 0, 0), ind = c(0, 0, 1, 0), area = c(0, 0, 0, 1),
    firm = 0
  )
  forced <- list(
    hh = list(inc = "z", exc = "b"), ind = list(inc = character(0), exc = character(0)),
    firm = list(inc = character(0), exc = character(0)), area = list(inc = character(0), exc = character(0))
  )
  out <- wise_lasso_covariates(c("a", "b", "c", "d"), vl, forced)
  expect_identical(out$hh, c("a", "z"))
  expect_identical(out$ind, "c")
  expect_identical(out$area, "d")
  expect_identical(out$firm, character(0))
  expect_identical(wise_lasso_candidates(vl, "a")$name, c("b", "c", "d"))
  expect_identical(wise_lasso_candidates(vl), vl)
})

test_that("the cluster variable is the location panel when it was joined", {
  expect_identical(wise_cluster_var(c("welfare", "loc_id_panel")), "loc_id_panel")
  expect_null(wise_cluster_var(c("welfare", "loc_id")))
})

test_that("fit statistics: raw values format to the app's table", {
  fx <- model_fixture()
  mf <- core_fit(fx)
  raw <- fit_stats_raw(mf$fit3, FALSE)
  expect_identical(raw$statistic, c("nobs", "r2", "ar2", "wr2"))
  app <- calc_fit_stats(mf$fit3, FALSE)
  expect_identical(app$Value[1], formatC(raw$value[1], format = "f", digits = 0, big.mark = ","))
  expect_identical(app$Value[2], sprintf("%.2f", raw$value[2]))
  rif <- core_fit(fx, "Unconditional quantile regression (RIF)")
  r <- fit_stats_raw(rif$fit3, FALSE, "rif", rif$taus)
  expect_setequal(r$tau, rif$taus)
  expect_identical(nrow(r), 3L * length(rif$taus))
})

# The core and the modules ----

test_that("wise_fit gives the fit and snapshot the Results module builds", {
  fx <- model_fixture()
  mf <- core_fit(fx)
  expect_s3_class(mf$fit3, "fixest")
  expect_named(mf$.snap, c("outcome", "weather", "survey_weather", "variable_list", "model"))
  expect_identical(mf$.snap$model$cluster, "loc_id_panel")
  drive_results(fx, function(app, items) {
    for (m in c("fit1", "fit2", "fit3")) {
      expect_identical(stats::coef(app[[m]]), stats::coef(mf[[m]]), info = m)
      expect_identical(stats::vcov(app[[m]]), stats::vcov(mf[[m]]), info = m)
    }
    expect_identical(app$.snap$model, mf$.snap$model)
    expect_identical(app$train_data, mf$train_data)
  })
})

test_that("the fixest model tables hold the app's coefficient, fit, headline and focused tables", {
  fx <- model_fixture()
  mf <- core_fit(fx)
  tabs <- step1_model_tables(mf)
  drive_results(fx, function(app, items) {
    # Coefficients: the export table has one row per specification and term.
    coefs <- items$model_coefficients$fun()
    tt <- tabs$model_terms
    expect_identical(nrow(tt), nrow(coefs))
    expect_identical(tt$term, coefs$Term)
    expect_identical(tt$model, as.integer(substr(coefs$Model, 2, 2)))
    expect_identical(tt$estimate, coefs$Estimate)
    expect_identical(tt$std_error, coefs$`Std. error`)
    expect_identical(tt$p_value, coefs$`p value`)
    expect_identical(tt$n_obs, as.numeric(coefs$Observations))

    # Focused estimates: the translated effect sits on the weather terms of (3).
    foc <- items$step1_focused_estimates$fun()
    hit <- tt[tt$model == 3L & !is.na(tt$translation), ]
    expect_identical(hit$term, foc$Term)
    expect_identical(hit$translation, foc$Translation)
    expect_identical(hit$estimate, foc$Effect)

    # Headline cards.
    head <- items$step1_headline_summary$fun()
    h <- tabs$model_fit[tabs$model_fit$section == "headline", ]
    expect_identical(h$statistic, head$card)
    expect_identical(h$text, head$value)
    expect_identical(h$detail, head$detail)
    expect_identical(unique(h$variable), "tx")
  })

  # Fit statistics: raw values format to the Model fit tab's table.
  fit <- tabs$model_fit[tabs$model_fit$section == "fit" & tabs$model_fit$model == 3L, ]
  shown <- calc_fit_stats(mf$fit3, FALSE)
  expect_identical(
    shown$Value,
    c(
      formatC(fit$value[1], format = "f", digits = 0, big.mark = ","),
      sprintf("%.2f", fit$value[2:4])
    )
  )
})

test_that("the model tables have the documented columns and sections", {
  fx <- model_fixture()
  tabs <- step1_model_tables(core_fit(fx))
  expect_named(tabs$model_terms, c(
    "model", "term", "tau", "is_weather", "estimate", "std_error", "statistic", "p_value",
    "conf_low", "conf_high", "n_obs", "importance_share", "lasso_freq", "translation"
  ))
  expect_named(tabs$model_fit, c(
    "section", "variable", "model", "tau", "statistic", "value", "text", "detail"
  ))
  expect_named(tabs$model_vcov, c("tau", "term_1", "term_2", "covariance"))
  expect_setequal(
    unique(tabs$model_fit$section), c("fit", "sample", "spec", "effect_inputs", "headline")
  )
  tt <- tabs$model_terms
  expect_true(all(is.na(tt$tau)))
  expect_true(all(tt$is_weather[tt$term %in% c("tx", "I(I(tx^2))")]))
  expect_false(any(tt$is_weather[tt$term %in% c("hhsize", "(Intercept)")]))
  # Importance shares: specification (3) only, summing to 100 over its terms.
  expect_true(all(is.na(tt$importance_share[tt$model != 3L])))
  expect_equal(sum(tt$importance_share, na.rm = TRUE), 100)
  expect_true(all(is.na(tt$lasso_freq)))
  spec <- tabs$model_fit[tabs$model_fit$section == "spec", ]
  expect_identical(spec$text[spec$statistic == "vcov"], "clustered: loc_id_panel")
  expect_identical(spec$text[spec$statistic == "fixed_effects"], "year,gaul1_code")
  # Effect inputs: the model sample's range of the weather variable.
  ei <- tabs$model_fit[tabs$model_fit$section == "effect_inputs", ]
  expect_identical(ei$statistic, c("x_min", "x_max", "x_mean", "x_sd"))
  expect_equal(ei$value[ei$statistic == "x_min"], min(fx$sw$tx))
  expect_equal(ei$value[ei$statistic == "x_max"], max(fx$sw$tx))
})

test_that("model_vcov is the weather block of the fit's covariance", {
  fx <- model_fixture()
  mf <- core_fit(fx)
  v <- model_vcov_table(mf)
  V <- stats::vcov(mf$fit3)
  expect_setequal(unique(v$term_1), c("tx", "I(I(tx^2))"))
  expect_identical(nrow(v), 4L)
  for (i in seq_len(nrow(v))) {
    expect_identical(v$covariance[i], V[v$term_1[i], v$term_2[i]])
  }
  # Symmetric.
  m <- stats::xtabs(covariance ~ term_1 + term_2, v)
  expect_equal(unname(m), unname(t(m)))
})

test_that("RIF tables have a coefficient and covariance block per quantile", {
  fx <- model_fixture()
  mf <- core_fit(fx, "Unconditional quantile regression (RIF)")
  tabs <- step1_model_tables(mf)
  tt <- tabs$model_terms
  expect_setequal(tt$tau, mf$taus)
  g <- mf$rif_grid
  expect_identical(nrow(tt), nrow(g))
  expect_identical(
    tt$estimate[tt$model == 3L & tt$tau == 0.5],
    g$estimate[g$model == 3L & g$tau == 0.5]
  )
  # The importance shares come from the median quantile model only.
  expect_true(all(is.na(tt$importance_share[tt$tau != 0.5 | tt$model != 3L])))
  expect_equal(sum(tt$importance_share, na.rm = TRUE), 100)
  v <- tabs$model_vcov
  expect_setequal(v$tau, mf$taus)
  expect_identical(
    v$covariance[v$tau == 0.1 & v$term_1 == "tx" & v$term_2 == "tx"],
    stats::vcov(mf$fit3[[1]])["tx", "tx"]
  )
  f <- tabs$model_fit
  expect_setequal(f$tau[f$section == "fit"], mf$taus)
  # The quantile translation sits on the median.
  expect_true(all(is.na(tt$translation[tt$tau != 0.5])))
  expect_true(any(!is.na(tt$translation[tt$tau == 0.5])))
})

test_that("a binned weather variable has bin terms and no continuous range", {
  fx <- model_fixture()
  fx$sw$tx <- cut(fx$sw$tx, c(-Inf, 28, 31, Inf), labels = c("[0, 28]", "(28, 31]", "(31, 99]"))
  swx <- model_fixture_weather(fx$vl, polynomial = character(0), form = "Binned")
  mf <- core_fit(fx, swx = swx)
  tabs <- step1_model_tables(mf)
  tt <- tabs$model_terms
  expect_true(any(grepl("^tx", tt$term[tt$is_weather])))
  expect_false("x_min" %in% tabs$model_fit$statistic)
  expect_true(nrow(tabs$model_vcov) > 0L)
})

test_that("a Lasso selection frequency is attached to the covariate it describes", {
  fx <- model_fixture()
  mf <- core_fit(fx, covs = list(hh = c("hhsize", "electricity")))
  tt <- model_terms_table(mf, selection_frequency = c(hhsize = 1, electricity = 0.8))
  expect_identical(tt$lasso_freq[tt$model == 3L & tt$term == "hhsize"], 1)
  expect_identical(tt$lasso_freq[tt$model == 3L & tt$term == "electricity"], 0.8)
  expect_true(all(is.na(tt$lasso_freq[tt$model != 3L])))
})

test_that("the Model module's specification and Lasso match the core", {
  fx <- model_fixture()
  shiny::testServer(
    mod_1_06_model_server,
    args = list(
      id = "m", variable_list = shiny::reactiveVal(fx$vl),
      selected_surveys = shiny::reactiveVal(data.frame()), analysis_unit = shiny::reactiveVal("hh"),
      selected_outcome = shiny::reactiveVal(fx$so),
      selected_weather = shiny::reactiveVal(model_fixture_weather(fx$vl)),
      survey_weather = shiny::reactiveVal(fx$sw)
    ),
    {
      session$setInputs(
        model_type = "Linear regression", interactions = character(0),
        fixedeffects = c("year", "gaul1_code"), covariates = "User-defined", hhcov = "hhsize"
      )
      session$flushReact()
      user <- selected_model()
      core_user <- wise_selected_model(
        "Linear regression", character(0), c("year", "gaul1_code"), "User-defined",
        list(hh = "hhsize", area = character(0), ind = character(0), firm = character(0)),
        lasso = list(standardize = FALSE), cluster = "loc_id_panel"
      )
      expect_identical(user, core_user)

      session$setInputs(covariates = "Lasso")
      session$setInputs(run_model = 0L)
      session$setInputs(run_model = 1L)
      session$flushReact()
      app_lasso <- selected_model()

      valid <- wise_valid_vars(fx$sw, fx$vl, "welfare")
      sel <- wise_lasso_selection(
        prepare_outcome_df(fx$sw, fx$so), fx$so, "tx", c("year", "gaul1_code"), character(0),
        wise_lasso_candidates(valid), "Linear regression", wise_lasso_settings(),
        wise_current_seed()
      )
      expect_true(all(c("hhsize", "electricity") %in% sel$selected_covariates))
      forced <- stats::setNames(
        rep(list(list(inc = character(0), exc = character(0))), 4L), c("ind", "hh", "firm", "area")
      )
      covs <- wise_lasso_covariates(sel$selected_covariates, valid, forced)
      expect_identical(app_lasso$hh_covariates, covs$hh)
      expect_identical(app_lasso$area_covariates, covs$area)
    }
  )
})

test_that("interactions and the policy scenario of the spec give the Model tab's specification", {
  fx <- model_fixture()
  swx <- model_fixture_weather(fx$vl)
  spec_model <- function(...) {
    m <- wise_spec(model = list(
      type = "linear", fixed_effects = c("year", "gaul1_code"),
      covariates = list(vars = "hhsize"), ...
    ))$model
    wise_model_from_spec(m, "hh", fx$sw, fx$so, swx, fx$vl, 123L)$selected_model
  }
  # Without them: no interaction, as in earlier phases.
  expect_identical(spec_model()$interactions, character(0))

  app_model <- function(interactions = character(0), policies = NULL) {
    out <- NULL
    shiny::testServer(
      mod_1_06_model_server,
      args = list(
        id = "m", variable_list = shiny::reactiveVal(fx$vl),
        selected_surveys = shiny::reactiveVal(data.frame()), analysis_unit = shiny::reactiveVal("hh"),
        selected_outcome = shiny::reactiveVal(fx$so), selected_weather = shiny::reactiveVal(swx),
        survey_weather = shiny::reactiveVal(fx$sw)
      ),
      {
        session$setInputs(
          model_type = "Linear regression", interactions = interactions,
          fixedeffects = c("year", "gaul1_code"), covariates = "User-defined", hhcov = "hhsize",
          selected_policies = policies
        )
        session$flushReact()
        out <<- selected_model()
      }
    )
    out
  }
  # The fields the interaction touches (the spec orders fixed effects, and the
  # module's standardise flag is a control the test does not set).
  same <- function(a, b) {
    f <- c("interactions", "hh_covariates", "area_covariates", "model_type", "covariate_selection")
    expect_identical(a[f], b[f])
  }
  # A chosen moderator.
  same(spec_model(interactions = "urban"), app_model("urban"))
  expect_identical(spec_model(interactions = "urban")$interactions, "urban")
  # A policy scenario locks its variable as an interaction.
  same(spec_model(policy_vars = "A"), app_model(character(0), "A"))
  expect_identical(spec_model(policy_vars = "A")$interactions, "electricity")
  both <- spec_model(interactions = "urban", policy_vars = "A")
  expect_setequal(both$interactions, c("urban", "electricity"))
  # The moderator is not offered as a covariate too.
  expect_error(
    wise_model_from_spec(
      wise_spec(model = list(
        type = "linear", covariates = list(vars = c("hhsize", "urban")), interactions = "urban"
      ))$model,
      "hh", fx$sw, fx$so, swx, fx$vl, 123L
    ),
    "Covariate"
  )
  # Variables the data does not offer for the role are refused.
  expect_error(
    wise_model_from_spec(
      wise_spec(model = list(type = "linear", interactions = "hhsize"))$model,
      "hh", fx$sw, fx$so, swx, fx$vl, 123L
    ),
    "Interaction variable"
  )
  vl2 <- fx$vl[fx$vl$name != "ttime_health", ]
  expect_error(
    wise_model_from_spec(
      wise_spec(model = list(type = "linear", policy_vars = "D"))$model,
      "hh", fx$sw, fx$so, swx, vl2, 123L
    ),
    "Policy scenario"
  )
})

test_that("the model_fit table keeps the values of the moderators", {
  fx <- model_fixture()
  swx <- model_fixture_weather(fx$vl)
  sm <- wise_selected_model(
    "Linear regression", "urban", c("year", "gaul1_code"), "User-defined",
    list(hh = "hhsize"), cluster = "loc_id_panel"
  )
  mf <- wise_fit(fx$sw, NULL, fx$so, swx, sm, fx$vl, 123L)
  tab <- model_fit_table(mf)
  mod <- tab[tab$section == "effect_inputs" & tab$variable %in% "urban", ]
  expect_setequal(mod$statistic, c("mod_min", "mod_max", "mod_mean", "mod_sd", "mod_n_distinct"))
  z <- mf$train_data$urban
  expect_equal(mod$value[mod$statistic == "mod_mean"], mean(z))
  expect_equal(mod$value[mod$statistic == "mod_sd"], stats::sd(z))
  expect_identical(mod$value[mod$statistic == "mod_n_distinct"], 2)
  # The weather variable keeps its rows; a fit without moderators has none.
  expect_true("x_mean" %in% tab$statistic[tab$variable %in% "tx"])
  plain <- model_fit_table(wise_fit(
    fx$sw, NULL, fx$so, swx,
    wise_selected_model("Linear regression", character(0), c("year", "gaul1_code"), "User-defined",
      list(hh = "hhsize"), cluster = "loc_id_panel"),
    fx$vl, 123L
  ))
  expect_false(any(grepl("^mod_", plain$statistic)))
})

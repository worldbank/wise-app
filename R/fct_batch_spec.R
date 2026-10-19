# Batch run spec ----
# One canonical, plain-list description of a single run (`wise_spec()`), its
# validation, its stage hashes, and the YAML grid that expands to many runs.
# App defaults live in `wise_spec_defaults()` (fct_spec_defaults.R). Phases 1
# to 3 cover the `source`, `sample`, `outcome`, `weather`, `stats`, `model`
# and `sim` sections; the policy section arrives with its phase. Shiny-free.

# Construction ----

# Deep merge: values of `over` replace those of `base`; named lists merge.
# A `NULL` in `over` leaves the base value alone.
#' @noRd
.spec_merge <- function(base, over) {
  if (is.null(over)) {
    return(base)
  }
  if (is.null(base)) {
    return(over)
  }
  if (is.list(over) && !length(over)) {
    return(base)
  }
  if (is.list(base) && is.list(over) && !is.null(names(over)) && !is.null(names(base))) {
    for (nm in names(over)) {
      if (!is.null(over[[nm]])) base[[nm]] <- .spec_merge(base[[nm]], over[[nm]])
    }
    return(base)
  }
  over
}

# Weather variable fields that follow a rule and stay empty until resolved.
.WX_RULE_FIELDS <- c("temporal_agg", "transformation")
.WX_FORMS <- c("Binned", "Continuous")
.WX_BINNING <- c("Equal frequency", "Equal width", "K-means", "Custom")
.WX_AGG <- c("Mean", "Median", "Min", "Max", "Sum")
.WX_TRANSFORMS <- c("None", "Deviation from mean", "Standardized anomaly")

# Scalar character, lower-cased match against the allowed set (YAML-friendly).
#' @noRd
.match_choice <- function(x, choices) {
  if (is.null(x) || length(x) != 1L || is.na(x)) {
    return(x)
  }
  hit <- choices[tolower(choices) == tolower(as.character(x))]
  if (length(hit)) hit else x
}

# Normalise one weather variable entry: static defaults filled, fields that do
# not apply to the chosen form dropped, so equal specs hash equal.
#' @noRd
.normalise_wx_var <- function(v) {
  v <- v %||% list()
  static <- wise_weather_var_defaults("none")
  static[.WX_RULE_FIELDS] <- NULL
  v <- .spec_merge(static, v)
  v$form <- .match_choice(v$form, .WX_FORMS)
  v$temporal_agg <- .match_choice(v$temporal_agg, .WX_AGG)
  v$transformation <- .match_choice(v$transformation, .WX_TRANSFORMS)
  v$binning_method <- .match_choice(v$binning_method, .WX_BINNING)
  v$ref_period <- as.integer(unlist(v$ref_period))
  if (identical(v$form, "Continuous")) {
    v$n_bins <- NULL
    v$binning_method <- NULL
    v$custom_breaks <- NULL
    v$polynomial <- as.character(unlist(v$polynomial))
  } else {
    v$n_bins <- as.integer(v$n_bins)
    v$polynomial <- NULL
    v$custom_breaks <- if (identical(v$binning_method, "Custom")) {
      parse_custom_breaks(unlist(v$custom_breaks))
    }
  }
  v[order(names(v))]
}

# Model section ----

.MODEL_LAMBDAS <- c("lambda.1se", "lambda.min")
.MODEL_METHODS <- c("user", "lasso")

# Short names accepted for the model types, case-insensitive.
.MODEL_ALIASES <- c(
  linear = "Linear regression", logistic = "Logistic regression",
  logit = "Logistic regression", rif = "Unconditional quantile regression (RIF)",
  quantile = "Unconditional quantile regression (RIF)"
)

#' @noRd
.match_model_type <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x)) {
    return(x)
  }
  key <- tolower(as.character(x))
  hit <- names(WISEAPP_MODEL_TYPES)[tolower(names(WISEAPP_MODEL_TYPES)) == key]
  if (length(hit)) hit else if (key %in% names(.MODEL_ALIASES)) .MODEL_ALIASES[[key]] else x
}

# Normalise the model section: defaults filled, choices canonical, sets sorted
# and fields that do not apply to the covariate method dropped, so equal specs
# hash equal. `type` and `fixed_effects` stay absent until the data decides.
#' @noRd
.normalise_model <- function(m) {
  m <- .spec_merge(wise_default_model(), m)
  chr <- function(x) sort(unique(as.character(unlist(x))))
  if (!is.null(m$type)) m$type <- .match_model_type(m$type)
  if (!is.null(m$fixed_effects)) m$fixed_effects <- chr(m$fixed_effects)
  cv <- m$covariates
  method <- tolower(as.character(cv$method))
  cv$method <- if (identical(method, "user-defined")) "user" else method
  if (identical(cv$method, "lasso")) {
    cv$vars <- NULL
    l <- cv$lasso
    l$alpha <- as.numeric(l$alpha)
    l$lambda <- .match_choice(as.character(l$lambda), .MODEL_LAMBDAS)
    for (f in c("nfolds", "mi_m", "mi_maxit")) l[[f]] <- as.integer(l[[f]])
    for (f in c("standardize", "use_mice")) l[[f]] <- as.logical(l[[f]])
    l$stability_threshold <- as.numeric(l$stability_threshold)
    l$force_in <- chr(l$force_in)
    l$force_out <- chr(l$force_out)
    cv$lasso <- l[order(names(l))]
  } else {
    cv$lasso <- NULL
    cv$vars <- chr(cv$vars)
  }
  m$covariates <- cv[order(names(cv))]
  m[order(names(m))]
}

# Problems of the model section on its own (data-dependent checks follow in
# `wise_spec_resolve()`).
#' @noRd
.model_problems <- function(m) {
  bad <- character(0)
  add <- function(...) bad <<- c(bad, paste0(...))
  unknown <- setdiff(names(m), c("type", "fixed_effects", "covariates"))
  if (length(unknown)) {
    add(
      "model.", paste(unknown, collapse = ", "), ": not a model setting in this version ",
      "(interactions and policy variables arrive with the policy phase)."
    )
  }
  if (!is.null(m$type) && !m$type %in% names(WISEAPP_MODEL_TYPES)) {
    add("model.type must be one of: ", paste(names(WISEAPP_MODEL_TYPES), collapse = ", "), ".")
  }
  fe <- m$fixed_effects
  if (!is.null(fe) && (anyNA(fe) || !all(nzchar(fe)))) add("model.fixed_effects must be variable names.")
  cv <- m$covariates
  if (length(setdiff(names(cv), c("method", "vars", "lasso")))) {
    add("model.covariates holds method, vars and lasso only.")
  }
  if (!cv$method %in% .MODEL_METHODS) {
    add("model.covariates.method must be one of: ", paste(.MODEL_METHODS, collapse = ", "), ".")
  }
  if (anyNA(cv$vars) || !all(nzchar(cv$vars))) add("model.covariates.vars must be variable names.")
  if (identical(cv$method, "lasso")) {
    l <- cv$lasso
    p <- "model.covariates.lasso."
    in_range <- function(x, lo, hi) length(x) == 1L && is.finite(x) && x >= lo && x <= hi
    if (!in_range(l$alpha, 0, 1)) add(p, "alpha must be between 0 and 1.")
    if (!l$lambda %in% .MODEL_LAMBDAS) add(p, "lambda must be one of: ", paste(.MODEL_LAMBDAS, collapse = ", "), ".")
    if (!in_range(l$nfolds, 5, 20)) add(p, "nfolds must be between 5 and 20.")
    if (!in_range(l$mi_m, 1, 20)) add(p, "mi_m must be between 1 and 20.")
    if (!in_range(l$mi_maxit, 1, 20)) add(p, "mi_maxit must be between 1 and 20.")
    if (!in_range(l$stability_threshold, 0.1, 1)) add(p, "stability_threshold must be between 0.1 and 1.")
    for (f in c("standardize", "use_mice")) {
      if (length(l[[f]]) != 1L || is.na(l[[f]])) add(p, f, " must be true or false.")
    }
    both <- intersect(l$force_in, l$force_out)
    if (length(both)) add(p, "force_in and force_out share: ", paste(both, collapse = ", "), ".")
  }
  bad
}

# Simulation section ----

.SIM_RESIDUALS <- c("original", "resample")
.SIM_FIELDS <- c(
  "hist_years", "future_periods", "ssps", "residuals", "coef_uncertainty",
  "propagate_all_covariate_uncertainty", "baseline_survey"
)

# Normalise the simulation section: defaults filled field by field (an empty
# `future_periods` or `ssps` means "none", not "the default"), scenarios in the
# order the app runs them, the baseline sorted, so equal specs hash equal.
# Unknown fields are kept for the validation to report. Periods stay in the
# order given: the order of the runs sets the random stream of the residual
# draws.
#' @noRd
.normalise_sim <- function(s) {
  d <- wise_default_sim()
  pick <- function(f) if (is.null(s[[f]])) d[[f]] else s[[f]]
  periods <- pick("future_periods")
  if (is.atomic(periods) && length(periods) == 2L) periods <- list(periods)
  ssps <- unique(tolower(as.character(unlist(pick("ssps")))))
  out <- list(
    hist_years = as.integer(unlist(pick("hist_years"))),
    future_periods = unname(lapply(periods, function(p) as.integer(unlist(p)))),
    ssps = c(intersect(WISEAPP_SSP_CODES, ssps), setdiff(ssps, WISEAPP_SSP_CODES)),
    residuals = .match_choice(as.character(pick("residuals")), .SIM_RESIDUALS),
    coef_uncertainty = as.logical(pick("coef_uncertainty")),
    propagate_all_covariate_uncertainty = as.logical(pick("propagate_all_covariate_uncertainty"))
  )
  if (!is.null(s$baseline_survey)) {
    out$baseline_survey <- sort(unique(as.character(unlist(s$baseline_survey))))
  }
  out <- c(out, s[setdiff(names(s), .SIM_FIELDS)])
  out[order(names(out))]
}

# Problems of the simulation section on its own.
#' @noRd
.sim_problems <- function(s) {
  bad <- character(0)
  add <- function(...) bad <<- c(bad, paste0(...))
  unknown <- setdiff(names(s), .SIM_FIELDS)
  if (length(unknown)) add("sim.", paste(unknown, collapse = ", "), ": not a simulation setting.")
  hy <- s$hist_years
  if (length(hy) != 2L || anyNA(hy) || hy[1] > hy[2] || hy[1] < WISEAPP_SIM_HIST_RANGE[[1L]] ||
    hy[2] > WISEAPP_SIM_HIST_RANGE[[2L]]) {
    add(
      "sim.hist_years must be two years between ", WISEAPP_SIM_HIST_RANGE[[1L]], " and ",
      WISEAPP_SIM_HIST_RANGE[[2L]], ", in ascending order."
    )
  }
  fp <- s$future_periods
  if (length(fp) > 3L) add("sim.future_periods: at most three projection periods (the app limit).")
  for (i in seq_along(fp)) {
    p <- fp[[i]]
    if (length(p) != 2L || anyNA(p) || p[2] <= p[1] || p[1] < .STEP2_SSP_START_YEAR ||
      p[2] > .STEP2_SSP_END_YEAR) {
      add(
        "sim.future_periods[", i, "] must be two years, the end after the start, between ",
        .STEP2_SSP_START_YEAR, " (the first year of the climate projections) and ",
        .STEP2_SSP_END_YEAR, "."
      )
    }
  }
  if (anyDuplicated(fp)) add("sim.future_periods: a period is listed twice.")
  bad_ssp <- setdiff(s$ssps, WISEAPP_SSP_CODES)
  if (length(bad_ssp)) {
    add(
      "sim.ssps must be among: ", paste(WISEAPP_SSP_CODES, collapse = ", "),
      " (not ", paste(bad_ssp, collapse = ", "), ")."
    )
  }
  if (length(fp) && !length(s$ssps)) add("sim.ssps: choose at least one scenario when future_periods are set.")
  if (length(s$residuals) != 1L || !s$residuals %in% .SIM_RESIDUALS) {
    add("sim.residuals must be one of: ", paste(.SIM_RESIDUALS, collapse = ", "), ".")
  }
  for (f in c("coef_uncertainty", "propagate_all_covariate_uncertainty")) {
    if (length(s[[f]]) != 1L || is.na(s[[f]])) add("sim.", f, " must be true or false.")
  }
  b <- s$baseline_survey
  if (!is.null(b) && (!length(b) || !all(grepl("^[^|]+\\|[0-9]{4}$", b)))) {
    add("sim.baseline_survey must list survey waves as CODE|YEAR (for example BFA|2021).")
  }
  bad
}

# Shallow merge for the simulation section: its fields are flat, and an empty
# value (`future_periods: []`) is a setting, not an absent one.
#' @noRd
.merge_sim <- function(base, over) {
  base <- base %||% list()
  for (nm in names(over)) {
    if (!is.null(over[[nm]])) base[nm] <- list(over[[nm]])
  }
  base
}

# The simulation settings that change results: residuals are not drawn for RIF
# and a run without projection periods has no scenarios.
#' @noRd
.sim_effective <- function(spec) {
  s <- spec$sim
  if (identical(spec$model$type, "Unconditional quantile regression (RIF)")) s$residuals <- "none"
  if (!length(s$future_periods)) s$ssps <- character(0)
  s
}

# Normalise a spec: types coerced, empty optional fields dropped, vectors in a
# canonical order.
#' @noRd
.spec_normalise <- function(spec) {
  if (!is.null(spec$model)) spec$model <- .normalise_model(spec$model)
  if (!is.null(spec$sim)) spec$sim <- .normalise_sim(spec$sim)
  spec$seed <- as.integer(spec$seed)
  spec$schema_version <- as.integer(spec$schema_version)
  spec$source$type <- as.character(spec$source$type)
  s <- spec$sample
  s$unit <- as.character(s$unit)
  s$countries <- if (is.null(s$countries)) NULL else sort(unique(as.character(unlist(s$countries))))
  s$years <- if (length(s$years)) {
    yrs <- lapply(s$years, function(y) sort(unique(as.integer(unlist(y)))))
    yrs[order(names(yrs))]
  }
  spec$sample <- s
  o <- spec$outcome
  o$name <- if (is.null(o$name)) NULL else as.character(o$name)
  o$currency <- as.character(o$currency)
  o$poverty_line <- if (is.null(o$poverty_line)) NULL else as.numeric(o$poverty_line)
  spec$outcome <- o
  w <- spec$weather
  w$hist_years <- as.integer(unlist(w$hist_years))
  for (v in wise_spec_weather_vars(w)) w[[v]] <- .normalise_wx_var(w[[v]])
  spec$weather <- w[c(sort(wise_spec_weather_vars(w)), "hist_years")]
  spec$stats$location_samples <- isTRUE(as.logical(spec$stats$location_samples))
  ind <- spec$stats$indicators
  spec$stats$indicators <- lapply(ind[order(names(ind))], function(i) {
    list(
      variable = as.character(i$variable), operator = as.character(i$operator),
      threshold = as.numeric(i$threshold)
    )
  })
  spec
}

#' Build a run spec
#'
#' Fills omitted fields from `wise_spec_defaults()` and normalises types, so a
#' spec that leaves a setting out is the same spec as one that states the
#' app default. Weather variables are named entries of `weather`
#' (`weather = list(tx = list(ref_period = c(1, 3), form = "Continuous"))`).
#'
#' @param ... Spec sections as named lists (`sample`, `outcome`, `weather`,
#'   `stats`, `source`) and `seed`; or one list holding them.
#'
#' @return A validated spec (plain named list).
#' @export
wise_spec <- function(...) {
  args <- list(...)
  if (length(args) == 1L && is.null(names(args)) && is.list(args[[1L]])) args <- args[[1L]]
  unknown <- setdiff(names(args), c(WISEAPP_SPEC_SECTIONS, "seed", "schema_version"))
  if (length(unknown)) {
    stop(
      "Unknown spec section(s): ", paste(unknown, collapse = ", "),
      ". This version supports: ", paste(c(WISEAPP_SPEC_SECTIONS, "seed"), collapse = ", "),
      ".", call. = FALSE
    )
  }
  spec <- wise_spec_validate(.spec_normalise(.spec_merge(wise_spec_defaults(), args)))
  spec
}

# Validation ----

#' Validate a run spec
#'
#' Applies the rules of the app's controls (allowed values, ranges, at most
#' two economies and two weather variables). Data-dependent checks (units of a
#' weather variable, available surveys) run in `wise_spec_resolve()`.
#'
#' @param spec A normalised spec.
#' @return `spec`, invisibly, or an error listing every problem.
#' @export
wise_spec_validate <- function(spec) {
  bad <- character(0)
  add <- function(...) bad <<- c(bad, paste0(...))
  if (!identical(spec$schema_version, 1L)) add("schema_version must be 1.")
  if (length(spec$seed) != 1L || is.na(spec$seed)) add("seed must be a single integer.")
  if (!spec$source$type %in% .CONNECTION_TYPES) {
    add("source.type must be one of: ", paste(.CONNECTION_TYPES, collapse = ", "), ".")
  }
  if (!identical(length(spec$sample$unit), 1L) || !spec$sample$unit %in% c("ind", "hh", "firm")) {
    add("sample.unit must be one of: ind, hh, firm.")
  }
  cs <- spec$sample$countries
  if (!is.null(cs) && (!length(cs) || length(cs) > 2L || anyNA(cs) || !all(nzchar(cs)))) {
    add("sample.countries must hold one or two economy codes (the app selects at most two).")
  }
  for (code in names(spec$sample$years)) {
    if (!is.null(cs) && !code %in% cs) add("sample.years names '", code, "', which is not in sample.countries.")
    if (anyNA(spec$sample$years[[code]])) add("sample.years.", code, " must be whole years.")
  }
  if (!spec$outcome$currency %in% c("PPP", "LCU")) add("outcome.currency must be PPP or LCU.")
  pl <- spec$outcome$poverty_line
  if (!is.null(pl) && (length(pl) != 1L || !is.finite(pl) || pl <= 0)) {
    add("outcome.poverty_line must be a positive number.")
  }
  w <- spec$weather
  vars <- wise_spec_weather_vars(w)
  if (length(vars) > 2L) add("weather: select at most two variables (the app limit).")
  hy <- w$hist_years
  this_year <- as.integer(format(Sys.Date(), "%Y"))
  if (length(hy) != 2L || anyNA(hy) || hy[1] > hy[2] || hy[1] < 1950L || hy[2] > this_year) {
    add("weather.hist_years must be two years, 1950 or later, in ascending order.")
  }
  for (v in vars) {
    x <- w[[v]]
    p <- paste0("weather.", v, ".")
    rp <- x$ref_period
    if (length(rp) != 2L || anyNA(rp) || rp[1] < 0L || rp[2] > 12L || rp[1] > rp[2]) {
      add(p, "ref_period must be two months before the interview, 0 to 12, in ascending order.")
    }
    if (!is.null(x$temporal_agg) && !x$temporal_agg %in% .WX_AGG) {
      add(p, "temporal_agg must be one of: ", paste(.WX_AGG, collapse = ", "), ".")
    }
    if (!is.null(x$transformation) && !x$transformation %in% .WX_TRANSFORMS) {
      add(p, "transformation must be one of: ", paste(.WX_TRANSFORMS, collapse = ", "), ".")
    }
    if (!x$form %in% .WX_FORMS) add(p, "form must be Binned or Continuous.")
    if (identical(x$form, "Binned")) {
      if (length(x$n_bins) != 1L || is.na(x$n_bins) || x$n_bins < 2L || x$n_bins > 10L) {
        add(p, "n_bins must be between 2 and 10.")
      }
      if (!x$binning_method %in% .WX_BINNING) {
        add(p, "binning_method must be one of: ", paste(.WX_BINNING, collapse = ", "), ".")
      }
      if (identical(x$binning_method, "Custom") && !length(x$custom_breaks)) {
        add(p, "custom_breaks must hold at least one value for Custom binning.")
      }
    } else if (identical(x$form, "Continuous") && !all(x$polynomial %in% c("2", "3"))) {
      add(p, "polynomial must be a subset of 2 and 3.")
    }
  }
  if (!is.logical(spec$stats$location_samples)) add("stats.location_samples must be true or false.")
  for (nm in names(spec$stats$indicators)) {
    i <- spec$stats$indicators[[nm]]
    if (!i$operator %in% c("<", ">") || !is.finite(i$threshold) || !nzchar(i$variable)) {
      add("stats.indicators.", nm, " needs variable, operator (< or >) and a numeric threshold.")
    }
    if (!grepl("^[A-Za-z][A-Za-z0-9_]*$", nm)) {
      add("stats.indicators.", nm, ": the name must be a valid column name.")
    }
  }
  if (!is.null(spec$model)) bad <- c(bad, .model_problems(spec$model))
  if (!is.null(spec$sim)) {
    if (is.null(spec$model)) add("sim: a simulation needs a model section (use `model: {}` for the app defaults).")
    bad <- c(bad, .sim_problems(spec$sim))
  }
  if (length(bad)) {
    stop(
      structure(
        class = c("wise_spec_error", "error", "condition"),
        list(
          message = paste0("Invalid run spec:\n", paste0("  - ", bad, collapse = "\n")),
          call = NULL, problems = bad
        )
      )
    )
  }
  invisible(spec)
}

# Resolution against the data ----

#' Resolve data-dependent defaults of a spec
#'
#' Fills the fields that follow a rule on the available data: the default
#' economy, every survey year, the first weather variable and the
#' unit-dependent aggregation and transformation of each weather variable.
#' With `survey_columns` the default outcome (the first available outcome
#' variable) and the default model type are resolved too, so the stage ids
#' encode them; without it `outcome.name` stays as given.
#'
#' @param spec A spec from `wise_spec()`.
#' @param metadata Output of `load_overview_metadata()`.
#' @param connection_params Connection parameter list.
#' @param survey_columns `NULL`, a character vector of the survey's column
#'   names, or a function of the (sample-resolved) spec returning one.
#' @return The resolved spec.
#' @export
wise_spec_resolve <- function(spec, metadata, connection_params, survey_columns = NULL) {
  sv <- wise_available_surveys(metadata$survey_list, spec$sample$unit, connection_params)
  codes <- unique(sv$code)
  cs <- spec$sample$countries %||% wise_default_economy(codes)
  unknown <- setdiff(cs, codes)
  if (length(unknown)) {
    stop(
      "No ", spec$sample$unit, " surveys available for: ", paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  avail <- get_available_years(sv, cs)
  years <- lapply(stats::setNames(cs, cs), function(code) {
    y <- spec$sample$years[[code]] %||% wise_default_years(avail[[code]])
    miss <- setdiff(y, avail[[code]])
    if (length(miss)) {
      stop("No ", code, " survey in year(s): ", paste(miss, collapse = ", "), call. = FALSE)
    }
    sort(unique(as.integer(y)))
  })
  spec$sample$countries <- sort(cs)
  spec$sample$years <- years[order(names(years))]

  # The baseline survey of the simulation: the latest wave of each economy
  # unless the spec names waves.
  if (!is.null(spec$sim)) {
    waves <- unlist(lapply(spec$sample$countries, function(code) {
      paste0(code, "|", spec$sample$years[[code]])
    }))
    given <- spec$sim$baseline_survey
    if (is.null(given)) {
      spec$sim$baseline_survey <- sort(wise_default_baseline(waves))
    } else if (length(setdiff(given, waves))) {
      stop(
        "sim.baseline_survey names survey wave(s) outside the sample: ",
        paste(setdiff(given, waves), collapse = ", "), call. = FALSE
      )
    }
    spec$sim <- spec$sim[order(names(spec$sim))]
  }

  wvars <- get_weather_vars(metadata$variable_list)
  vars <- wise_spec_weather_vars(spec$weather)
  if (!length(vars)) vars <- wise_default_weather_var(wvars)
  unknown <- setdiff(vars, wvars$name)
  if (length(unknown)) {
    stop("Unknown weather variable(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  w <- list()
  for (v in sort(vars)) {
    units <- as.character(wvars$units[wvars$name == v][1])
    x <- .normalise_wx_var(spec$weather[[v]])
    d <- wise_weather_var_defaults(units)
    x$temporal_agg <- x$temporal_agg %||% d$temporal_agg
    x$transformation <- x$transformation %||% d$transformation
    if (!x$temporal_agg %in% temporal_agg_choices(units)) {
      stop("weather.", v, ".temporal_agg '", x$temporal_agg, "' is not available for ", v, ".", call. = FALSE)
    }
    if (!x$transformation %in% transformation_choices(units)) {
      stop("weather.", v, ".transformation '", x$transformation, "' is not available for ", v, ".", call. = FALSE)
    }
    w[[v]] <- x[order(names(x))]
  }
  w$hist_years <- spec$weather$hist_years
  spec$weather <- w

  if (!is.null(survey_columns)) {
    cols <- if (is.function(survey_columns)) survey_columns(spec) else survey_columns
    outs <- filter_outcome_vars(metadata$variable_list, cols)
    spec$outcome$name <- spec$outcome$name %||% wise_default_outcome(outs$name)
    spec$outcome <- spec$outcome[intersect(c("name", "currency", "poverty_line"), names(spec$outcome))]
    info <- outs[outs$name == spec$outcome$name, , drop = FALSE]
    # An outcome the surveys lack is left for the data stage to report, so
    # that run fails alone and the rest of the grid still runs.
    if (nrow(info) && !is.null(spec$model)) {
      spec$model$type <- spec$model$type %||% wise_default_model_type(info$type[1])
      problems <- .model_resolved_problems(spec$model, info$type[1])
      if (length(problems)) stop(paste(problems, collapse = " "), call. = FALSE)
    }
  }
  spec
}

# Model type against the outcome type, as the Model tab offers them: logistic
# needs a binary outcome, RIF a continuous one.
#' @noRd
.model_resolved_problems <- function(model, outcome_type) {
  binary <- identical(outcome_type, "logical")
  if (identical(model$type, "Logistic regression") && !binary) {
    return("model.type 'Logistic regression' needs a binary outcome.")
  }
  if (identical(model$type, "Unconditional quantile regression (RIF)") && binary) {
    return("model.type 'Unconditional quantile regression (RIF)' needs a continuous outcome.")
  }
  character(0)
}

# Column names of the survey files of a spec's sample (a cheap schema read).
#' @noRd
.read_survey_columns <- function(spec, metadata, connection_params) {
  ss <- wise_select_surveys(
    metadata$survey_list, spec$sample$unit, connection_params, spec$sample$countries, spec$sample$years
  )
  colnames(load_data(ss$fname, connection_params, unify_schemas = TRUE))
}


# Stage hashes ----

# Canonical JSON: named lists sorted by name, numbers at full precision.
#' @noRd
.spec_canonical <- function(x) {
  if (is.list(x) && !is.null(names(x))) x <- x[order(names(x))]
  if (is.list(x)) x <- lapply(x, .spec_canonical)
  x
}

#' @noRd
.spec_json <- function(x, pretty = FALSE) {
  as.character(jsonlite::toJSON(
    .spec_canonical(x),
    auto_unbox = TRUE, digits = NA, null = "null", na = "null", pretty = pretty
  ))
}

#' @noRd
.spec_digest <- function(x) {
  substr(digest::digest(.spec_json(x), algo = "sha256", serialize = FALSE), 1L, 12L)
}

#' Stage ids of a spec
#'
#' Hashes of the spec sections each stage depends on. They key the tables and
#' decide which work is shared between runs: `data_id` (source, sample,
#' outcome, statistics options), `wxvar_id` (the data plus one weather
#' variable's reference period, temporal aggregation and transformation, and
#' the historical years; one per variable), `weather_id` (the data plus the
#' whole weather section, binning included: the survey-weather frame),
#' `fit_id` (data, weather, model and seed; `NA` without a model section),
#' `sim_id` (the fit and the simulation settings that change results; `NA`
#' without a `sim` section) and `run_id` (the whole spec, including the seed).
#'
#' @param spec A resolved spec.
#' @return A list: `data_id`, `wxvar_ids` (named by variable), `weather_id`,
#'   `fit_id`, `sim_id`, `run_id`.
#' @export
wise_spec_ids <- function(spec) {
  data_id <- .spec_digest(spec[c("schema_version", "source", "sample", "outcome", "stats")])
  vars <- wise_spec_weather_vars(spec$weather)
  # The descriptive statistics use the values before binning, so form and
  # binning do not enter: profiles that bin one variable differently share it.
  wx_fields <- c("ref_period", "temporal_agg", "transformation")
  wxvar_ids <- vapply(vars, function(v) {
    x <- spec$weather[[v]]
    .spec_digest(list(
      data_id = data_id, variable = v, spec = x[intersect(wx_fields, names(x))],
      hist_years = spec$weather$hist_years
    ))
  }, character(1))
  # The merged survey-weather frame depends on the whole weather section; the
  # seed only on K-means bin breaks.
  kmeans <- any(vapply(vars, function(v) identical(spec$weather[[v]]$binning_method, "K-means"), logical(1)))
  weather_id <- .spec_digest(list(
    data_id = data_id, weather = spec$weather, seed = if (kmeans) spec$seed
  ))
  fit_id <- if (is.null(spec$model)) {
    NA_character_
  } else {
    .spec_digest(list(data_id = data_id, weather = spec$weather, model = spec$model, seed = spec$seed))
  }
  sim_id <- if (is.null(spec$sim) || is.na(fit_id)) {
    NA_character_
  } else {
    .spec_digest(list(fit_id = fit_id, sim = .sim_effective(spec)))
  }
  list(
    data_id = data_id, wxvar_ids = wxvar_ids, weather_id = weather_id, fit_id = fit_id,
    sim_id = sim_id, run_id = .spec_digest(spec)
  )
}


# Serialisation ----

#' Write a spec as JSON
#' @param spec A spec.
#' @param file Output path.
#' @export
wise_spec_write <- function(spec, file) {
  writeLines(.spec_json(spec, pretty = TRUE), file)
  invisible(file)
}

#' Read a spec written by `wise_spec_write()`
#' @param file Path to a spec JSON file.
#' @return A spec.
#' @export
wise_spec_read <- function(file) {
  x <- jsonlite::fromJSON(file, simplifyVector = TRUE, simplifyDataFrame = FALSE, simplifyMatrix = FALSE)
  wise_spec(x)
}


# App configuration import ----

# Input ids of the Step 1 data controls in an app configuration export
# (`<step>-<module>-<input>`).
.CONFIG_PREFIX <- c(
  sample = "step1-sample-", outcome = "step1-outcome-", weather = "step1-weather-",
  model = "step1-model-", sim = "step2-weathersim-"
)

#' Translate an app configuration export into a run spec
#'
#' Reads the Step 1 sample, outcome, weather and model inputs of a
#' configuration written by the app's Export (`wise_config_snapshot()`); the
#' seed comes from `random_seed`. Interactions and policy scenarios of the
#' Model tab are not read (a warning says so); settings of later steps are
#' ignored here.
#'
#' @param config A parsed configuration (`jsonlite::fromJSON()`), or the path
#'   of a configuration JSON file.
#' @return A spec.
#' @export
wise_spec_from_config <- function(config) {
  if (is.character(config) && length(config) == 1L) {
    config <- jsonlite::fromJSON(config, simplifyVector = TRUE, simplifyDataFrame = FALSE)
  }
  verdict <- .import_validate(config, app_version = NA_character_)
  if (!verdict$ok) stop(verdict$text, call. = FALSE)
  inp <- config$inputs
  get <- function(id) inp[[id]]
  p <- .CONFIG_PREFIX

  sample <- list(unit = get(paste0(p[["sample"]], "unit")))
  economy <- get(paste0(p[["sample"]], "economy"))
  if (length(economy)) {
    sample$countries <- as.character(unlist(economy))
    sample$years <- Filter(Negate(is.null), stats::setNames(lapply(sample$countries, function(code) {
      get(paste0(p[["sample"]], "year_", code))
    }), sample$countries))
  }
  outcome <- list(
    name = get(paste0(p[["outcome"]], "outcome")),
    currency = get(paste0(p[["outcome"]], "currency")),
    poverty_line = get(paste0(p[["outcome"]], "poverty_line"))
  )
  weather <- list()
  vars <- get(paste0(p[["weather"]], "weather_variable_selector"))
  for (v in as.character(unlist(vars))) {
    x <- list()
    for (field in names(.WX_INPUT_KEYS)) {
      val <- get(paste0(p[["weather"]], v, "_", .WX_INPUT_KEYS[[field]]))
      if (!is.null(val)) x[[field]] <- val
    }
    weather[[v]] <- x
  }
  hy <- get(paste0(p[["weather"]], "hist_years"))
  if (!is.null(hy)) weather$hist_years <- hy
  if (!length(wise_spec_weather_vars(weather)) && is.null(hy)) weather <- NULL

  model <- NULL
  model_type <- get(paste0(p[["model"]], "model_type"))
  if (!is.null(model_type)) {
    m <- function(id) get(paste0(p[["model"]], id))
    roles <- c("hh", "ind", "firm", "area")
    flat <- function(prefix) as.character(unlist(lapply(roles, function(r) m(paste0(prefix, r)))))
    ignored <- c(
      if (length(m("interactions"))) "interactions",
      if (length(m("selected_policies"))) "policy scenario"
    )
    if (length(ignored)) {
      warning(
        "The configuration sets ", paste(ignored, collapse = " and "),
        "; the batch model section does not support ", if (length(ignored) > 1L) "them" else "it",
        " yet, so the model is read without.", call. = FALSE
      )
    }
    lasso <- Filter(Negate(is.null), list(
      alpha = m("lasso_alpha"), lambda = m("lasso_interactions"), nfolds = m("lasso_nfolds"),
      standardize = if (!is.null(m("lasso_standardize"))) m("lasso_standardize") == "Standardize",
      use_mice = m("use_mice"), mi_m = m("mi_m"), mi_maxit = m("mi_maxit"),
      stability_threshold = m("stability_threshold"),
      force_in = flat("force_in_"), force_out = flat("force_out_")
    ))
    model <- Filter(Negate(is.null), list(
      type = model_type,
      fixed_effects = if (!is.null(m("fixedeffects"))) as.character(unlist(m("fixedeffects"))),
      covariates = list(
        method = m("covariates"),
        vars = as.character(unlist(lapply(c("hhcov", "indcov", "firmcov", "areacov"), m))),
        lasso = lasso
      )
    ))
  }

  # Step 2 sidebar. A projection period the app leaves out (incomplete, empty
  # or before the climate projections) is left out here as well.
  sim <- NULL
  s2 <- function(id) get(paste0(p[["sim"]], id))
  period_inputs <- lapply(1:3, function(i) s2(paste0("fut_period_", i)))
  sim_settings <- Filter(Negate(is.null), list(
    hist_years = s2("hist_years"), ssps = s2("climate"), residuals = s2("residuals"),
    coef_uncertainty = s2("include_coef_uncertainty"),
    propagate_all_covariate_uncertainty = s2("propagate_all_covariate_uncertainty"),
    baseline_survey = s2("baseline_survey"),
    future_periods = if (!all(vapply(period_inputs, is.null, logical(1)))) {
      Filter(Negate(is.null), lapply(period_inputs, .step2_valid_future_period))
    }
  ))
  if (length(sim_settings)) {
    if (is.null(model)) {
      warning(
        "The configuration sets the simulation, which needs a Step 1 model; ",
        "no model is set, so the simulation is read without.", call. = FALSE
      )
    } else {
      sim <- sim_settings
    }
  }

  args <- list(
    sample = sample, outcome = outcome, weather = weather, model = model, sim = sim,
    seed = config$random_seed
  )
  do.call(wise_spec, Filter(Negate(is.null), args))
}


# Grid authoring ----

# Axis aliases: axis name -> spec path.
.AXIS_PATHS <- list(
  country = c("sample", "countries"), countries = c("sample", "countries"),
  unit = c("sample", "unit"), seed = "seed",
  hist_years = c("weather", "hist_years"),
  currency = c("outcome", "currency"), poverty_line = c("outcome", "poverty_line"),
  outcome = c("outcome", "name")
)

# Spec sections that later phases will add; named in errors.
.FUTURE_SECTIONS <- "policy"

# Profile groups that set a part of a section rather than the section itself.
.PROFILE_PATHS <- list(
  covariates = c("model", "covariates"), fixed_effects = c("model", "fixed_effects")
)

#' @noRd
.get_path <- function(x, path) {
  for (p in path) x <- x[[p]]
  x
}

#' @noRd
.set_path <- function(x, path, value) {
  if (length(path) == 1L) {
    x[[path]] <- value
  } else {
    x[[path[1L]]] <- .set_path(x[[path[1L]]] %||% list(), path[-1L], value)
  }
  x
}

# Apply one axis value to a spec (a list of raw sections, not yet normalised).
#' @noRd
.apply_axis <- function(spec, axis, value, profiles) {
  if (axis %in% .FUTURE_SECTIONS) {
    stop(
      "Axis '", axis, "' belongs to a later phase; this version covers ",
      paste(WISEAPP_SPEC_SECTIONS, collapse = ", "), " and seed.", call. = FALSE
    )
  }
  prof <- profiles[[axis]]
  if (!is.null(prof) && is.character(value) && length(value) == 1L) {
    if (!value %in% names(prof)) {
      stop("Axis '", axis, "': no profile '", value, "' in profiles.", axis, ".", call. = FALSE)
    }
    # A weather profile replaces the variable set; other sections merge. A
    # fixed-effects profile is a list of variable names and replaces the set.
    if (identical(axis, "weather")) {
      spec$weather <- spec$weather[intersect(names(spec$weather), "hist_years")]
    }
    path <- .PROFILE_PATHS[[axis]] %||% axis
    new <- if (identical(axis, "fixed_effects")) {
      as.character(unlist(prof[[value]]))
    } else if (identical(axis, "sim")) {
      .merge_sim(.get_path(spec, path), prof[[value]])
    } else {
      .spec_merge(.get_path(spec, path) %||% list(), prof[[value]])
    }
    return(.set_path(spec, path, new))
  }
  path <- .AXIS_PATHS[[axis]]
  if (is.null(path) && grepl(".", axis, fixed = TRUE)) path <- strsplit(axis, ".", fixed = TRUE)[[1L]]
  if (is.null(path)) {
    stop(
      "Unknown axis '", axis, "'. Use a profile group name, one of ",
      paste(names(.AXIS_PATHS), collapse = ", "), ", or a dotted spec path.", call. = FALSE
    )
  }
  spec <- .set_path(spec, path, value)
  # Years are keyed by economy; drop the ones of economies no longer selected.
  if (identical(path, c("sample", "countries")) && length(spec$sample$years)) {
    spec$sample$years <- spec$sample$years[names(spec$sample$years) %in% unlist(value)]
  }
  spec
}

#' @noRd
.axis_label <- function(value) paste(as.character(unlist(value)), collapse = "+")

#' Expand a run grid into leaf run specs
#'
#' A grid is a YAML file (or the equivalent list) with optional `base`
#' (an app configuration JSON), top-level spec sections and `seed`,
#' `profiles` (named partial settings per section), `axes` (what varies),
#' `zip` (axes that vary together) and `exclude` (combinations to drop).
#' Axes are crossed unless zipped.
#'
#' @param grid Path to a grid YAML file, or a parsed list.
#' @param connection_params Connection used to resolve data-dependent
#'   defaults (`NULL` builds a local connection from `WISEAPP_DATA_PATH` when
#'   that is set). Without a connection the specs stay unresolved and their
#'   ids differ from those of a run.
#' @param metadata Output of `load_overview_metadata()` (loaded from
#'   `connection_params` when `NULL`).
#' @param survey_columns Survey column names (a vector, or a function of the
#'   spec) used to resolve the default outcome and model type; `NULL` reads
#'   them from the survey files.
#' @return A data frame, one row per run: `run_id`, one column per axis with
#'   the profile label, `data_id`, `wxvar_ids` (list), `weather_id`, `fit_id`
#'   (`NA` without a model section), `resolved`, `spec` (list of specs).
#' @export
wise_spec_expand <- function(grid, connection_params = NULL, metadata = NULL,
                             survey_columns = NULL) {
  if (is.character(grid)) {
    .need_pkg("yaml", "read a grid file")
    grid_dir <- dirname(normalizePath(grid, mustWork = TRUE))
    grid <- yaml::read_yaml(grid)
  } else {
    grid_dir <- getwd()
  }
  unknown <- setdiff(
    names(grid), c("base", "seed", WISEAPP_SPEC_SECTIONS, "profiles", "axes", "zip", "exclude")
  )
  future <- intersect(unknown, .FUTURE_SECTIONS)
  if (length(future)) {
    stop(
      "Grid section(s) '", paste(future, collapse = "', '"), "' belong to a later phase.",
      call. = FALSE
    )
  }
  if (length(unknown)) stop("Unknown grid key(s): ", paste(unknown, collapse = ", "), call. = FALSE)

  base <- list()
  if (!is.null(grid$base)) {
    path <- if (file.exists(grid$base)) grid$base else file.path(grid_dir, grid$base)
    base <- wise_spec_from_config(path)
    base$schema_version <- NULL
  }
  top <- grid[intersect(c("seed", WISEAPP_SPEC_SECTIONS), names(grid))]
  base <- .spec_merge(base, top[setdiff(names(top), "sim")])
  if (!is.null(top$sim)) base$sim <- .merge_sim(base$sim, top$sim)

  axes <- grid$axes %||% list()
  profiles <- grid$profiles %||% list()
  axis_names <- names(axes)
  if (length(axes) && is.null(axis_names)) stop("axes must be a named list.", call. = FALSE)
  values <- lapply(axes, function(a) if (is.list(a)) a else as.list(a))

  # Index combinations: zipped axes share one index.
  zips <- lapply(grid$zip %||% list(), as.character)
  zipped <- unlist(zips)
  bad_zip <- setdiff(zipped, axis_names)
  if (length(bad_zip)) stop("zip names unknown axes: ", paste(bad_zip, collapse = ", "), call. = FALSE)
  units <- c(zips, as.list(setdiff(axis_names, zipped)))
  sizes <- lapply(units, function(u) {
    n <- unique(vapply(values[u], length, integer(1)))
    if (length(n) > 1L) stop("Zipped axes must have equal lengths: ", paste(u, collapse = ", "), call. = FALSE)
    n
  })
  idx <- if (length(units)) {
    do.call(expand.grid, c(lapply(sizes, seq_len), list(KEEP.OUT.ATTRS = FALSE)))
  } else {
    data.frame(row = 1L)
  }

  rows <- lapply(seq_len(nrow(idx)), function(i) {
    spec <- base
    labels <- list()
    for (k in seq_along(units)) {
      for (ax in units[[k]]) {
        val <- values[[ax]][[idx[i, k]]]
        spec <- .apply_axis(spec, ax, val, profiles)
        labels[[ax]] <- .axis_label(val)
      }
    }
    list(spec = spec, labels = labels)
  })

  # Exclusions on the axis labels.
  keep <- vapply(rows, function(r) {
    !any(vapply(grid$exclude %||% list(), function(rule) {
      unknown_ax <- setdiff(names(rule), axis_names)
      if (length(unknown_ax)) stop("exclude names unknown axes: ", paste(unknown_ax, collapse = ", "), call. = FALSE)
      all(vapply(names(rule), function(ax) {
        r$labels[[ax]] %in% vapply(as.list(rule[[ax]]), .axis_label, character(1))
      }, logical(1)))
    }, logical(1)))
  }, logical(1))
  rows <- rows[keep]
  if (!length(rows)) stop("Every combination of the grid is excluded.", call. = FALSE)

  specs <- lapply(rows, function(r) do.call(wise_spec, r$spec))

  cp <- connection_params
  if (is.null(cp) && nzchar(Sys.getenv("WISEAPP_DATA_PATH"))) cp <- wise_batch_connection(specs[[1]]$source)
  resolved <- !is.null(cp)
  if (resolved) {
    if (is.null(metadata)) metadata <- load_overview_metadata(cp)
    # Survey columns decide the default outcome and model type; read once per
    # sample.
    cache <- new.env(parent = emptyenv())
    cols <- function(spec) {
      if (is.function(survey_columns)) {
        return(survey_columns(spec))
      }
      if (!is.null(survey_columns)) {
        return(survey_columns)
      }
      key <- .spec_digest(spec[c("sample", "source")])
      cache[[key]] <- cache[[key]] %||% .read_survey_columns(spec, metadata, cp)
      cache[[key]]
    }
    specs <- lapply(specs, wise_spec_resolve,
      metadata = metadata, connection_params = cp, survey_columns = cols
    )
  }

  ids <- lapply(specs, wise_spec_ids)
  out <- data.frame(run_id = vapply(ids, `[[`, "", "run_id"), stringsAsFactors = FALSE)
  for (ax in axis_names) out[[ax]] <- vapply(rows, function(r) r$labels[[ax]], "")
  out$data_id <- vapply(ids, `[[`, "", "data_id")
  out$wxvar_ids <- lapply(ids, `[[`, "wxvar_ids")
  out$weather_id <- vapply(ids, `[[`, "", "weather_id")
  out$fit_id <- vapply(ids, `[[`, "", "fit_id")
  out$sim_id <- vapply(ids, `[[`, "", "sim_id")
  out$resolved <- resolved
  out$spec <- specs
  dup <- duplicated(out$run_id)
  if (any(dup)) {
    warning(sum(dup), " grid row(s) give a spec that another row already gives and were dropped.", call. = FALSE)
    out <- out[!dup, , drop = FALSE]
  }
  rownames(out) <- NULL
  tibble::as_tibble(out)
}

#' Connection parameters for a spec's source
#'
#' Credentials and the data location come from the environment variables the
#' app uses (for local data, `WISEAPP_DATA_PATH`); the spec holds only the
#' source type.
#'
#' @param source The spec `source` section.
#' @return A connection parameter list.
#' @export
wise_batch_connection <- function(source = list(type = "local")) {
  build_connection_params(source$type %||% "local")
}

# Suggested packages ----

#' @noRd
.need_pkg <- function(pkg, what) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Package '", pkg, "' is needed to ", what, ". Install it with install.packages(\"", pkg, "\").", call. = FALSE)
  }
  invisible(TRUE)
}

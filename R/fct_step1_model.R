# Step 1 model glue ----
# Shiny-free functions that turn the settings of the Model tab into the
# arguments of `run_lasso_selection()` and `fit_model()`, and run them. The
# module servers (mod_1_06, mod_1_07) call these, and so does the batch
# pipeline, so a batch fit and an app fit are built from the same objects
# with the same seed.


# Variables and covariates ----

#' Variables the model can use: present and at least 90 % complete
#'
#' The valid variable list of the Model tab. Completeness is checked within
#' every survey wave, on the rows with a non-missing outcome.
#'
#' @param survey_weather Survey-weather frame.
#' @param variable_list Variable metadata.
#' @param outcome_name Outcome column name.
#' @return The filtered variable list.
#' @noRd
wise_valid_vars <- function(survey_weather, variable_list, outcome_name) {
  filter_valid_vars(survey_weather, variable_list,
    min_complete = 0.9,
    group_cols = c("code", "year", "survname"),
    outcome = outcome_name,
    row_rules = WISE_LABOR_ROW_RULES
  )
}

# Labour variables are defined for part of the sample only: employment and
# unemployment for people of working age (15+), and self-employment and the
# sector of the main job for the employed. Their completeness is judged on
# those rows (`filter_valid_vars(row_rules =)`).
#' @noRd
WISE_LABOR_ROW_RULES <- local({
  working_age <- function(d) d$age >= 15
  employed <- function(d) d$employed == 1
  list(
    employed = working_age, unemployed = working_age,
    selfemployed = employed, agriculture = employed,
    industry = employed, services = employed
  )
})

#' Lasso settings with the Model tab's defaults for omitted fields
#'
#' @param alpha,lambda,nfolds,standardize,use_mice,mi_m,mi_maxit,stability_threshold
#'   Control values (`NULL` = default). `standardize` is a logical or the
#'   control's label (`"Standardize"`, `"Do not standardize"`).
#' @return A named list (see `wise_default_lasso()`).
#' @noRd
wise_lasso_settings <- function(alpha = NULL, lambda = NULL, nfolds = NULL,
                                standardize = NULL, use_mice = NULL, mi_m = NULL,
                                mi_maxit = NULL, stability_threshold = NULL) {
  d <- wise_default_lasso()
  list(
    alpha = alpha %||% d$alpha,
    lambda = lambda %||% d$lambda,
    nfolds = nfolds %||% d$nfolds,
    standardize = if (is.null(standardize)) {
      d$standardize
    } else if (is.logical(standardize)) {
      standardize
    } else {
      standardize == "Standardize"
    },
    use_mice = use_mice %||% d$use_mice,
    mi_m = mi_m %||% d$mi_m,
    mi_maxit = mi_maxit %||% d$mi_maxit,
    stability_threshold = stability_threshold %||% d$stability_threshold
  )
}

#' Candidate variable list of the Lasso: forced exclusions removed
#'
#' @param valid_vl Valid variable list (`wise_valid_vars()`).
#' @param force_out Variables to keep out of the candidate pool.
#' @return The variable list without `force_out`.
#' @noRd
wise_lasso_candidates <- function(valid_vl, force_out = character(0)) {
  if (length(force_out) > 0 && !is.null(valid_vl)) {
    valid_vl <- valid_vl[!valid_vl$name %in% force_out, , drop = FALSE]
  }
  valid_vl
}

#' Stability Lasso covariate selection from the Model tab settings
#'
#' @param df Survey-weather frame with the outcome on the model scale
#'   (`prepare_outcome_df()`).
#' @param selected_outcome One-row outcome table.
#' @param weather_vars,fe_vars,int_vars Weather variables, fixed effects and
#'   interaction moderators (kept unpenalised).
#' @param valid_vl Candidate variable list (`wise_lasso_candidates()`).
#' @param model_type Model type label.
#' @param settings Lasso settings (`wise_lasso_settings()`).
#' @param seed Seed of the run.
#' @return A list: `selected_covariates`, `selection_frequency`.
#' @noRd
wise_lasso_selection <- function(df, selected_outcome, weather_vars, fe_vars, int_vars,
                                 valid_vl, model_type, settings, seed) {
  run_lasso_selection(
    df = df,
    selected_outcome = selected_outcome,
    weather_vars = weather_vars,
    fe_vars = fe_vars,
    int_vars = int_vars,
    valid_vl = valid_vl,
    model_type = model_type,
    alpha = settings$alpha,
    lambda_choice = settings$lambda,
    nfolds = settings$nfolds,
    standardize = settings$standardize,
    mi_m = settings$mi_m,
    mi_maxit = settings$mi_maxit,
    mi_method = "norm",
    use_mice = settings$use_mice,
    stability_threshold = settings$stability_threshold,
    parallel_seed = seed,
    cv_selection = "random",
    glmnet_tol = 1e-4,
    cv_cluster = wise_cluster_var(names(df))
  )
}

#' Covariates by level from a Lasso selection
#'
#' A selected variable joins the level whose role flag it carries; forced-in
#' variables are added and forced-out ones removed, per level.
#'
#' @param selected Selected covariate names.
#' @param valid_vl Valid variable list.
#' @param forced Per level (`ind`, `hh`, `firm`, `area`): `list(inc =, exc =)`.
#' @return A list of character vectors: `hh`, `area`, `ind`, `firm`.
#' @noRd
wise_lasso_covariates <- function(selected, valid_vl, forced) {
  resolve <- function(role) {
    base <- valid_vl$name[valid_vl[[role]] %in% 1 & valid_vl$name %in% selected]
    setdiff(unique(c(base, forced[[role]]$inc)), forced[[role]]$exc)
  }
  list(hh = resolve("hh"), area = resolve("area"), ind = resolve("ind"), firm = resolve("firm"))
}


# Model specification ----

#' Cluster variable of the Step 1 models
#'
#' The survey-location panel (`COEF_VCOV_SPEC`), when the H3 files were joined;
#' otherwise none, and fixest's default VCV applies.
#'
#' @param columns Column names of the survey-weather frame.
#' @return `"loc_id_panel"` or `NULL`.
#' @noRd
wise_cluster_var <- function(columns) if ("loc_id_panel" %in% columns) "loc_id_panel" else NULL

#' Model specification from the Model tab settings
#'
#' @param model_type Model type label.
#' @param interactions Interaction moderators.
#' @param fixed_effects Fixed effects.
#' @param covariate_selection `"User-defined"` or `"Lasso"`.
#' @param covariates List of covariates by level (`hh`, `area`, `ind`, `firm`).
#' @param lasso List of Lasso control values as the controls hold them
#'   (`alpha`, `lambda`, `nfolds`, `standardize`, `mi_m`, `mi_maxit`,
#'   `stability_threshold`; `NULL` entries take the defaults).
#' @param cluster Cluster variable (`wise_cluster_var()`).
#' @return A `build_selected_model()` list.
#' @noRd
wise_selected_model <- function(model_type, interactions, fixed_effects, covariate_selection,
                                covariates, lasso = list(), cluster = NULL) {
  build_selected_model(
    model_type          = model_type,
    interactions        = interactions,
    fixedeffects        = fixed_effects,
    covariate_selection = covariate_selection,
    hh_covariates       = covariates$hh,
    area_covariates     = covariates$area,
    ind_covariates      = covariates$ind,
    firm_covariates     = covariates$firm,
    lasso_alpha         = lasso$alpha,
    lasso_lambda        = lasso$lambda,
    lasso_nfolds        = lasso$nfolds,
    lasso_standardize   = lasso$standardize,
    mi_m                = lasso$mi_m,
    mi_maxit            = lasso$mi_maxit,
    stability_threshold = lasso$stability_threshold,
    cluster             = cluster
  )
}


#' Model specification from a run spec's model section (batch)
#'
#' Does what the Model tab does between the controls and "Run model": checks
#' the choices against the variables the data offers, runs the Lasso when the
#' covariates come from it, and assembles the specification. The interactions
#' are the moderators of the spec plus the variables the policy scenario
#' (`policy_vars`) locks; no interaction is the default.
#'
#' @param model The spec `model` section, resolved (`type` set).
#' @param unit Unit of analysis (`"hh"`, `"ind"`, `"firm"`).
#' @param survey_weather Survey-weather frame (with `loc_id_panel` when the
#'   location panel was joined).
#' @param selected_outcome One-row outcome table.
#' @param selected_weather Selected weather table.
#' @param variable_list Variable metadata.
#' @param seed Seed of the run.
#' @return A list: `selected_model` and `selection_frequency` (Lasso only).
#' @noRd
wise_model_from_spec <- function(model, unit, survey_weather, selected_outcome, selected_weather,
                                 variable_list, seed) {
  sw <- as.data.frame(survey_weather)
  vl <- wise_valid_vars(sw, variable_list, selected_outcome$name)
  outcome <- as.character(selected_outcome$name)
  weather_vars <- as.character(selected_weather$name)
  roles <- c("hh", "area", "ind", "firm")
  shown <- function(role) identical(role, "area") || identical(unit, role)
  unavailable <- function(what, bad) {
    stop(what, " not available in the data: ", paste(bad, collapse = ", "), ".", call. = FALSE)
  }

  fe_valid <- filter_vars_by_role(vl, "fe")$name
  fe <- model$fixed_effects %||% wise_default_fixed_effects(fe_valid)
  if (length(setdiff(fe, fe_valid))) unavailable("Fixed effect(s)", setdiff(fe, fe_valid))

  # Moderators of the weather effect: those chosen, and those a policy scenario
  # locks (the Model tab adds them to the selection).
  # Outcome-flagged variables qualify, except the outcome of this run.
  ixn_valid <- setdiff(
    filter_vars_by_role(vl, "interact", extra_filter = list(type = "numeric"))$name,
    outcome
  )
  locked <- unique(unlist(get_policy_locked_vars(model$policy_vars, vl), use.names = FALSE))
  defs <- policy_definitions(vl)
  no_policy_var <- vapply(model$policy_vars, function(k) {
    !any(defs[[k]]$vars %in% vl$name)
  }, logical(1))
  if (any(no_policy_var)) {
    unavailable("Policy scenario variable(s) of", names(no_policy_var)[no_policy_var])
  }
  if (length(setdiff(model$interactions, c(ixn_valid, locked)))) {
    unavailable("Interaction variable(s)", setdiff(model$interactions, c(ixn_valid, locked)))
  }
  interactions <- unique(c(model$interactions, locked))

  cv <- model$covariates
  lasso <- list()
  selection <- NULL
  if (identical(cv$method, "lasso")) {
    l <- cv$lasso
    settings <- wise_lasso_settings(
      l$alpha, l$lambda, l$nfolds, l$standardize, l$use_mice, l$mi_m, l$mi_maxit,
      l$stability_threshold
    )
    # The variables the force-in / force-out controls offer at each level.
    offered <- function(role) {
      if (!shown(role) || !role %in% names(vl)) {
        return(character(0))
      }
      x <- vl[vl[[role]] %in% 1, , drop = FALSE]
      keep <- !x$name %in% c(outcome, weather_vars)
      if ("outcome" %in% names(x)) keep <- keep & (is.na(x$outcome) | x$outcome != 1L)
      x$name[keep]
    }
    bad <- setdiff(c(l$force_in, l$force_out), unlist(lapply(roles, offered)))
    if (length(bad)) unavailable("Forced covariate(s)", bad)
    forced <- stats::setNames(lapply(c("ind", "hh", "firm", "area"), function(r) {
      list(inc = intersect(l$force_in, offered(r)), exc = intersect(l$force_out, offered(r)))
    }), c("ind", "hh", "firm", "area"))
    selection <- wise_lasso_selection(
      prepare_outcome_df(sw, selected_outcome), selected_outcome, weather_vars, fe, interactions,
      wise_lasso_candidates(vl, unique(c(l$force_out))), model$type, settings, seed
    )
    covs <- wise_lasso_covariates(selection$selected_covariates, vl, forced)
    lasso <- settings
    lasso$use_mice <- NULL
    method <- "Lasso"
  } else {
    pool <- function(role) {
      if (!shown(role)) {
        return(character(0))
      }
      exclude_selected_vars(
        filter_vars_by_role(vl, role),
        outcome_name = outcome, weather_names = weather_vars,
        interactions = interactions, fixedeffects = fe
      )$name
    }
    bad <- setdiff(cv$vars, unlist(lapply(roles, pool)))
    if (length(bad)) unavailable("Covariate(s)", bad)
    covs <- stats::setNames(lapply(roles, function(r) intersect(cv$vars, pool(r))), roles)
    method <- "User-defined"
  }
  list(
    selected_model = wise_selected_model(
      model$type, interactions, fe, method, covs, lasso, wise_cluster_var(colnames(sw))
    ),
    selection_frequency = selection$selection_frequency
  )
}


# Fit ----

#' Fit the three progressive Step 1 models
#'
#' Relabels the bin levels with the observed outer breaks, puts the outcome on
#' the model scale and calls `fit_model()`. The result carries the fit-time
#' snapshot (`.snap`) every renderer and table builder reads, so labels and
#' settings describe the fitted run.
#'
#' @param survey_weather Survey-weather frame.
#' @param stored_breaks Bin breaks stored at weather load (or `NULL`).
#' @param selected_outcome One-row outcome table.
#' @param selected_weather Selected weather table.
#' @param selected_model Model specification (`wise_selected_model()`).
#' @param variable_list Variable metadata.
#' @param seed Seed of the run.
#' @return The `fit_model()` list with `.snap`.
#' @noRd
wise_fit <- function(survey_weather, stored_breaks, selected_outcome, selected_weather,
                     selected_model, variable_list, seed) {
  # Bin-edge labels: cut() levels carry the +/-Inf sentinel edges used for
  # bucketing; substitute the observed outer breaks stored at weather load so
  # every downstream label reads "(36.3, 40.1]", not "(36.3, Inf]". Applied to
  # the fitted frame AND the snapshot, so cards, figures and tables all show
  # observed ranges.
  svw <- relabel_bin_levels(as.data.frame(survey_weather), stored_breaks)
  df <- prepare_outcome_df(svw, selected_outcome)

  fit_args <- list(
    df               = df,
    selected_outcome = selected_outcome,
    selected_weather = selected_weather,
    selected_model   = selected_model
  )
  if ("seed" %in% names(formals(fit_model))) {
    fit_args$seed <- seed
  }
  fit_list <- do.call(fit_model, fit_args)
  # INT-05: snapshot every label/setting the renderers need at fit time.
  fit_list$.snap <- list(
    outcome        = selected_outcome,
    weather        = selected_weather,
    survey_weather = svw,
    variable_list  = variable_list,
    model          = selected_model
  )
  # The seed the fit used, kept with the result for run provenance.
  fit_list$.seed <- as.integer(seed)
  fit_list
}

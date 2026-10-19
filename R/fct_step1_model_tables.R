# Step 1 model tables ----
# Shiny-free builders for the three model tables of the batch pipeline
# (`model_terms`, `model_fit`, `model_vcov`; reference in
# batch/docs/phase2_tables.md) and for the translated effects that the Results
# tab and the tables share. The Results module (mod_1_07) calls
# `step1_translations()` and `step1_focused_df()`; batch calls the same two and
# adds the table builders. Values are raw (never rounded).


# Translated effects ----

#' Translated effects of a fit: scenarios and headline cards
#'
#' The chain the Results tab builds once per fit: effect scenarios per weather
#' variable, the tail and heterogeneity inputs of RIF fits, and the
#' "At a glance" cards with their tidy table. Every value comes from the fit-time
#' snapshot.
#'
#' @param mf A `wise_fit()` / `fit_model()` list with `.snap`.
#' @param label_fun Function mapping variable names to labels (default: the
#'   snapshot's variable list).
#' @return A list: `scenarios` (named by weather variable), `rif_scenarios`,
#'   `rif_heterogeneity` (both `NULL` unless RIF), `headline` (the cards,
#'   `step1_headline_cards()`), `headline_table`.
#' @noRd
step1_translations <- function(mf, label_fun = .label_lookup(mf$.snap$variable_list)) {
  snap <- mf$.snap
  vars <- mf$weather_terms
  by_var <- function(fun) {
    stats::setNames(lapply(vars, function(v) tryCatch(fun(v), error = function(e) NULL)), vars)
  }
  is_rif <- identical(mf$engine, "rif")
  scenarios <- by_var(function(v) step1_scenarios(mf, snap, v))
  rif_scenarios <- if (is_rif) by_var(function(v) .s1_rif_scenarios(mf, snap, v, taus = c(0.1, 0.9)))
  rif_heterogeneity <- if (is_rif) by_var(function(v) step1_rif_heterogeneity_p(mf, snap, v))
  headline <- tryCatch(
    step1_headline_cards(
      mf, snap,
      label_fun = label_fun,
      scenarios_list = scenarios,
      rif_scenarios = rif_scenarios,
      rif_heterogeneity = rif_heterogeneity
    ),
    error = function(e) NULL
  )
  list(
    scenarios = scenarios, rif_scenarios = rif_scenarios,
    rif_heterogeneity = rif_heterogeneity, headline = headline,
    headline_table = tryCatch(step1_headline_table(result = headline), error = function(e) NULL)
  )
}

#' Focused weather estimates of the full specification
#'
#' The tidy data frame behind the Results tab's focused table: weather and
#' interaction terms of specification (3) with the model-scale estimate, 95 %
#' CI, p-value and the translated per-+1-SD effect.
#'
#' @param mf A `wise_fit()` list with `.snap`.
#' @param translations Result of `step1_translations()`.
#' @param label_fun Function mapping variable names to labels.
#' @return A data frame (`make_regtable_focused_df()`), or `NULL`.
#' @noRd
step1_focused_df <- function(mf, translations = step1_translations(mf),
                             label_fun = .label_lookup(mf$.snap$variable_list)) {
  outcome <- mf$.snap$outcome
  is_logit <- is_logistic_fit(mf)
  sd_x <- stats::setNames(vapply(mf$weather_terms, function(v) {
    x <- suppressWarnings(as.numeric(mf$train_data[[v]]))
    x <- x[is.finite(x)]
    if (length(x) > 10) stats::sd(x) else NA_real_
  }, numeric(1)), mf$weather_terms)
  tryCatch(
    make_regtable_focused_df(
      fit3 = extract_native_fit(mf$fit3, mf$engine),
      weather_terms = mf$weather_terms,
      interaction_terms = mf$interaction_terms,
      label_fun = label_fun,
      engine = mf$engine,
      is_logistic = is_logit,
      is_lpm = !is_logit && identical(tolower(as.character(outcome$type[1])), "logical"),
      is_log_outcome = identical(as.character(outcome$transform[1]), "log"),
      rif_grid = mf$rif_grid,
      mf = mf,
      scenarios_list = translations$scenarios,
      sd_x = sd_x[is.finite(sd_x)]
    ),
    error = function(e) NULL
  )
}


# model_terms ----

# Coefficients of the three specifications, one row per (model, term[, tau]).
#' @noRd
.model_coef_rows <- function(mf) {
  if (identical(mf$engine, "rif") && !is.null(mf$rif_grid) && nrow(mf$rif_grid)) {
    g <- mf$rif_grid
    n_obs <- vapply(seq_len(nrow(g)), function(i) {
      fit <- mf[[paste0("fit", g$model[i])]]
      sub <- tryCatch(fit[[match(g$tau[i], mf$taus)]], error = function(e) NULL)
      if (is.null(sub)) NA_real_ else as.numeric(stats::nobs(sub))
    }, numeric(1))
    out <- data.frame(
      model = as.integer(g$model), term = as.character(g$term), tau = as.numeric(g$tau),
      estimate = g$estimate, std_error = g$std.error, statistic = g$statistic,
      p_value = g$p.value, conf_low = g$conf.low, conf_high = g$conf.high,
      n_obs = n_obs, stringsAsFactors = FALSE
    )
    return(out[order(out$model, out$tau), , drop = FALSE])
  }
  rows <- lapply(1:3, function(m) {
    fit <- mf[[paste0("fit", m)]]
    if (!inherits(fit, "fixest")) {
      return(NULL)
    }
    ct <- tryCatch(.fixest_coeftable(fit), error = function(e) NULL)
    if (is.null(ct) || !nrow(ct)) {
      return(NULL)
    }
    est <- unname(ct[, 1])
    se <- unname(ct[, 2])
    data.frame(
      model = m, term = rownames(ct), tau = NA_real_, estimate = est, std_error = se,
      statistic = unname(ct[, 3]), p_value = unname(ct[, 4]),
      conf_low = est - 1.96 * se, conf_high = est + 1.96 * se,
      n_obs = as.numeric(tryCatch(stats::nobs(fit), error = function(e) NA_real_)),
      stringsAsFactors = FALSE, row.names = NULL
    )
  })
  do.call(rbind, rows)
}

#' Coefficient table of a fit
#'
#' One row per specification (`model` 1 = weather only, 2 = + fixed effects,
#' 3 = + fixed effects and controls), term and, for RIF, quantile `tau`.
#' `importance_share` (specification 3; the median quantile for RIF) and
#' `translation` (weather terms of specification 3) come from the app's
#' importance plot and focused table; `lasso_freq` is the selection frequency
#' of a Lasso covariate.
#'
#' @param mf A `wise_fit()` list with `.snap`.
#' @param translations Result of `step1_translations()`.
#' @param selection_frequency Named numeric vector of Lasso selection
#'   frequencies (`NULL` unless the covariates came from the Lasso).
#' @return A data frame (columns in `batch/docs/phase2_tables.md`), or `NULL`.
#' @noRd
model_terms_table <- function(mf, translations = step1_translations(mf),
                              selection_frequency = NULL) {
  out <- .model_coef_rows(mf)
  if (is.null(out) || !nrow(out)) {
    return(NULL)
  }
  out$is_weather <- out$term %in% unlist(lapply(1:3, function(m) {
    tryCatch(weather_coef_names(extract_rif_median(mf[[paste0("fit", m)]], mf$engine), mf$weather_terms),
      error = function(e) character(0)
    )
  }))
  is3 <- out$model == 3L
  is_rif <- identical(mf$engine, "rif")
  median_tau <- if (is_rif) mf$taus[min(5L, length(mf$taus))] else NA_real_
  imp <- tryCatch(importance_shares(extract_rif_median(mf$fit3, mf$engine)), error = function(e) NULL)
  out$importance_share <- NA_real_
  if (is.data.frame(imp)) {
    at <- is3 & (if (is_rif) out$tau %in% median_tau else TRUE)
    out$importance_share[at] <- imp$share[match(out$term[at], imp$term)]
  }
  out$lasso_freq <- NA_real_
  if (length(selection_frequency)) {
    out$lasso_freq[is3] <- unname(selection_frequency[out$term[is3]])
  }
  out$translation <- NA_character_
  foc <- step1_focused_df(mf, translations)
  if (is.data.frame(foc) && nrow(foc)) {
    key <- function(term, tau) paste(term, if (is_rif) format(tau, digits = 15) else "", sep = "|")
    hit <- match(
      key(out$term[is3], out$tau[is3]),
      key(foc$Term, if (is_rif) foc$Tau else NA_real_)
    )
    out$translation[is3] <- foc$Translation[hit]
  }
  rownames(out) <- NULL
  out[c(
    "model", "term", "tau", "is_weather", "estimate", "std_error", "statistic", "p_value",
    "conf_low", "conf_high", "n_obs", "importance_share", "lasso_freq", "translation"
  )]
}


# model_fit ----

#' Fit statistics, sample and effect inputs of a fit
#'
#' Long format: `section` says what a row describes. `fit` rows hold the
#' goodness-of-fit statistics per specification (and quantile); `sample` the
#' estimation sample; `spec` the engine, model family, variance estimator and
#' any fallback the fitter applied (as `text`); `effect_inputs` the model-sample
#' range, mean and SD of each continuous weather variable, the values of each
#' moderator (interaction: `mod_min`, `mod_max`, `mod_mean`, `mod_sd`,
#' `mod_n_distinct`, or the `mod_levels` of a categorical one) and, for binary
#' outcomes, the median-risk linear predictor `profile_eta` that the effect
#' chart needs; `headline` the "At a glance" cards (`text` = value, `detail` =
#' note).
#'
#' @param mf A `wise_fit()` list with `.snap`.
#' @param translations Result of `step1_translations()`.
#' @return A data frame: `section`, `variable`, `model`, `tau`, `statistic`,
#'   `value`, `text`, `detail`.
#' @noRd
model_fit_table <- function(mf, translations = step1_translations(mf)) {
  row <- function(section, statistic, value = NA_real_, text = NA_character_, detail = NA_character_,
                  variable = NA_character_, model = NA_integer_, tau = NA_real_) {
    data.frame(
      section = section, variable = variable, model = as.integer(model), tau = as.numeric(tau),
      statistic = statistic, value = as.numeric(value), text = as.character(text),
      detail = as.character(detail), stringsAsFactors = FALSE
    )
  }
  is_logit <- is_logistic_fit(mf)
  snap <- mf$.snap
  parts <- list()

  # Goodness of fit, per specification.
  for (m in 1:3) {
    s <- tryCatch(fit_stats_raw(mf[[paste0("fit", m)]], is_logit, mf$engine, mf$taus), error = function(e) NULL)
    if (!is.null(s)) {
      parts[[length(parts) + 1L]] <- row("fit", s$statistic, s$value, model = m, tau = s$tau)
    }
  }

  # Estimation sample and specification.
  fb <- mf$fallbacks %||% list()
  vcv_fallback <- any(vapply(fb, function(x) identical(x$kind, "vcv"), logical(1)))
  cluster <- as.character(snap$model$cluster %||% character(0))
  vcov_txt <- if (length(cluster) && !vcv_fallback) {
    paste0("clustered: ", paste(cluster, collapse = ", "))
  } else {
    "default (IID)"
  }
  parts[[length(parts) + 1L]] <- row("sample", "n_estimation", nrow(mf$train_data))
  parts[[length(parts) + 1L]] <- row("spec",
    c("engine", "model_family", "requested_type", "vcov", "fixed_effects", "covariate_selection"),
    text = c(
      mf$engine, mf$model_type, as.character(snap$model$type %||% NA_character_), vcov_txt,
      paste(mf$fe_terms, collapse = ","), as.character(snap$model$covariate_selection %||% NA_character_)
    )
  )
  for (x in fb) {
    parts[[length(parts) + 1L]] <- row("spec", paste0("fallback_", x$kind),
      text = paste0(x$requested, " -> ", x$used), detail = x$reason
    )
  }

  # Inputs of the effect charts.
  mm <- resolve_model_matrix(extract_rif_median(mf$fit3, mf$engine))
  for (v in mf$weather_terms) {
    x <- if (!is.null(mm) && v %in% names(mm)) suppressWarnings(as.numeric(mm[[v]])) else numeric(0)
    x <- x[is.finite(x)]
    if (length(x)) {
      sd_x <- suppressWarnings(as.numeric(mf$train_data[[v]]))
      sd_x <- sd_x[is.finite(sd_x)]
      parts[[length(parts) + 1L]] <- row("effect_inputs", c("x_min", "x_max", "x_mean", "x_sd"),
        c(min(x), max(x), mean(x), if (length(sd_x) > 10) stats::sd(sd_x) else NA_real_),
        variable = v
      )
    }
    eta <- translations$scenarios[[v]]$profile_eta
    if (length(eta) == 1L && is.finite(eta)) {
      parts[[length(parts) + 1L]] <- row("effect_inputs", "profile_eta", eta, variable = v)
    }
  }
  # Moderators of the weather effect (interactions): the values the "who is
  # affected" chart draws at, in the model sample. A numeric or binary moderator
  # has its range, mean and SD; a categorical one its levels.
  for (v in intersect(as.character(snap$model$interactions %||% character(0)), names(mf$train_data))) {
    z <- mf$train_data[[v]]
    if (is.numeric(z) || is.logical(z)) {
      z <- suppressWarnings(as.numeric(z))
      z <- z[is.finite(z)]
      if (length(z)) {
        parts[[length(parts) + 1L]] <- row("effect_inputs",
          c("mod_min", "mod_max", "mod_mean", "mod_sd", "mod_n_distinct"),
          c(min(z), max(z), mean(z), if (length(z) > 1L) stats::sd(z) else NA_real_, length(unique(z))),
          variable = v
        )
      }
    } else {
      lv <- if (is.factor(z)) levels(droplevels(z)) else sort(unique(as.character(z[!is.na(z)])))
      parts[[length(parts) + 1L]] <- row("effect_inputs", c("mod_n_distinct", "mod_levels"),
        c(length(lv), NA_real_), text = c(NA_character_, paste(lv, collapse = ",")), variable = v
      )
    }
  }

  # Headline cards.
  for (i in seq_along(translations$headline$rows)) {
    cards <- translations$headline$rows[[i]]$cards
    parts[[length(parts) + 1L]] <- row("headline",
      vapply(cards, function(c) c$label %||% "", character(1)),
      text = vapply(cards, function(c) c$value %||% "", character(1)),
      detail = vapply(cards, function(c) c$note %||% "", character(1)),
      variable = mf$weather_terms[i]
    )
  }
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}


# model_vcov ----

#' Covariance of the weather coefficients
#'
#' The variance-covariance matrix of specification (3) as the app reports it
#' (the fit-time estimator, clustered at the location panel when available),
#' restricted to the weather terms and their interactions and polynomials. One
#' block per quantile for RIF. Both triangles are stored.
#'
#' @param mf A `wise_fit()` list.
#' @return A data frame: `tau`, `term_1`, `term_2`, `covariance`, or `NULL`.
#' @noRd
model_vcov_table <- function(mf) {
  fits <- if (identical(mf$engine, "rif")) {
    stats::setNames(as.list(mf$fit3), mf$taus)
  } else {
    list(`NA` = mf$fit3)
  }
  blocks <- lapply(seq_along(fits), function(i) {
    fit <- fits[[i]]
    if (!inherits(fit, "fixest")) {
      return(NULL)
    }
    V <- tryCatch(.fixest_vcov(fit), error = function(e) NULL)
    if (is.null(V)) {
      return(NULL)
    }
    terms <- intersect(weather_coef_names(fit, mf$weather_terms), colnames(V))
    if (!length(terms)) {
      return(NULL)
    }
    g <- expand.grid(term_2 = terms, term_1 = terms, stringsAsFactors = FALSE)
    data.frame(
      tau = if (identical(mf$engine, "rif")) mf$taus[i] else NA_real_,
      term_1 = g$term_1, term_2 = g$term_2,
      covariance = V[cbind(g$term_1, g$term_2)],
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, blocks)
  if (!is.null(out)) rownames(out) <- NULL
  out
}


#' The three model tables of a fit
#'
#' @param mf A `wise_fit()` list with `.snap`.
#' @param selection_frequency Lasso selection frequencies or `NULL`.
#' @return A list: `model_terms`, `model_fit`, `model_vcov`.
#' @noRd
step1_model_tables <- function(mf, selection_frequency = NULL) {
  tr <- step1_translations(mf)
  list(
    model_terms = model_terms_table(mf, tr, selection_frequency),
    model_fit = model_fit_table(mf, tr),
    model_vcov = model_vcov_table(mf)
  )
}

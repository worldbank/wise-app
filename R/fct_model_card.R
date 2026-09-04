# ============================================================================ #
# Pure functions translating a `build_selected_model()` spec into the sparse   #
# formula line of the "Selected model" card (Results / Model fit tabs):        #
#   outcome ~ weather (+ interactions) + covariates | FE | clustering          #
# Stateless and testable without Shiny.                                        #
# ============================================================================ #


# ---------------------------------------------------------------------------- #
# Labels                                                                        #
# ---------------------------------------------------------------------------- #

#' Badge text for the model card: model type and fitting engine
#'
#' @param selected_model Named list from `build_selected_model()`.
#'
#' @return e.g. `"Linear regression \u00B7 OLS"`, `"Logistic regression
#'   \u00B7 logit"`, `"Random forest \u00B7 ranger"`.
#'
#' @export
model_badge <- function(selected_model) {
  type   <- as.character(selected_model$type[1] %||% "")
  engine <- as.character(selected_model$engine[1] %||% "fixest")
  eng <- switch(engine,
    fixest = switch(type,
      "Linear regression"   = "OLS",
      "Logistic regression" = "logit",
      engine),
    engine
  )
  paste0(type, " \u00B7 ", eng)
}

#' Plain-language clustering phrase for the formula tail
#'
#' @param cluster Scalar character cluster column name, or empty/NULL for
#'   unclustered.
#'
#' @return e.g. `"clustered by location panel"` or `"unclustered"`.
#'
#' @export
model_cluster_phrase <- function(cluster) {
  cl <- as.character(cluster[1])
  if (length(cl) == 0 || is.na(cl) || !nzchar(cl)) return("unclustered")
  paste0("clustered by ", switch(cl,
    loc_id_panel = "location panel",
    loc_id       = "location",
    cl
  ))
}

#' Count of model covariates by role
#'
#' @param selected_model Named list from `build_selected_model()`.
#'
#' @return Named integer vector (household, area, individual, firm) with only
#'   non-zero entries.
#'
#' @export
model_covariate_counts <- function(selected_model) {
  n <- vapply(
    selected_model[c("hh_covariates", "area_covariates", "ind_covariates",
                     "firm_covariates")],
    function(x) length(unlist(x)), integer(1)
  )
  n <- n[n > 0L]
  names(n) <- c("household", "area", "individual", "firm")[seq_along(n)]
  n[n > 0]
}

#' Total number of covariates in the model spec
#' @noRd
model_covariate_total <- function(selected_model) {
  sum(model_covariate_counts(selected_model))
}


# ---------------------------------------------------------------------------- #
# Card assembly                                                                 #
# ---------------------------------------------------------------------------- #

#' Assemble the "Selected model" card rows (sparse formula line)
#'
#' One row echoing a regression formula: outcome ~ weather terms (crossed
#' with interaction moderators when present) + covariates | fixed effects |
#' clustering. Model type and engine live in the card badge.
#'
#' @param selected_model Named list from `build_selected_model()`.
#' @param label_fun Optional function mapping variable names to display
#'   labels.
#' @param outcome_label Optional outcome label (left-hand side).
#' @param weather_labels Optional character vector of weather variable labels
#'   ("Monthly ..." prefixes are stripped).
#'
#' @return A list with one pre-built row tag for `selection_summary_card()`.
#'
#' @export
model_card_rows <- function(selected_model, label_fun = NULL,
                            outcome_label = NULL,
                            weather_labels = character(0)) {
  sm <- selected_model

  to_lab <- function(nms) {
    nms <- unlist(nms)
    if (!length(nms)) return(character(0))
    if (is.null(label_fun)) return(as.character(nms))
    vapply(nms, function(v) {
      l <- label_fun(v)
      if (length(l) > 0 && !is.na(l[1]) && nzchar(l[1])) l[1] else v
    }, character(1), USE.NAMES = FALSE)
  }

  wx  <- sub("^Monthly\\s+", "", as.character(weather_labels))
  wx  <- wx[!is.na(wx) & nzchar(wx)]
  mods <- to_lab(sm$interactions)
  mode <- as.character(sm$interaction_mode[1] %||% "pairwise")
  fe   <- to_lab(sm$fixedeffects)
  n_cov <- model_covariate_total(sm)

  # Weather terms: crossed with the moderators when interactions are set.
  # Saturated mode crosses each weather with the full moderator set; pairwise
  # mode generates one term per weather x moderator pair.
  wx_terms <- if (length(mods) && length(wx)) {
    if (identical(mode, "saturated")) {
      vapply(wx, function(w) paste0(w, " \u00D7 ", paste(mods, collapse = " \u00D7 ")),
             character(1))
    } else {
      as.vector(outer(wx, mods, function(a, b) paste0(a, " \u00D7 ", b)))
    }
  } else {
    wx
  }

  rhs <- as.character(wx_terms)
  if (n_cov > 0) rhs <- c(rhs, paste0(n_cov, " covariates"))
  if (!length(rhs)) rhs <- "no covariates"

  # Token list: (op, text, muted); op tokens render as light-blue symbols.
  toks <- list(
    list(op = NA, text = if (is.null(outcome_label) || !nzchar(outcome_label)) {
      "Outcome"
    } else outcome_label, muted = FALSE),
    list(op = "~", text = NA, muted = FALSE)
  )
  for (i in seq_along(rhs)) {
    if (i > 1) toks[[length(toks) + 1L]] <- list(op = "+", text = NA, muted = FALSE)
    toks[[length(toks) + 1L]] <- list(op = NA, text = rhs[i], muted = FALSE)
  }
  toks[[length(toks) + 1L]] <- list(op = "|", text = NA, muted = FALSE)
  if (length(fe)) {
    toks[[length(toks) + 1L]] <- list(
      op = NA, text = paste0(paste(fe, collapse = " \u00B7 "), " FE"), muted = TRUE
    )
    toks[[length(toks) + 1L]] <- list(op = "|", text = NA, muted = FALSE)
  }
  toks[[length(toks) + 1L]] <- list(
    op = NA, text = model_cluster_phrase(sm$cluster), muted = TRUE
  )

  kids <- lapply(toks, function(t) {
    if (!is.na(t$op)) {
      shiny::tags$span(class = "selection-card-op", t$op)
    } else {
      shiny::tags$span(
        class = if (isTRUE(t$muted)) "selection-card-muted" else "selection-card-formula",
        t$text
      )
    }
  })

  list(
    shiny::tags$div(
      class = "selection-card-row",
      shiny::tags$span(
        class = "selection-card-formula",
        do.call(htmltools::tagList, kids)
      )
    )
  )
}

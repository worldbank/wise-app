# ============================================================================ #
# Step 3 construction, treatment assignment, and covariate support diagnostics.
# ============================================================================ #

policy_treatment_matrix <- function(baseline_svy, policy_svy,
                                    eligibility = NULL, weight_col = "weight") {
  if (is.null(baseline_svy) || is.null(policy_svy) ||
      nrow(baseline_svy) != nrow(policy_svy)) return(data.frame())
  b <- if (!is.null(eligibility)) as.logical(eligibility) else {
    if ("sp_eligible" %in% names(baseline_svy)) as.logical(baseline_svy$sp_eligible) else rep(FALSE, nrow(baseline_svy))
  }
  p <- if (SP_TRANSFER_COL %in% names(policy_svy)) policy_svy[[SP_TRANSFER_COL]] > 0 else {
    if ("sp_eligible" %in% names(policy_svy)) as.logical(policy_svy$sp_eligible) else rep(FALSE, nrow(policy_svy))
  }
  b[is.na(b)] <- FALSE; p[is.na(p)] <- FALSE
  w <- if (weight_col %in% names(baseline_svy)) as.numeric(baseline_svy[[weight_col]]) else rep(1, nrow(baseline_svy))
  w[!is.finite(w) | w < 0] <- 0
  status <- interaction(b, p, drop = TRUE, sep = "_")
  labels <- c(`FALSE_FALSE` = "Still uncovered", `FALSE_TRUE` = "Newly covered",
              `TRUE_FALSE` = "Lost coverage", `TRUE_TRUE` = "Baseline covered")
  dplyr::bind_rows(lapply(names(labels), function(k) {
    ok <- as.character(status) == k
    data.frame(
      status = labels[[k]],
      eligible_baseline = startsWith(k, "TRUE"),
      treated_policy = endsWith(k, "TRUE"),
      n = sum(ok), weighted_n = sum(w[ok]),
      weighted_share = if (sum(w) > 0) sum(w[ok]) / sum(w) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
}

policy_covariate_support <- function(training, policy, vars = NULL,
                                     rare_share = 0.01) {
  if (is.null(training) || is.null(policy)) return(data.frame())
  vars <- vars %||% intersect(names(training), names(policy))
  vars <- setdiff(vars, c("welfare", "weight", "sim_year", "year"))
  dplyr::bind_rows(lapply(vars, function(v) {
    tr <- training[[v]]; po <- policy[[v]]
    if (is.numeric(tr) && is.numeric(po)) {
      lo <- min(tr, na.rm = TRUE); hi <- max(tr, na.rm = TRUE)
      out <- po < lo | po > hi
      data.frame(variable = v, type = "numeric", training_lo = lo,
                 training_hi = hi, policy_outside_n = sum(out, na.rm = TRUE),
                 policy_outside_share = mean(out, na.rm = TRUE),
                 rare_or_absent = FALSE, warning = any(out, na.rm = TRUE),
                 stringsAsFactors = FALSE)
    } else {
      trc <- as.character(tr); poc <- as.character(po)
      freq <- prop.table(table(trc, useNA = "no"))
      absent <- !(poc %in% names(freq))
      rare <- !absent & vapply(poc, function(x) {
        if (!x %in% names(freq)) return(FALSE)
        as.numeric(freq[[x]]) < rare_share
      }, logical(1L))
      data.frame(variable = v, type = "categorical", training_lo = NA,
                 training_hi = NA, policy_outside_n = 0,
                 policy_outside_share = 0,
                 rare_or_absent = any(absent | rare, na.rm = TRUE),
                 warning = any(absent | rare, na.rm = TRUE),
                 stringsAsFactors = FALSE)
    }
  }))
}

policy_treatment_assignment <- policy_treatment_matrix

policy_construction_summary <- function(baseline_svy, policy_svy, sp = NULL,
                                        analysis_unit = "hh", seed = WISEAPP_DEFAULT_SEED) {
  if (is.null(baseline_svy) || is.null(policy_svy)) return(data.frame())
  changed <- detect_manipulated_vars(baseline_svy, policy_svy)
  transfer <- if (SP_TRANSFER_COL %in% names(policy_svy)) policy_svy[[SP_TRANSFER_COL]] else rep(0, nrow(policy_svy))
  data.frame(
    item = c("Active manipulated variables", "Changed row count", "Weighted changed share",
             "Realized transfer total", "Random seed", "Reconciliation"),
    value = c(
      paste(changed, collapse = ", "),
      sum(vapply(seq_len(nrow(baseline_svy)), function(i) {
        any(vapply(changed, function(v) !identical(baseline_svy[[v]][[i]], policy_svy[[v]][[i]]), logical(1)))
      }, logical(1))),
      mean(vapply(seq_len(nrow(baseline_svy)), function(i) {
        any(vapply(changed, function(v) !identical(baseline_svy[[v]][[i]], policy_svy[[v]][[i]]), logical(1)))
      }, logical(1))),
      .sp_transfer_totals(policy_svy, analysis_unit)$total,
      seed,
      if (length(transfer) == nrow(policy_svy)) "Reconciled with realized policy frame" else "Unavailable"
    ), stringsAsFactors = FALSE
  )
}

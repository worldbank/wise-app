# Step 3 input glue ----
# The lever configurations and the `step3_compute()` arguments, built from plain
# named lists of control values (input id -> value). The Step 3 lever modules
# (`mod_3_01` to `mod_3_05`) and `mod_3_06` call these with their inputs; the
# batch runner calls them with the `policy` section of a spec, so the app and a
# batch run turn the same settings into the same configuration. Shiny-free.

# Input ids read by each lever. A missing id behaves like an input that has not
# been rendered yet (the fallbacks below).
STEP3_SP_IDS <- c(
  "sp_type", "budget_mode", "budget_fixed", "targeting", "targeting_threshold_pct",
  "pmt_variable", "pmt_cutoff", "inclusion_error_pct", "exclusion_error_pct",
  "error_concentration", "transfer_amount_mode", "transfer_pctile", "transfer_amount_usd",
  "amount_basis", "admin_cost_pct",
  "trigger_type", "trigger_variable", "trigger_direction", "trigger_value",
  "trigger_value_low", "trigger_return_period_years", "trigger_metric", "trigger_level",
  "trigger_pov_line", "payout_scope", "national_k_pct", "payments_per_activation",
  "dyn_geo", "dyn_geo_pct", "dyn_welfare", "dyn_welfare_pct", "dyn_incl_error_pct",
  "dyn_excl_error_pct", "budget_rule", "loss_share_pct", "annual_cap", "loss_event_pct",
  "transfer_n_payments", "transfer_timing", "timeliness_weeks", "forecast_pod_pct",
  "forecast_far_pct", "effect_multiplier", "delay_loss_pct_per_week"
)

#' Control ids of the access levers of a slot
#'
#' Levers are controlled by their code: `<code>_universal` and `<code>_pct`
#' (binary access), `<code>_pct` (percent change of a numeric variable), or the
#' `health_*` ids (travel time). Slots are `infra`, `digital`, `education` and
#' `other` (levers of any other group).
#'
#' @param slot One of the slots above.
#' @param registry Lever registry (`policy_registry()`).
#' @return Character vector of control ids.
#' @noRd
step3_ids <- function(slot, registry = policy_registry(NULL)) {
  r <- registry[registry$slot == slot & registry$behaviour %in% c("binary", "pct", "health"), , drop = FALSE]
  ids <- lapply(seq_len(nrow(r)), function(i) {
    switch(r$behaviour[i],
      binary = paste0(r$code[i], c("_universal", "_pct")),
      pct = paste0(r$code[i], "_pct"),
      health = c("health_mode", "health_travel_pct", "health_travel_max")
    )
  })
  unique(as.character(unlist(ids)))
}

# Ids of the levers of a data directory without policy metadata.
STEP3_INFRA_IDS <- step3_ids("infra")
STEP3_DIGITAL_IDS <- step3_ids("digital")
STEP3_EDUCATION_IDS <- step3_ids("education")
STEP3_OTHER_IDS <- step3_ids("other")
STEP3_LABOR_IDS <- c("labor_emp", "sector_manufacturing", "sector_services")

# The values of the named controls, as a list with an entry (possibly `NULL`)
# for each id. `read` is `function(id)`; a module passes `function(id) input[[id]]`.
#' @noRd
step3_read_inputs <- function(ids, read) {
  stats::setNames(lapply(ids, read), ids)
}

#' Social protection scenario configuration
#'
#' The scenario list `apply_policy_to_svy()` and `step3_compute()` take as
#' `sp_cfg`, from the control values of the social protection module.
#'
#' @param x Named list of control values by input id (`STEP3_SP_IDS`).
#' @param currency Currency of the entered amounts (`.sp_currency()`).
#' @param analysis_unit Analysis unit; a per-person amount only exists for `"hh"`.
#' @return The scenario list.
#' @noRd
wise_sp_config <- function(x, currency = "PPP", analysis_unit = "hh") {
  g <- function(id) x[[id]]
  num <- function(v) suppressWarnings(as.numeric(v))
  sp_type_val <- g("sp_type") %||% "regular"
  is_regular <- identical(sp_type_val, "regular")
  list(
    # program type
    sp_type = sp_type_val,
    # Budget mode: a shock program pays a fixed amount per activation
    budget_mode = if (identical(sp_type_val, "shock")) {
      "transfer_first"
    } else {
      g("budget_mode") %||% "transfer_first"
    },
    # Default to 0 (not 1,000,000) so an un-touched budget can never
    # accidentally apply a million-USD transfer if budget-first mode is
    # selected before a budget is entered.
    budget_fixed = g("budget_fixed") %||% 0,
    # Targeting
    targeting = g("targeting") %||% "exante_poor",
    targeting_threshold = g("targeting_threshold_pct") %||% 20,
    pmt_variable = g("pmt_variable") %||% NA_character_,
    pmt_cutoff = g("pmt_cutoff") %||% NA_real_,
    inclusion_error_pct = g("inclusion_error_pct") %||% 10,
    exclusion_error_pct = g("exclusion_error_pct") %||% 10,
    # 0 = errors fall on random units; larger = nearer the cutoff
    error_concentration = num(g("error_concentration") %||% 0),
    # Transfer amount per payment, in `currency` (outcome units; the id is
    # historical). A percentile of baseline welfare only sets the amount of a
    # regular program paid per transfer; `wise_sp_resolve_amount()` turns it
    # into `transfer_amount_usd`.
    currency = currency,
    transfer_amount_mode =
      if (!identical(sp_type_val, "shock") &&
        identical(g("budget_mode") %||% "transfer_first", "transfer_first") &&
        identical(g("transfer_amount_mode"), "pctile")) {
        "pctile"
      } else {
        "fixed"
      },
    transfer_pctile = num(g("transfer_pctile") %||% 10),
    transfer_amount_usd = g("transfer_amount_usd") %||% 0,
    # Per-person basis only exists for household analysis units
    amount_basis = if (identical(analysis_unit, "hh")) {
      g("amount_basis") %||% "per_household"
    } else {
      "per_household"
    },
    # Administration as a percentage of total cost
    admin_cost_pct = g("admin_cost_pct") %||% 0,
    # Shock-responsive trigger and payout (Trigger settings flyout)
    trigger_type = g("trigger_type") %||% "weather",
    trigger_variable = g("trigger_variable") %||% NA_character_,
    trigger_direction = g("trigger_direction") %||% "above",
    trigger_value = num(g("trigger_value") %||% NA_real_),
    trigger_value_low = num(g("trigger_value_low") %||% NA_real_),
    trigger_return_period_years = num(g("trigger_return_period_years") %||% NA_real_),
    trigger_metric = g("trigger_metric") %||% "weather",
    trigger_level = g("trigger_level") %||% "national",
    trigger_pov_line = num(g("trigger_pov_line") %||% NA_real_),
    payout_scope = g("payout_scope") %||% "local",
    national_k_pct = num(g("national_k_pct") %||% 0),
    payments_per_activation = g("payments_per_activation") %||% 1L,
    # Layered dynamic targeting (shock only)
    dyn_geo = g("dyn_geo") %||% "all",
    dyn_geo_pct = num(g("dyn_geo_pct") %||% 50),
    dyn_welfare = isTRUE(g("dyn_welfare")),
    dyn_welfare_pct = num(g("dyn_welfare_pct") %||% 20),
    dyn_incl_error_pct = num(g("dyn_incl_error_pct") %||% 20),
    dyn_excl_error_pct = num(g("dyn_excl_error_pct") %||% 20),
    # Budget rule and annual cap (shock only; blank cap = none)
    budget_rule = g("budget_rule") %||% "fixed",
    loss_share_pct = num(g("loss_share_pct") %||% NA_real_),
    annual_cap = num(g("annual_cap") %||% NA_real_),
    loss_event_pct = num(g("loss_event_pct") %||% 10),
    # Timing - regular programs always have n payments
    transfer_frequency =
      if (is_regular) {
        "regular"
      } else {
        g("transfer_frequency") %||% "oneoff"
      },
    transfer_n_payments =
      if (identical(sp_type_val, "shock")) {
        # Payments in an activated year, so the reach card and the cost
        # arithmetic read the same number as the dynamic transfer
        g("payments_per_activation") %||% 1L
      } else if (is_regular) {
        g("transfer_n_payments") %||% 6L
      } else {
        g("transfer_n_payments") %||% 1L
      },
    transfer_timing =
      if (is_regular) {
        NA_character_
      } else {
        g("transfer_timing") %||% "expost"
      },
    timeliness_weeks =
      if (is_regular) {
        NA_integer_
      } else {
        g("timeliness_weeks") %||% 0L
      },
    # Forecast skill, multiplier and delay loss (shock only, P2-7)
    forecast_pod_pct = num(g("forecast_pod_pct") %||% 100),
    forecast_far_pct = num(g("forecast_far_pct") %||% 0),
    effect_multiplier = num(g("effect_multiplier") %||% 1),
    delay_loss_pct_per_week = num(g("delay_loss_pct_per_week") %||% 0)
  )
}

#' Resolve a percentile transfer amount
#'
#' With `transfer_amount_mode == "pctile"` the amount per payment is the
#' weighted percentile of baseline daily welfare times 365 over the number of
#' payments, in the outcome's currency. The percentile is taken on the `welfare`
#' column of the baseline survey frame the policy is applied to, with the same
#' weighted quantile as the `exante_poor` cutoff (`.sp_welfare_quantile()`); for
#' an LCU outcome the welfare is first converted with `ppp2021`, the inverse of
#' the conversion the transfer undergoes. The amount is written to
#' `transfer_amount_usd`, so cost, cost-effectiveness, the preview and the run
#' read one number. Call it once per run, in the main process, with the frame
#' the run uses.
#'
#' @param sp Scenario list from `wise_sp_config()`.
#' @param svy Baseline survey frame (`welfare`, `weight`, `ppp2021`).
#' @return `sp` with `transfer_amount_usd` set and `amount_resolved` (`status`
#'   `"ok"` or `"unavailable"`, `pctile`, `daily_value`, `per_payment`,
#'   `per_year`, `n_obs`, `currency`). Unchanged for a fixed amount.
#' @noRd
wise_sp_resolve_amount <- function(sp, svy) {
  if (!identical(sp$transfer_amount_mode, "pctile")) {
    return(sp)
  }
  currency <- .sp_currency(sp$currency)
  res <- list(
    status = "unavailable", pctile = sp$transfer_pctile, daily_value = NA_real_,
    per_payment = NA_real_, per_year = NA_real_, n_obs = 0L, currency = currency
  )
  if (is.data.frame(svy) && "welfare" %in% names(svy) && is.finite(sp$transfer_pctile)) {
    w <- suppressWarnings(as.numeric(svy$welfare))
    if (identical(currency, "LCU") && "ppp2021" %in% names(svy)) {
      w <- w * suppressWarnings(as.numeric(svy$ppp2021))
    }
    wt <- if ("weight" %in% names(svy)) suppressWarnings(as.numeric(svy$weight))
    ok <- is.finite(w)
    if (!is.null(wt)) ok <- ok & is.finite(wt) & wt > 0
    res$n_obs <- sum(ok)
    if (res$n_obs >= 10L) {
      daily <- .sp_welfare_quantile(w[ok], wt[ok], sp$transfer_pctile / 100)
      if (is.finite(daily) && daily > 0) {
        res$daily_value <- daily
        res$per_year <- daily * 365
        res$per_payment <- res$per_year / sp$transfer_n_payments
        res$status <- "ok"
      }
    }
  }
  sp$transfer_amount_usd <- if (identical(res$status, "ok")) res$per_payment else 0
  sp$amount_resolved <- res
  sp
}

# One access lever: "universal" sets the change to 100 percent.
#' @noRd
.step3_access_change <- function(x, stem) {
  if (isTRUE(x[[paste0(stem, "_universal")]])) 100L else x[[paste0(stem, "_pct")]] %||% 0L
}

#' Access-lever scenario configuration of one slot
#'
#' The scenario list `apply_policy_to_svy()` takes as `infra`, `digital` or
#' `education`, from the control values of the levers of the slot (by lever
#' code, see `step3_ids()`). Binary levers give `<code>_universal` and
#' `<code>_access_change_pct`, numeric levers `<code>_value_change_pct`, the
#' health lever its three fields. `lever_vars` records each lever's variables.
#' Control values under earlier stems (`elec`, `primary`, ...) are read as the
#' lever's.
#'
#' @param x Named list of control values by input id.
#' @param slot `infra`, `digital`, `education` or `other`.
#' @param registry Lever registry (`policy_registry()`).
#' @return The scenario list.
#' @noRd
wise_access_config <- function(x, slot, registry = policy_registry(NULL)) {
  x <- policy_normalise_stems(x)
  r <- registry[registry$slot == slot & registry$behaviour %in% c("binary", "pct", "health"), , drop = FALSE]
  out <- list()
  # one control per lever, however many variables (levels) the lever has
  for (i in which(!duplicated(r$code))) {
    code <- r$code[i]
    out <- c(out, switch(r$behaviour[i],
      # TRUE = set all to 1, FALSE = change by pct
      binary = stats::setNames(
        list(isTRUE(x[[paste0(code, "_universal")]]), .step3_access_change(x, code)),
        paste0(code, c("_universal", "_access_change_pct"))
      ),
      pct = stats::setNames(
        list(x[[paste0(code, "_pct")]] %||% 0L),
        paste0(code, "_value_change_pct")
      ),
      # Health facility travel time
      health = list(
        health_mode = x[["health_mode"]] %||% "pct",
        health_travel_pct = x[["health_travel_pct"]] %||% 0L,
        health_travel_max = x[["health_travel_max"]] %||% 60L
      )
    ))
  }
  out$lever_vars <- lapply(split(r$var, factor(r$code, levels = unique(r$code))), unique)
  out$lever_groups <- as.list(stats::setNames(r$group, r$code)[!duplicated(r$code)])
  out
}

#' Infrastructure, digital inclusion, education and other-group scenarios
#' @param x Named list of control values by input id.
#' @param registry Lever registry (`policy_registry()`).
#' @return The scenario list.
#' @noRd
wise_infra_config <- function(x, registry = policy_registry(NULL)) {
  wise_access_config(x, "infra", registry)
}

#' @rdname wise_infra_config
#' @noRd
wise_digital_config <- function(x, registry = policy_registry(NULL)) {
  wise_access_config(x, "digital", registry)
}

#' @rdname wise_infra_config
#' @noRd
wise_education_config <- function(x, registry = policy_registry(NULL)) {
  wise_access_config(x, "education", registry)
}

#' @rdname wise_infra_config
#' @noRd
wise_other_config <- function(x, registry = policy_registry(NULL)) {
  wise_access_config(x, "other", registry)
}

#' Merge access-lever scenario lists
#'
#' Levers of groups without a module of their own are controlled in the "other"
#' module and run with the infrastructure scenario: the lists are merged, fields
#' and `lever_vars` alike (fields are named by lever code, so they cannot clash).
#'
#' @param ... Scenario lists (`NULL` ignored).
#' @return The merged list, or `NULL` when none is given.
#' @noRd
step3_merge_access <- function(...) {
  cfgs <- Filter(is.list, list(...))
  if (!length(cfgs)) {
    return(NULL)
  }
  meta <- c("lever_vars", "lever_groups")
  out <- do.call(c, lapply(cfgs, function(z) z[setdiff(names(z), meta)]))
  for (m in meta) {
    x <- do.call(c, lapply(cfgs, function(z) z[[m]]))
    if (length(x)) out[[m]] <- x[!duplicated(names(x))]
  }
  out
}

# Labels of the groups with a moved lever in a scenario list, for the summary
# card: the label of the slot's own module, or the group text of other levers.
#' @noRd
.access_active_labels <- function(cfg, default) {
  codes <- .access_cfg_moved_codes(cfg)
  groups <- vapply(codes, function(k) as.character(cfg$lever_groups[[k]] %||% ""), character(1))
  slot_label <- c(infrastructure = "Infrastructure", digital = "Digital inclusion", education = "Education")
  lab <- ifelse(groups %in% names(slot_label), unname(slot_label[groups]),
    ifelse(!nzchar(groups), default,
      paste0(toupper(substring(groups, 1, 1)), gsub("_", " ", substring(groups, 2), fixed = TRUE))
    )
  )
  unique(lab)
}

# Sector-slider defaults: the observed shares of the survey, rounded, so an
# untouched slider is "no change" rather than a 0 percent target (R2-BUG-05).
#' @noRd
step3_sector_defaults <- function(svy) {
  shares <- .labor_sector_shares(svy)
  if (is.null(shares)) {
    c(industry = 0, services = 0)
  } else {
    round(shares[c("industry", "services")])
  }
}

#' The inputs of one `step3_compute()` run
#'
#' @param svy Baseline survey frame: the one Step 2 used, with the outcome column.
#' @param mf The (slim) model fit of Step 1.
#' @param sp_cfg,infra_cfg,digital_cfg,labor_cfg,education_cfg Lever
#'   configurations (`NULL`: the lever is not part of the run).
#' @param model_vars Names of the variables of the selected model
#'   (`model_term_names()`).
#' @param analysis_unit Analysis unit of the run.
#' @param skip_coef Skip coefficient draws (Step 2 setting).
#' @param residuals Residual rule requested for Step 2.
#' @param run_generation Generation of the run, part of the run identity.
#' @param seed Seed of the policy draws.
#' @return The argument list `step3_compute()` takes besides `hs` and `ss`.
#' @noRd
wise_step3_input <- function(svy, mf, sp_cfg = NULL, infra_cfg = NULL, digital_cfg = NULL,
                             labor_cfg = NULL, education_cfg = NULL,
                             model_vars = character(), analysis_unit = "hh",
                             skip_coef = FALSE, residuals = "original",
                             run_generation = 0L, seed = NULL) {
  list(
    svy = svy, mf = mf,
    sp_cfg = sp_cfg, infra_cfg = infra_cfg,
    digital_cfg = digital_cfg, labor_cfg = labor_cfg,
    education_cfg = education_cfg,
    model_vars = model_vars,
    analysis_unit = analysis_unit,
    skip_coef = skip_coef,
    residuals = residuals,
    run_generation = run_generation,
    seed = seed
  )
}

#' Labor market scenario configuration
#'
#' A sector target is `NULL` ("unchanged") until its slider moves away from the
#' observed share; `apply_policy_to_svy()` reallocates only then.
#'
#' @param x Named list of control values by input id (`STEP3_LABOR_IDS`).
#' @param defaults Observed sector shares (`step3_sector_defaults()`).
#' @return The scenario list.
#' @noRd
wise_labor_config <- function(x, defaults) {
  sector_target <- function(value, default) {
    if (is.null(value) || isTRUE(value == default)) NULL else value
  }
  mfg <- x[["sector_manufacturing"]] %||% 0
  services <- x[["sector_services"]] %||% 0
  list(
    employment_change_pp = x[["labor_emp"]] %||% 0,
    sector_manufacturing = sector_target(x[["sector_manufacturing"]], defaults[["industry"]]),
    sector_services = sector_target(x[["sector_services"]], defaults[["services"]]),
    sector_agriculture = max(0L, 100L - mfg - services)
  )
}

# Keep the last successful result/context pair intact until the next run has
# completed all work. A failed run therefore has no publication side effect.
.publish_decomposition_bundle <- function(previous, context, success) {
  if (!isTRUE(success)) {
    return(previous)
  }
  list(context = context)
}

# R2-BUG-14: Step 3 combines the live Step 1 fit with the stored Step 2
# result. The Step 2 run signature records the fit signature it was built
# from, so a different live fit means Step 2 is stale for the current model
# and the policy run must not start. Results without a recorded signature
# are not judged.
.step2_model_mismatch <- function(mf, hs) {
  if (is.null(mf) || is.null(hs) || !is.list(hs$.sig)) {
    return(FALSE)
  }
  !identical(mf$.sig, hs$.sig$fit_sig)
}

# First missing prerequisite of a policy run as a message for the user, or NULL
# when the run can start. Order matters: it is the order the checks were made
# in mod_3_06_policy_sim_server()'s run().
.step3_run_prerequisite_error <- function(mf, hs, sw, svy) {
  if (is.null(mf)) {
    return(paste(
      "No fitted model. Run the Step 1 model before simulating policy",
      "scenarios."
    ))
  }
  if (is.null(hs)) {
    return("Step 2 simulation must be run before policy simulation.")
  }
  if (.step2_model_mismatch(mf, hs)) {
    return(paste(
      "The Step 1 model changed after the Step 2 simulation ran.",
      "Re-run the Step 2 simulation before simulating policy scenarios."
    ))
  }
  if (is.null(sw)) {
    return(paste(
      "No weather variables selected. Configure them in Step 1 before",
      "simulating policy scenarios."
    ))
  }
  if (is.null(svy)) {
    return("Survey data not available.")
  }
  NULL
}

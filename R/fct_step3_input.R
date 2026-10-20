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

STEP3_INFRA_IDS <- c(
  paste0(rep(c("elec", "water", "sanitation", "piped", "piped_to_prem", "imp_wat_san"), each = 2L),
    c("_universal", "_pct")),
  "health_mode", "health_travel_pct", "health_travel_max"
)
STEP3_DIGITAL_IDS <- c("internet_universal", "internet_pct", "mobile_universal", "mobile_pct")
STEP3_EDUCATION_IDS <- c(
  "primary_universal", "primary_pct", "secondary_universal", "secondary_pct",
  "postsec_universal", "postsec_pct"
)
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
  is_regular <- TRUE
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

#' Infrastructure scenario configuration
#' @param x Named list of control values by input id (`STEP3_INFRA_IDS`).
#' @return The scenario list.
#' @noRd
wise_infra_config <- function(x) {
  access <- function(stem, field = stem) {
    out <- list(
      isTRUE(x[[paste0(stem, "_universal")]]),
      .step3_access_change(x, stem)
    )
    names(out) <- c(paste0(field, "_universal"), paste0(field, "_access_change_pct"))
    out
  }
  c(
    # Electricity: TRUE = set all to 1, FALSE = increase by pct
    access("elec"), access("water"), access("sanitation"), access("piped"),
    access("piped_to_prem"), access("imp_wat_san"),
    # Health facility travel time
    list(
      health_mode = x[["health_mode"]] %||% "pct",
      health_travel_pct = x[["health_travel_pct"]] %||% 0L,
      health_travel_max = x[["health_travel_max"]] %||% 60L
    )
  )
}

#' Digital inclusion scenario configuration
#' @param x Named list of control values by input id (`STEP3_DIGITAL_IDS`).
#' @return The scenario list.
#' @noRd
wise_digital_config <- function(x) {
  list(
    internet_universal = isTRUE(x[["internet_universal"]]),
    internet_access_change_pct = .step3_access_change(x, "internet"),
    mobile_universal = isTRUE(x[["mobile_universal"]]),
    mobile_access_change_pct = .step3_access_change(x, "mobile")
  )
}

#' Education scenario configuration
#' @param x Named list of control values by input id (`STEP3_EDUCATION_IDS`).
#' @return The scenario list.
#' @noRd
wise_education_config <- function(x) {
  list(
    primary_universal = isTRUE(x[["primary_universal"]]),
    primary_access_change_pct = .step3_access_change(x, "primary"),
    secondary_universal = isTRUE(x[["secondary_universal"]]),
    secondary_access_change_pct = .step3_access_change(x, "secondary"),
    postsec_universal = isTRUE(x[["postsec_universal"]]),
    postsec_access_change_pct = .step3_access_change(x, "postsec")
  )
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

# Policy scenario discovery and diagnostics ----
# Pure functions for policy scenario variable discovery and diagnostics.
# Stateless and testable without Shiny.


#' Internal column name holding the per-household SP cash-transfer amount
#'
#' Set by \code{apply_policy_to_svy()}, read by \code{run_sim_pipeline()} (which
#' adds it to predicted welfare on the level scale), the diagnostics module,
#' and the decomposition. The leading-dot prefix marks it as an internal column
#' and the suffix makes it unlikely to collide with a user-supplied variable.
#' Treat this constant as the single source of truth across the codebase.
#' @export
SP_TRANSFER_COL <- ".wiseapp_sp_transfer"

# Shock-responsive mode (P1-4): `apply_policy_to_svy()` writes this logical
# column (static targeting result, including errors) and no transfer. The
# amount is paid per row, year and member only when the trigger fires, so a
# static `SP_TRANSFER_COL` would count the transfer twice.
SP_ELIGIBLE_COL <- ".wiseapp_sp_eligible"


# Policy activity predicates ----

# Keep the summary card and policy application on the same definition of an
# active lever. Selecting a policy domain alone is not an intervention.
.lever_moved <- function(x) {
  is.numeric(x) && length(x) == 1L && is.finite(x) && x != 0
}

.access_moved <- function(universal, change_pct) {
  isTRUE(universal) || .lever_moved(change_pct)
}

# Sector sliders carry a target share only when the user changed it from the
# observed share; NULL means "unchanged", and 0 is a valid target.
.sector_target_set <- function(x) {
  is.numeric(x) && length(x) == 1L && is.finite(x)
}

# Exact lever/term matching (CR-BUG-08) ----

#' Match a policy lever variable against model variable or coefficient names
#'
#' The single matcher shared by the lever UI gating, `apply_policy_to_svy()`
#' gating and the decomposition term maps. Each name is split on `:` and a
#' component matches when it equals `var`, or `var` followed by one of its
#' factor levels (`values` is the survey column, used only to derive the
#' levels of factor, character or logical columns). Matching is exact and
#' case-insensitive, so `piped` never matches `piped_to_prem`.
#'
#' @param var Lever variable name (scalar).
#' @param terms Character vector of model variable or coefficient names.
#' @param values Optional survey column for `var`.
#' @param partner Optional weather variable. When NULL, returns the main-effect
#'   terms of `var` (no `:`), exact name first. When supplied, returns the
#'   two-way interaction terms whose other component starts with `partner`.
#' @param any_component When TRUE, returns every name in which `var` appears
#'   as a component (main effect or interaction); used for lever gating.
#' @return Character vector of matching names.
#' @keywords internal
.policy_lever_terms <- function(var, terms, values = NULL, partner = NULL,
                                any_component = FALSE) {
  terms <- as.character(terms %||% character(0))
  if (!length(terms) || is.null(var) || !nzchar(var)) {
    return(character(0))
  }
  lvls <- if (is.factor(values)) {
    levels(values)
  } else if (is.character(values)) {
    unique(values[!is.na(values)])
  } else if (is.logical(values)) {
    "TRUE"
  } else {
    character(0)
  }
  keys <- tolower(unique(c(var, paste0(var, lvls))))
  parts <- strsplit(tolower(terms), ":", fixed = TRUE)
  hit <- vapply(parts, function(p) {
    if (isTRUE(any_component)) {
      return(any(p %in% keys))
    }
    if (is.null(partner)) {
      return(length(p) == 1L && p %in% keys)
    }
    length(p) == 2L && sum(p %in% keys) == 1L &&
      startsWith(p[!p %in% keys], tolower(partner))
  }, logical(1))
  out <- terms[hit]
  # Prefer the exact variable name over level-suffixed terms.
  out[order(tolower(out) != tolower(var))]
}

#' Is a lever variable referenced by the Step 1 model?
#' @param var Lever variable name(s).
#' @param model_vars Model variable or term names.
#' @return Logical vector, one per `var`.
#' @keywords internal
.lever_in_model <- function(var, model_vars) {
  vapply(var, function(v) {
    length(.policy_lever_terms(v, model_vars, any_component = TRUE)) > 0L
  }, logical(1), USE.NAMES = FALSE)
}

#' Has the infrastructure scenario been changed from its defaults?
#' @param infra Scenario list from `mod_3_02_infra_server()`.
#' @return Scalar logical.
#' @export
has_infra_change <- function(infra) {
  length(.access_cfg_moved_codes(infra)) > 0L
}

# The lever codes a scenario list (infra, digital, education) has moved. A lever
# is a set of fields named by its code: `<code>_universal` and
# `<code>_access_change_pct` (binary access), `<code>_value_change_pct` (percent
# change of a numeric variable), or the `health_*` fields (travel time). Fields
# are read by name, so a scenario needs no list of known levers.
#' @noRd
.access_cfg_moved_codes <- function(cfg) {
  if (!is.list(cfg)) {
    return(character(0))
  }
  nm <- names(cfg)
  moved <- character(0)
  for (f in nm[grepl("_universal$", nm)]) {
    if (isTRUE(cfg[[f]])) moved <- c(moved, sub("_universal$", "", f))
  }
  for (f in nm[grepl("_(access|value)_change_pct$", nm)]) {
    if (.lever_moved(cfg[[f]])) moved <- c(moved, sub("_(access|value)_change_pct$", "", f))
  }
  if (.lever_moved(cfg$health_travel_pct) || identical(cfg$health_mode, "max")) {
    moved <- c(moved, "health")
  }
  # (a binary lever with the code `health` is found by its own fields above)
  unique(.cfg_stem_code(moved))
}

# Earlier scenario lists name levers by old stems (`elec`, `primary`, ...).
#' @noRd
.cfg_stem_code <- function(stem) {
  unname(ifelse(stem %in% names(POLICY_STEM_ALIASES), POLICY_STEM_ALIASES[stem], stem))
}

# Variables of the levers a scenario list carries, as a named list code -> vars.
# `wise_access_config()` records them (`lever_vars`); a list without them (an
# earlier shape) reads the levers from its field names and takes the variables of
# the default levers.
#' @noRd
.cfg_lever_vars <- function(cfg) {
  if (!is.list(cfg)) {
    return(list())
  }
  lv <- cfg$lever_vars
  lv <- if (is.list(lv)) lv else list()
  nm <- names(cfg)
  codes <- c(
    sub("_universal$", "", nm[grepl("_universal$", nm)]),
    sub("_(access|value)_change_pct$", "", nm[grepl("_(access|value)_change_pct$", nm)]),
    if (any(c("health_mode", "health_travel_pct", "health_travel_max") %in% nm)) "health"
  )
  for (k in setdiff(unique(.cfg_stem_code(codes)), names(lv))) {
    v <- POLICY_FALLBACK$var[POLICY_FALLBACK$code == k]
    lv[[k]] <- if (length(v)) v else k
  }
  lv
}

# Field of a lever in a scenario list, under its code or an old stem.
#' @noRd
.cfg_field <- function(cfg, code, suffix) {
  stems <- c(code, names(POLICY_STEM_ALIASES)[POLICY_STEM_ALIASES == code])
  for (s in stems) {
    f <- paste0(s, suffix)
    if (f %in% names(cfg)) {
      return(cfg[[f]])
    }
  }
  NULL
}

#' Has the digital inclusion scenario been changed from its defaults?
#' @param digital Scenario list from `mod_3_03_digital_server()`.
#' @return Scalar logical.
#' @export
has_digital_change <- function(digital) {
  length(.access_cfg_moved_codes(digital)) > 0L
}

#' Has the education scenario been changed from its defaults?
#' @param education Scenario list from `mod_3_05_education_server()`.
#' @return Scalar logical.
#' @export
has_education_change <- function(education) {
  length(.access_cfg_moved_codes(education)) > 0L
}

#' Has the labor market scenario been changed from its defaults?
#' @param labor Scenario list from `mod_3_04_labor_server()`.
#' @return Scalar logical.
#' @export
has_labor_change <- function(labor) {
  if (!is.list(labor)) {
    return(FALSE)
  }
  .lever_moved(labor$employment_change_pp) ||
    .sector_target_set(labor$sector_manufacturing) ||
    .sector_target_set(labor$sector_services)
}

# Rows of the working population: employed, or self-employed when the file
# keeps the two apart. `selfemployed` is optional.
#' @noRd
.labor_working <- function(svy) {
  working <- svy$employed %in% 1L
  if ("selfemployed" %in% names(svy)) working <- working | svy$selfemployed %in% 1L
  working
}

#' Observed sector shares of the working population
#'
#' Initial values for the labour lever's sector sliders, so an untouched
#' slider means "no change". Uses survey `weight` when present (as the SP
#' reach preview does), otherwise row counts.
#' @param svy Survey frame with `employed`, `selfemployed`, `agriculture`,
#'   `industry` and `services`.
#' @return Named numeric vector (`industry`, `services`, `agriculture`) of
#'   percentages, or NULL when the shares cannot be computed.
#' @keywords internal
.labor_sector_shares <- function(svy) {
  need <- c("employed", "agriculture", "industry", "services")
  if (!is.data.frame(svy) || !all(need %in% names(svy))) {
    return(NULL)
  }
  working <- .labor_working(svy)
  w <- if ("weight" %in% names(svy)) {
    suppressWarnings(as.numeric(svy$weight))
  } else {
    rep(1, nrow(svy))
  }
  w[!is.finite(w) | w < 0] <- 0
  total <- sum(w[working])
  if (!any(working) || total <= 0) {
    return(NULL)
  }
  vapply(c("industry", "services", "agriculture"), function(sec) {
    100 * sum(w[working & svy[[sec]] == 1L], na.rm = TRUE) / total
  }, numeric(1))
}

#' Has social protection been configured to spend money?
#' @param sp Scenario list from `mod_3_01_sp_server()`.
#' @return Scalar logical.
#' @export
has_sp_change <- function(sp) {
  if (!is.list(sp)) {
    return(FALSE)
  }
  if (identical(sp$sp_type, "shock")) {
    # Fixed amount per activation (the budget mode is not used, decision 12), or
    # a share of modelled loss (P2-6), which needs no amount
    spends <- if (identical(sp$budget_rule %||% "fixed", "loss_share")) {
      .lever_moved(sp$loss_share_pct)
    } else {
      .lever_moved(sp$transfer_amount_usd) &&
        .lever_moved(sp$payments_per_activation %||% 1L)
    }
    return(spends && is.null(.sp_shock_problem(sp)))
  }
  if (identical(sp$budget_mode %||% "transfer_first", "budget_first")) {
    .lever_moved(sp$budget_fixed)
  } else {
    .lever_moved(sp$transfer_amount_usd) &&
      .lever_moved(sp$transfer_n_payments)
  }
}


#' Known survey columns that policy levers can modify
#'
#' Keep changed-column scans bounded to the columns the Step 3 policy
#' application can actually mutate. Social protection is handled separately
#' through `SP_TRANSFER_COL`; diagnostics optionally include the outcome after
#' applying that transfer to a local copy.
#'
#' @param infra,digital,labor,education Optional policy scenario lists. When
#'   none are supplied, all known policy covariates are returned.
#' @param model_vars Optional model terms used to apply the same gating as
#'   `apply_policy_to_svy()`.
#' @param outcome Optional outcome column to include (diagnostics only).
#' @return Character vector in stable policy-definition order.
#' @keywords internal
.policy_candidate_cols <- function(infra = NULL, digital = NULL, labor = NULL,
                                   education = NULL, model_vars = NULL,
                                   outcome = NULL) {
  definition_vars <- unlist(
    lapply(POLICY_DEFINITIONS, function(def) def$vars %||% character()),
    use.names = FALSE
  )
  labor_vars <- c(
    "employed", "selfemployed", "unemployed",
    "agriculture", "industry", "services"
  )
  cfg_vars <- unlist(lapply(
    list(infra, digital, education), function(cfg) unlist(.cfg_lever_vars(cfg), use.names = FALSE)
  ), use.names = FALSE)
  all_candidates <- unique(c(definition_vars, labor_vars, cfg_vars))

  scenarios_supplied <- !all(vapply(
    list(infra, digital, labor, education), is.null, logical(1)
  ))
  if (!scenarios_supplied) {
    return(unique(c(all_candidates, outcome)))
  }

  changed <- function(x) {
    if (is.null(x) || length(x) != 1L || is.na(x)) {
      return(FALSE)
    }
    if (is.logical(x)) isTRUE(x) else x != 0
  }
  candidates <- character()

  for (cfg in list(infra, digital, education)) {
    lv <- .cfg_lever_vars(cfg)
    for (code in .access_cfg_moved_codes(cfg)) {
      candidates <- c(candidates, lv[[code]])
    }
  }
  if (!is.null(labor)) {
    if (changed(labor$employment_change_pp)) {
      candidates <- c(candidates, "employed", "selfemployed", "unemployed")
    }
    if (.sector_target_set(labor$sector_manufacturing) ||
      .sector_target_set(labor$sector_services)) {
      candidates <- c(
        candidates, "employed", "selfemployed",
        "agriculture", "industry", "services"
      )
    }
  }

  candidates <- unique(candidates)
  if (!is.null(model_vars)) {
    candidates <- candidates[.lever_in_model(candidates, model_vars)]
  }
  unique(c(candidates, outcome))
}


#' Population-level cost of an applied social-protection transfer
#'
#' The single implementation of the transfer arithmetic the Step 3 diagnostics
#' tab reports. Reads the transfer column `apply_policy_to_svy()` wrote, so it
#' cannot drift from what was actually applied.
#'
#' `SP_TRANSFER_COL` holds a *daily* amount, already divided by household size
#' where welfare is per-capita (analysis unit "hh"). With survey weights, each
#' household row's weight represents people, so multiplying the per-capita
#' transfer by that weight gives the population cost. Without weights, each row
#' represents one household and `hhsize` restores its household-level amount.
#'
#' `SP_TRANSFER_COL` is on the scale of the stored `welfare` column (2021 PPP).
#' `currency = "LCU"` converts it back to 2021 LCU (times `ppp2021`) so that
#' totals are reported in the currency the amount was entered in.
#'
#' @param svy_policy    Survey frame after `apply_policy_to_svy()`.
#' @param analysis_unit `"hh"`, `"ind"` or `"firm"`.
#' @param currency      `"PPP"` (default) or `"LCU"`; see `sp$currency`.
#' @param admin_share   Administrative cost as a share of total cost, in
#'   `[0, 0.9]` (see `.sp_admin_share()`). The transfer column holds net
#'   transfers only, so admin cost is `transfer / (1 - a) - transfer`.
#'
#' @return A named list: `total` (annual population cost of the transfers
#'   themselves), `admin_cost` and `total_cost` (transfers plus admin; equal to
#'   `total` when `admin_share` is 0), `per_unit` (annual
#'   amount per recipient), `n_recipients` (sample rows receiving a transfer),
#'   `n_recipients_weighted` (people represented),
#'   `n_households_weighted` (recipient households represented in household
#'   mode) and `weighted`
#'   (whether survey weights were used).
#' @keywords internal
.sp_transfer_totals <- function(svy_policy, analysis_unit = "hh",
                                currency = "PPP", admin_share = 0) {
  if (is.null(svy_policy) || !is.data.frame(svy_policy) ||
    !SP_TRANSFER_COL %in% names(svy_policy)) {
    return(.sp_transfer_totals_values(
      NULL, svy_policy, analysis_unit, currency, admin_share
    ))
  }
  .sp_transfer_totals_values(
    svy_policy[[SP_TRANSFER_COL]], svy_policy, analysis_unit, currency,
    admin_share
  )
}

.sp_transfer_totals_values <- function(v, svy, analysis_unit = "hh",
                                       currency = "PPP", admin_share = 0) {
  zero <- list(
    total = 0, admin_cost = 0, total_cost = 0, per_unit = 0, n_recipients = 0L,
    n_recipients_weighted = 0, weighted = FALSE
  )
  if (is.null(svy) || !is.data.frame(svy) || is.null(v) ||
    length(v) != nrow(svy)) {
    return(zero)
  }

  v <- suppressWarnings(as.numeric(v))
  # Stored scale (PPP) -> entry currency. No-op when the data carry no ppp2021
  # (no load-time conversion happened), matching .povline_to_ppp().
  if (identical(.sp_currency(currency), "LCU") && "ppp2021" %in% names(svy)) {
    v <- v * suppressWarnings(as.numeric(svy$ppp2021))
  }

  has_w <- "weight" %in% names(svy)
  w <- if (has_w) {
    suppressWarnings(as.numeric(svy$weight))
  } else {
    rep(1, nrow(svy))
  }

  # In household mode, row weights represent population; divide by household
  # size to recover recipient-household equivalents for cost arithmetic.
  hh <- if (identical(analysis_unit, "hh") && "hhsize" %in% names(svy)) {
    h <- suppressWarnings(as.numeric(svy$hhsize))
    h[!is.finite(h) | h <= 0] <- 1
    h
  } else {
    rep(1, nrow(svy))
  }

  ok <- is.finite(v) & is.finite(w)
  if (!any(ok)) {
    return(zero)
  }

  cost_scale <- if (identical(analysis_unit, "hh") && !has_w) {
    hh
  } else {
    rep(1, nrow(svy))
  }
  total <- sum(v[ok] * w[ok] * cost_scale[ok]) * 365

  elig <- ok & v > 0
  unit_weight <- if (identical(analysis_unit, "hh") && has_w) w / hh else w
  per_unit <- if (any(elig) && sum(unit_weight[elig]) > 0) {
    (sum(v[elig] * w[elig] * cost_scale[elig]) /
       sum(unit_weight[elig])) * 365
  } else {
    0
  }

  admin_share <- if (is.finite(admin_share) && admin_share > 0) {
    min(admin_share, 0.9)
  } else {
    0
  }
  admin_cost <- total * admin_share / (1 - admin_share)

  list(
    total                 = total,
    admin_cost            = admin_cost,
    total_cost            = total + admin_cost,
    per_unit              = per_unit,
    n_recipients          = sum(elig),
    n_recipients_weighted = if (any(elig)) sum(w[elig]) else 0,
    n_households_weighted = if (identical(analysis_unit, "hh")) {
      if (any(elig)) sum(unit_weight[elig]) else 0
    } else {
      NA_real_
    },
    weighted              = has_w
  )
}

# Build the transfer vector from an eligibility draw. Both the preview and
# apply_policy_to_svy() use this arithmetic; only the latter writes the vector
# onto the survey as SP_TRANSFER_COL.
.sp_transfer_values <- function(svy, sp, analysis_unit, eligible) {
  if (length(eligible) != nrow(svy) || !"welfare" %in% names(svy)) {
    return(NULL)
  }

  hhsize_scale <- if (identical(analysis_unit, "hh") && "hhsize" %in% names(svy)) {
    hs <- suppressWarnings(as.numeric(svy$hhsize))
    hs[!is.finite(hs) | hs <= 0] <- 1
    hs
  } else {
    rep_len(1, nrow(svy))
  }

  # The amount is entered in the outcome's currency (`sp$currency`), but the
  # transfer column is added to the stored welfare, which is 2021 PPP. An LCU
  # amount is divided by the per-row ppp2021 factor (R2-BUG-04); PPP amounts
  # and data without deflators pass through unchanged.
  to_welfare_scale <- function(x) {
    .povline_to_ppp(x, svy, identical(.sp_currency(sp$currency), "LCU"))
  }

  # Per household (default): the amount is shared across the household's
  # members, so the per-capita welfare gain is amount / hhsize. Per capita:
  # every member of a recipient household receives the amount, so the
  # per-capita gain is the amount itself and cost scales with household size.
  # Only household analysis units have a hhsize to scale by.
  per_capita <- identical(.sp_amount_basis(sp), "per_capita")
  amount_scale <- if (per_capita) rep_len(1, nrow(svy)) else hhsize_scale

  if (sp$budget_mode == "transfer_first") {
    daily_transfer <- (sp$transfer_amount_usd * sp$transfer_n_payments) / 365
    return(to_welfare_scale(ifelse(eligible, daily_transfer / amount_scale, 0)))
  }

  if (sp$budget_mode == "budget_first") {
    n_eligible <- sum(eligible)
    if (n_eligible <= 0) return(NULL)
    w_elig <- if ("weight" %in% names(svy)) {
      w <- suppressWarnings(as.numeric(svy$weight[eligible]))
      valid <- is.finite(w) & w > 0
      if (identical(analysis_unit, "hh") && !per_capita) {
        hs <- hhsize_scale[eligible]
        sum(w[valid] / hs[valid], na.rm = TRUE)
      } else {
        # Per-capita budgets are shared over recipient people, and household
        # row weights already count people.
        sum(w[valid], na.rm = TRUE)
      }
    } else {
      0
    }
    n_units <- if (per_capita) sum(hhsize_scale[eligible]) else n_eligible
    divisor <- if (w_elig > 0) w_elig else n_units
    # The budget is total spend; admin cost takes its share first.
    net_budget <- sp$budget_fixed * (1 - .sp_admin_share(sp))
    daily_transfer <- (net_budget / divisor) / 365
    return(to_welfare_scale(ifelse(eligible, daily_transfer / amount_scale, 0)))
  }

  NULL
}

# Entry currency of an SP scenario: "LCU" or "PPP" (anything else, including a
# scenario that predates the field, is PPP - the stored welfare scale).
.sp_currency <- function(currency) {
  currency <- toupper(as.character(currency %||% "PPP")[1L])
  if (is.na(currency) || !identical(currency, "LCU")) "PPP" else "LCU"
}

# Administrative cost as a share of total cost (`sp$admin_cost_pct`, percent).
# Clamped to [0, 0.9]; missing or invalid is 0, so scenarios that predate the
# field behave exactly as before.
.sp_admin_share <- function(sp) {
  a <- suppressWarnings(as.numeric(sp$admin_cost_pct %||% 0)[1L]) / 100
  if (!is.finite(a) || a <= 0) 0 else min(a, 0.9)
}

# Amount basis of an SP scenario: "per_household" (default) or "per_capita".
.sp_amount_basis <- function(sp) {
  if (identical(sp$amount_basis, "per_capita")) "per_capita" else "per_household"
}

# Display prefix for SP amounts and costs in the entry currency.
.sp_currency_prefix <- function(currency) {
  if (identical(.sp_currency(currency), "LCU")) "LCU " else "$"
}


#' Reach and cost of a social-protection scenario, before it is run
#'
#' UI-32: the targeting controls used to give no feedback until a full policy
#' simulation had run, so picking a cutoff was guesswork. This answers "who
#' does this reach, and what does it cost?" directly from the survey and the
#' scenario.
#'
#' The numbers use the same seeded eligibility function and transfer
#' arithmetic as the run, without materializing a policy copy of the survey.
#' `.sp_transfer_totals()` remains the single implementation of the arithmetic
#' the diagnostics tab reports for the run's `.wiseapp_sp_transfer` column.
#'
#' The caller must pass the survey frame the *run* will use - Step 2 may have
#' filtered `survey_weather()` down to one baseline round, and totals computed
#' over every round instead would overstate both the eligible population and
#' the cost.
#'
#' @param svy Survey frame the policy run will use (`hist_sim()$svy`, falling
#'   back to `survey_weather()`). Needs `welfare`; `weight` and `hhsize` are
#'   used when present.
#' @param sp  Scenario list from `mod_3_01_sp_server()`.
#' @param analysis_unit `"hh"`, `"ind"` or `"firm"`.
#' @param seed Base seed; must match the one passed to `apply_policy_to_svy()`.
#'
#' @return A named list, or NULL when the survey cannot support the estimate:
#'   \describe{
#'     \item{n_rows}{Sample rows receiving a transfer.}
#'     \item{n_total}{Sample rows in the survey.}
#'     \item{n_pop}{Person-weighted recipient count (sample count when the
#'       survey carries no weights).}
#'     \item{n_recipient_units}{Recipient count, using weight / household size
#'       when household rows are person weighted.}
#'     \item{share_pct}{Weighted recipient share of the population, 0-100.}
#'     \item{weighted}{TRUE when survey weights were used.}
#'     \item{transfer_per_unit}{Annual transfer per recipient.}
#'     \item{transfer_total}{Annual population-level cost, including
#'       administration.}
#'     \item{transfer_cost, admin_cost}{The transfer and administration parts
#'       of `transfer_total`.}
#'     \item{amount_basis}{`"per_household"` or `"per_capita"`.}
#'     \item{transfer_per_person}{Annual net transfer per recipient person
#'       (NA when there are no recipients).}
#'     \item{budget_first}{TRUE when the per-unit amount was derived from a
#'       fixed budget rather than set directly.}
#'   }
#' @keywords internal
.sp_scenario_reach <- function(svy, sp, analysis_unit = "hh",
                               seed = WISEAPP_DEFAULT_SEED) {
  if (is.null(svy) || is.null(sp) || !is.data.frame(svy) || nrow(svy) == 0) {
    return(NULL)
  }
  if (!"welfare" %in% names(svy)) {
    return(NULL)
  }

  # The run and preview share one eligibility draw and transfer calculation;
  # the preview needs only this vector and the columns used by its totals.
  values <- tryCatch(
    withr::with_seed(wise_seed(seed, "policy", "sp"), {
      eligible <- .determine_sp_eligibility(svy, sp)
      transfer <- .sp_transfer_values(svy, sp, analysis_unit, eligible)
      list(eligible = eligible, transfer = transfer)
    }),
    error = function(e) NULL
  )
  if (is.null(values) || is.null(values$transfer) ||
    length(values$eligible) != nrow(svy)) {
    return(NULL)
  }
  eligible <- values$eligible
  totals <- .sp_transfer_totals_values(
    values$transfer, svy, analysis_unit, sp$currency, .sp_admin_share(sp)
  )

  # Eligibility is reported separately from receipt: a scenario with a zero
  # transfer still targets a population, and saying "0 eligible" there would
  # be misleading.
  eligible[is.na(eligible)] <- FALSE

  w <- if ("weight" %in% names(svy)) {
    suppressWarnings(as.numeric(svy$weight))
  } else {
    rep(1, nrow(svy))
  }
  w[!is.finite(w) | w < 0] <- 0
  weighted <- "weight" %in% names(svy) && sum(w) > 0
  if (!weighted) w <- rep(1, nrow(svy))

  w_elig <- sum(w[eligible])
  w_total <- sum(w)
  hhsize <- if (identical(analysis_unit, "hh") && "hhsize" %in% names(svy)) {
    hs <- suppressWarnings(as.numeric(svy$hhsize))
    hs[!is.finite(hs) | hs <= 0] <- 1
    hs
  } else {
    rep(1, nrow(svy))
  }
  household_weights <- if (identical(analysis_unit, "hh") && weighted) {
    w / hhsize
  } else {
    w
  }

  list(
    n_rows = sum(eligible),
    n_total = nrow(svy),
    n_pop = w_elig,
    n_recipient_units = sum(household_weights[eligible]),
    n_households_total = sum(household_weights),
    share_pct = if (w_total > 0) 100 * w_elig / w_total else NA_real_,
    weighted = weighted,
    transfer_per_unit = totals$per_unit,
    # Total annual cost, including administration (equal to the transfer cost
    # when admin_cost_pct is 0).
    transfer_total = totals$total_cost,
    transfer_cost = totals$total,
    admin_cost = totals$admin_cost,
    amount_basis = .sp_amount_basis(sp),
    transfer_per_person = {
      rec <- is.finite(values$transfer) & values$transfer > 0
      persons <- if (weighted) sum(w[rec]) else sum(hhsize[rec])
      if (persons > 0) totals$total / persons else NA_real_
    },
    budget_first = identical(
      sp$budget_mode %||% "transfer_first",
      "budget_first"
    )
  )
}


#' Does a policy scenario actually change the survey?
#'
#' TRUE when \code{apply_policy_to_svy()} moved anything at all - a covariate
#' lever, or a non-zero social-protection transfer. Unlike
#' \code{.compute_policy_deltas()} (which deliberately excludes
#' \code{SP_TRANSFER_COL}, since the transfer enters through welfare rather
#' than as a covariate), an SP-only scenario counts as an effect here.
#'
#' Used to warn - never to block - when every lever sits at its zero default,
#' so a run that will reproduce the baseline says so instead of looking like
#' a simulation that failed to start.
#'
#' @param svy_baseline Baseline survey-weather data frame.
#' @param svy_policy   Policy-adjusted survey-weather data frame.
#' @return Scalar logical.
#' @keywords internal
.scenario_has_effect <- function(svy_baseline, svy_policy,
                                 candidates = NULL) {
  if (is.null(svy_baseline) || is.null(svy_policy)) {
    return(FALSE)
  }

  # Social protection: any non-zero transfer is an effect on its own.
  sp <- svy_policy[[SP_TRANSFER_COL]]
  if (!is.null(sp)) {
    sp <- suppressWarnings(as.numeric(sp))
    if (any(is.finite(sp) & abs(sp) > 1e-10)) {
      return(TRUE)
    }
  }

  # Shock-responsive program: eligible households are paid when triggered.
  elig <- svy_policy[[SP_ELIGIBLE_COL]]
  if (!is.null(elig) && any(elig, na.rm = TRUE)) {
    return(TRUE)
  }

  # Covariate levers: only columns apply_policy_to_svy() can mutate. Survey
  # frames are wide, while this set is small and fixed by the policy schema.
  shared <- intersect(names(svy_baseline), names(svy_policy))
  if (!is.null(candidates)) shared <- shared[shared %in% candidates]
  for (col in shared) {
    b <- svy_baseline[[col]]
    p <- svy_policy[[col]]
    if (is.factor(b)) b <- as.character(b)
    if (is.factor(p)) p <- as.character(p)
    if (is.numeric(b) && is.numeric(p)) {
      if (any(abs(p - b) > 1e-10, na.rm = TRUE)) {
        return(TRUE)
      }
    } else if (!identical(b, p)) {
      return(TRUE)
    }
  }
  FALSE
}


#' Build the immutable diagnostics snapshot for one successful policy run
#'
#' Computes changed-variable and numeric summaries once, before the policy run
#' publishes any reactive state. The caller stores the returned ordinary R
#' object in one reactive value so renderers and exports observe the same run.
#'
#' @param svy_baseline Baseline survey frame.
#' @param svy_policy Policy-adjusted survey frame.
#' @param outcome Outcome column whose post-transfer values are diagnosed.
#' @param analysis_unit Analysis unit used for transfer totals.
#' @param candidates Known columns that the active policy configuration can
#'   modify, plus `outcome` when transfer-adjusted welfare should be shown.
#' @param sp Social-protection scenario used to snapshot eligibility before
#'   targeting errors.
#' @return A diagnostics snapshot, or NULL when either frame is unavailable.
#' @keywords internal
.policy_diagnostics_snapshot <- function(svy_baseline, svy_policy,
                                         outcome = "welfare",
                                         analysis_unit = "hh",
                                         candidates = .policy_candidate_cols(
                                           outcome = outcome
                                         ),
                                         sp = NULL,
                                         shock = NULL) {
  if (is.null(svy_baseline) || is.null(svy_policy)) {
    return(NULL)
  }

  policy_diag <- svy_policy
  if (!is.null(shock)) {
    # Shock-responsive program: "treated" is paid in at least one historical
    # year, at the amount of one activation; costs below are annual means.
    policy_diag[[SP_TRANSFER_COL]] <- shock$per_household * shock$paid_historical
  }
  if (SP_TRANSFER_COL %in% names(policy_diag) &&
    outcome %in% names(policy_diag)) {
    policy_diag[[outcome]] <- policy_diag[[outcome]] +
      policy_diag[[SP_TRANSFER_COL]]
  }

  sp_currency <- .sp_currency(sp$currency)
  admin_share <- .sp_admin_share(sp)
  totals <- .sp_transfer_totals(
    policy_diag, analysis_unit, sp_currency, admin_share
  )
  # Expected annual cost over the historical years (first summary row)
  shock_cost <- if (!is.null(shock)) as.list(shock$summary[1L, ])
  if (!is.null(shock_cost)) {
    totals$total <- shock_cost$mean_transfer_cost
    totals$admin_cost <- shock_cost$mean_admin_cost
    totals$total_cost <- shock_cost$mean_total_cost
  }
  vars <- detect_manipulated_vars(
    svy_baseline, policy_diag,
    candidates = candidates
  )

  input_summary <- if (length(vars) > 0L) {
    policy_input_diagnostics(svy_baseline, policy_diag, vars = vars)
  } else {
    NULL
  }
  baseline_values <- lapply(vars, function(v) svy_baseline[[v]])
  policy_values <- lapply(vars, function(v) policy_diag[[v]])
  names(baseline_values) <- names(policy_values) <- vars
  changed_counts <- .policy_changed_counts(svy_baseline, policy_diag, vars)
  eligibility <- tryCatch(
    if (!is.null(sp)) {
      .determine_sp_eligibility(svy_baseline, sp, apply_errors = FALSE)
    } else {
      NULL
    },
    error = function(e) NULL
  )

  out <- list(
    status = if (length(vars) == 0L) "no_change" else NULL,
    manipulated_vars = vars,
    baseline_values = baseline_values,
    policy_values = policy_values,
    changed_counts = changed_counts,
    transfer_sum = totals$total,
    admin_sum = totals$admin_cost,
    total_cost_sum = totals$total_cost,
    admin_share = admin_share,
    amount_basis = .sp_amount_basis(sp),
    transfer_pp = totals$per_unit,
    transfer_households = totals$n_households_weighted,
    transfer_currency = sp_currency,
    input_summary = input_summary,
    analysis_unit = analysis_unit,
    treatment_matrix = policy_treatment_matrix(
      svy_baseline, policy_diag,
      eligibility = eligibility,
      analysis_unit = analysis_unit
    ),
    component_matrix = policy_component_matrix(
      svy_baseline, policy_diag,
      analysis_unit = analysis_unit,
      candidates = unique(c(candidates, SP_TRANSFER_COL)),
      currency = sp_currency,
      admin_share = admin_share,
      sp_cost = shock_cost$mean_total_cost
    ),
    reach = policy_reach_summary(
      svy_baseline, policy_diag,
      analysis_unit = analysis_unit,
      candidates = unique(c(candidates, SP_TRANSFER_COL))
    )
  )
  if (!is.null(shock)) out$is_shock <- TRUE
  out
}


# Policy scenario candidate discovery ----

#' Identify candidate variables in the variable list matching given patterns
#'
#' @param variable_list A data frame with columns \code{name}, \code{label},
#'   and role flags \code{ind}, \code{hh}, \code{firm}, \code{area}.
#' @param patterns Character vector of regex patterns matched (case-insensitive)
#'   against the \code{name} column.
#'
#' @return A data frame with columns \code{name}, \code{label}, \code{level},
#'   or \code{NULL} if no matches.
#' @export
policy_candidate_info <- function(variable_list, patterns) {
  if (is.null(variable_list) || nrow(variable_list) == 0) {
    return(NULL)
  }
  nm <- variable_list$name
  if (is.null(nm)) {
    return(NULL)
  }
  mask <- Reduce(`|`, lapply(patterns, function(p) grepl(p, nm, ignore.case = TRUE)))
  if (!any(mask)) {
    return(NULL)
  }
  df <- variable_list[mask, , drop = FALSE]
  level <- vapply(seq_len(nrow(df)), function(i) {
    for (lvl in c("ind", "hh", "firm", "area")) {
      v <- df[[lvl]][i]
      if (!is.null(v) && !is.na(v) && v == 1L) {
        return(switch(lvl,
          ind = "Individual",
          hh = "Household",
          firm = "Firm",
          area = "Area"
        ))
      }
    }
    ""
  }, character(1))
  data.frame(
    name = df$name,
    label = if (!is.null(df$label)) df$label else df$name,
    level = level,
    stringsAsFactors = FALSE
  )
}

#' Build a placeholder tag listing selectable candidate variables
#'
#' @param category_label Human-readable category name (e.g. "infrastructure").
#' @param candidate_df Data frame from \code{policy_candidate_info()}.
#'
#' @return A Shiny tag.
#' @export
policy_placeholder_tag <- function(category_label, candidate_df) {
  msg_head <- paste0(
    "None of the relevant variables for ", category_label,
    " have been selected in the Step 1 model, so they cannot be manipulated here. ",
    "Go back to Step 1 to include them in the model."
  )
  if (is.null(candidate_df) || nrow(candidate_df) == 0) {
    return(shiny::div(
      class = "alert alert-info",
      msg_head, shiny::tags$br(),
      shiny::tags$em("No candidate variables were found in the variable list for this category.")
    ))
  }
  items <- lapply(seq_len(nrow(candidate_df)), function(i) {
    lvl <- candidate_df$level[i]
    shiny::tags$li(paste0(
      candidate_df$label[i],
      if (nzchar(lvl)) paste0(" (", lvl, ")") else ""
    ))
  })
  shiny::div(
    class = "alert alert-info",
    msg_head, shiny::tags$br(),
    shiny::tags$strong("Candidates available to select:"),
    do.call(shiny::tags$ul, items)
  )
}


# Random subset of rows ----
#
# Draws rows of `idx` in a random order. Without usable weights `w` (NULL) it
# takes `n` rows, the same `sample.int()` call as before weighted draws. With
# weights it takes the first rows whose cumulative weight is closest to
# `target`, so the weighted share moved matches the share asked for to within
# one row's weight (DOC-13; the same rule as the SP targeting errors, P0-8).
# `prob` makes some rows likelier to be drawn.
.pick_rows <- function(idx, n, target, w = NULL, prob = NULL) {
  if (is.null(w)) {
    k <- min(n, length(idx))
    return(idx[sample.int(length(idx), k, prob = prob)])
  }
  ord <- idx[sample.int(length(idx), prob = prob)]
  cum <- cumsum(w[ord])
  j <- which.min(abs(cum - target))
  k <- if (target <= abs(cum[j] - target)) 0L else j
  ord[seq_len(k)]
}


# Binary access flip helper ----
#
# Treats `change_pct` as the share of currently-without-access observations to
# flip to access (positive) or share of with-access to flip to no-access
# (negative).  `universal = TRUE` sets everyone to 1. With survey weights `w`
# the share is of the weighted group (DOC-13); without, of the rows.

.apply_binary_access <- function(x, universal, change_pct, w = NULL) {
  if (isTRUE(universal)) {
    return(ifelse(is.na(x), NA_integer_, 1L))
  }
  if (is.null(change_pct) || is.na(change_pct) || change_pct == 0) {
    return(x)
  }

  x_out <- as.integer(x)
  if (change_pct > 0) {
    idx0 <- which(x_out == 0L & !is.na(x_out))
    n_flip <- round(length(idx0) * change_pct / 100)
    if (n_flip > 0 && length(idx0) > 0) {
      flip <- .pick_rows(idx0, n_flip, sum(w[idx0]) * change_pct / 100, w)
      x_out[flip] <- 1L
    }
  } else {
    idx1 <- which(x_out == 1L & !is.na(x_out))
    n_flip <- round(length(idx1) * abs(change_pct) / 100)
    if (n_flip > 0 && length(idx1) > 0) {
      flip <- .pick_rows(idx1, n_flip, sum(w[idx1]) * abs(change_pct) / 100, w)
      x_out[flip] <- 0L
    }
  }
  x_out
}

# Percent change of a numeric lever variable: x * (1 + pct / 100).
.apply_numeric_pct <- function(x, pct) {
  if (is.null(pct) || length(pct) != 1L || is.na(pct) || pct == 0) {
    return(x)
  }
  x * (1 + pct / 100)
}

# Apply the moved levers of one scenario list (infra, digital, education) to the
# survey. A lever is handled by the fields it has: universal/access change
# (binary access), a value change (percent change of a numeric variable), or the
# health fields (travel time, the one special behaviour). Only variables in
# `lever_cols` (the model's) are changed. Each binary lever draws from its own
# stream, seeded by its variable, so toggling one lever never redraws another.
#' @noRd
.apply_access_levers <- function(svy, cfg, lever_cols, lever_seed) {
  moved <- .access_cfg_moved_codes(cfg)
  if (!length(moved)) {
    return(svy)
  }
  lv <- .cfg_lever_vars(cfg)
  w <- .sp_error_weights(svy)
  for (code in moved) {
    for (v in intersect(lv[[code]], lever_cols)) {
      universal <- .cfg_field(cfg, code, "_universal")
      access <- .cfg_field(cfg, code, "_access_change_pct")
      value <- .cfg_field(cfg, code, "_value_change_pct")
      if (identical(code, "health") && is.null(universal) && is.null(access) && is.null(value)) {
        svy[[v]] <- .apply_health_travel(
          svy[[v]], cfg$health_mode, cfg$health_travel_pct, cfg$health_travel_max
        )
      } else if (!is.null(value)) {
        svy[[v]] <- .apply_numeric_pct(svy[[v]], value)
      } else {
        svy[[v]] <- withr::with_seed(
          lever_seed(v), .apply_binary_access(svy[[v]], universal, access, w)
        )
      }
    }
  }
  svy
}

# Levers a scenario list has moved whose variable cannot be applied: not in the
# survey, or not in the model (`model_vars`). Named list code -> reason.
#' @noRd
.access_levers_unavailable <- function(cfg, survey_cols, model_vars = NULL) {
  lv <- .cfg_lever_vars(cfg)
  out <- character(0)
  for (code in .access_cfg_moved_codes(cfg)) {
    vars <- lv[[code]]
    in_svy <- vars[vars %in% survey_cols]
    if (!length(in_svy)) {
      out[[code]] <- "variable not in the survey"
    } else if (!is.null(model_vars) && !any(.lever_in_model(in_svy, model_vars))) {
      out[[code]] <- "variable not in the model"
    }
  }
  out
}

# Labour levers a scenario has moved whose variables cannot act: not in the
# survey, or not in the model (`model_vars`). Named character code -> reason,
# like `.access_levers_unavailable()`.
#' @noRd
.labor_levers_unavailable <- function(labor, survey_cols, model_vars = NULL) {
  out <- character(0)
  if (!is.list(labor)) {
    return(out)
  }
  why <- function(need) {
    absent <- setdiff(need, survey_cols)
    if (length(absent)) {
      return(paste0(paste(absent, collapse = ", "), " not in the survey"))
    }
    if (!is.null(model_vars)) {
      off <- need[!.lever_in_model(need, model_vars)]
      if (length(off)) {
        return(paste0(paste(off, collapse = ", "), " not in the model"))
      }
    }
    NULL
  }
  if (.lever_moved(labor$employment_change_pp)) {
    r <- why(c("employed", "unemployed"))
    if (!is.null(r)) out[["employment"]] <- r
  }
  if (.sector_target_set(labor$sector_manufacturing) || .sector_target_set(labor$sector_services)) {
    r <- why(c("employed", "agriculture", "industry", "services"))
    if (!is.null(r)) out[["sectors"]] <- r
  }
  out
}

.apply_health_travel <- function(x, mode, pct, max_min) {
  if (identical(mode, "pct")) {
    if (is.null(pct) || is.na(pct) || pct == 0) {
      return(x)
    }
    x * (1 + pct / 100)
  } else if (identical(mode, "max")) {
    if (is.null(max_min) || is.na(max_min)) {
      return(x)
    }
    pmin(x, max_min)
  } else {
    x
  }
}

# Welfare quantile for ex-ante targeting. Weighted by the survey weight (when
# present) so that "poorest p%" covers p% of the population, matching the
# weighted budget. Rows with a missing or non-positive weight are left out of
# the weighted quantile; without any usable weight the quantile is unweighted.
.sp_welfare_quantile <- function(welfare, weight, p) {
  welfare <- as.numeric(welfare)
  w <- if (is.null(weight)) NULL else suppressWarnings(as.numeric(weight))
  ok <- !is.na(welfare)
  if (!is.null(w)) {
    ok <- ok & !is.na(w) & w > 0
  }
  if (!is.null(w) && any(ok)) {
    return(unname(collapse::fquantile(welfare[ok], p, w = w[ok])))
  }
  unname(stats::quantile(welfare, p, na.rm = TRUE))
}

# How strongly targeting errors concentrate near the cutoff (`sp$error_concentration`).
# 0 (default, missing or invalid) is uniform random flips; larger values make
# rows near the cutoff likelier to flip. Clamped to [0, 50].
.sp_error_concentration <- function(sp) {
  k <- suppressWarnings(as.numeric(sp$error_concentration %||% 0)[1L])
  if (!is.finite(k) || k <= 0) 0 else min(k, 50)
}

# Distance of each row from the targeting cutoff, as a difference in
# percentile rank (0 at the cutoff, up to 1). The percentile rank is
# unweighted, which keeps the distance independent of survey weights. NULL when
# no distance exists (universal targeting, binary proxy variables, or an
# unusable cutoff), in which case flips stay uniform.
.sp_cutoff_distance <- function(svy, sp, targeting) {
  pct_rank <- function(x) {
    ok <- !is.na(x)
    out <- rep(NA_real_, length(x))
    if (any(ok)) {
      out[ok] <- (rank(x[ok], ties.method = "average") - 0.5) / sum(ok)
    }
    out
  }
  if (identical(targeting, "exante_poor")) {
    p <- (sp$targeting_threshold %||% 20) / 100
    return(abs(pct_rank(as.numeric(svy$welfare)) - p))
  }
  if (identical(targeting, "pmt")) {
    pmt_var <- sp$pmt_variable
    pmt_cut <- suppressWarnings(as.numeric(sp$pmt_cutoff %||% NA))
    if (is.null(pmt_var) || is.na(pmt_var) || is.na(pmt_cut) ||
      !(pmt_var %in% names(svy))) {
      return(NULL)
    }
    col <- svy[[pmt_var]]
    uniq <- sort(unique(col[!is.na(col)]))
    if (length(uniq) <= 2) {
      return(NULL)
    }
    cut_rank <- mean(col <= pmt_cut, na.rm = TRUE)
    return(abs(pct_rank(as.numeric(col)) - cut_rank))
  }
  NULL
}

# Survey weights used to size targeting errors (P0-8). NULL when the frame has
# no usable weight column or the weights are constant, in which case the
# error counts are row counts. Missing or negative weights count as 0.
.sp_error_weights <- function(svy) {
  if (!"weight" %in% names(svy)) {
    return(NULL)
  }
  w <- suppressWarnings(as.numeric(svy[["weight"]]))
  w[!is.finite(w) | w < 0] <- 0
  if (sum(w) <= 0 || length(unique(w)) < 2L) {
    return(NULL)
  }
  w
}

.determine_sp_eligibility <- function(svy, sp, apply_errors = TRUE) {
  n <- nrow(svy)
  targeting <- sp$targeting %||% "exante_poor"

  if (targeting == "universal") {
    eligible <- rep(TRUE, n)
  } else if (targeting == "exante_poor") {
    q <- .sp_welfare_quantile(
      svy$welfare, svy[["weight"]], (sp$targeting_threshold %||% 20) / 100
    )
    eligible <- !is.na(svy$welfare) & svy$welfare <= q
  } else if (targeting == "pmt") {
    pmt_var <- sp$pmt_variable
    pmt_cut <- as.numeric(sp$pmt_cutoff %||% NA)
    if (is.null(pmt_var) || is.na(pmt_var) || is.na(pmt_cut) ||
      !(pmt_var %in% names(svy))) {
      eligible <- rep(FALSE, n)
    } else {
      col <- svy[[pmt_var]]
      uniq <- sort(unique(col[!is.na(col)]))
      if (length(uniq) == 2 && all(uniq %in% c(0, 1))) {
        # Binary: match the selected value exactly
        eligible <- !is.na(col) & col == pmt_cut
      } else {
        # Continuous: include those at or below the cutoff
        eligible <- !is.na(col) & col <= pmt_cut
      }
    }
  } else {
    eligible <- rep(FALSE, n)
  }

  # Inclusion / exclusion errors (not applied for universal). Diagnostics can
  # request the ideal targeting rule by leaving these errors unapplied.
  #
  # The error targets are shares of the weighted population: the slider share
  # of the non-eligible (inclusion) or eligible (exclusion) survey weight, so
  # the realised weighted rate matches the slider to within one row's weight
  # (P0-8). Rows are drawn in a random order and flipped until the cumulative
  # weight is closest to the target. Without usable weights, or with constant
  # weights, this is the row count and the draw is the same sample.int() call
  # as before the weighted variant, so those results are unchanged. Which rows
  # flip is uniform unless `sp$error_concentration` > 0, which makes rows near
  # the cutoff likelier to flip (see .sp_cutoff_distance()).
  if (isTRUE(apply_errors) && targeting != "universal") {
    incl_rate <- (sp$inclusion_error_pct %||% 0) / 100
    excl_rate <- (sp$exclusion_error_pct %||% 0) / 100
    non_elig <- which(!eligible)
    elig <- which(eligible)
    conc <- .sp_error_concentration(sp)
    cut_dist <- if (conc > 0) .sp_cutoff_distance(svy, sp, targeting) else NULL
    err_w <- .sp_error_weights(svy)
    prob_for <- function(idx) {
      if (is.null(cut_dist)) {
        return(NULL)
      }
      d <- cut_dist[idx]
      d[!is.finite(d)] <- 1
      exp(-conc * d)
    }
    pick <- function(idx, rate) {
      .pick_rows(idx, round(length(idx) * rate), sum(err_w[idx]) * rate,
        err_w, prob_for(idx))
    }
    if (length(non_elig) > 0 && incl_rate > 0) {
      eligible[pick(non_elig, incl_rate)] <- TRUE
    }
    if (length(elig) > 0 && excl_rate > 0) {
      eligible[pick(elig, excl_rate)] <- FALSE
    }
  }

  eligible
}


#' Apply Policy Scenario Adjustments to Survey Covariates
#'
#' Modifies selected covariates in the survey-weather frame to reflect the
#' user-defined policy scenarios from the Step 3 sidebar.
#'
#' @param svy     A data frame of merged survey-weather data (from
#'                \code{mod_1_modelling_server()$survey_weather()}).
#' @param infra   Named list returned by \code{mod_3_02_infra_server()}.
#' @param sp      Named list returned by \code{mod_3_01_sp_server()}.
#' @param digital Named list returned by \code{mod_3_03_digital_server()}.
#' @param labor   Named list returned by \code{mod_3_04_labor_server()}.
#' @param education Named list returned by \code{mod_3_05_education_server()}.
#' @param model_vars Character vector of variable / term names in the current
#'   Step 1 model (covariates and interactions). When supplied, covariate
#'   levers only mutate columns that appear in the model - a variable dropped
#'   from Step 1 leaves the survey untouched. When \code{NULL} (the default)
#'   no gating is applied (legacy behaviour).
#' @param seed Integer seed for stochastic policy assignment.
#' @param analysis_unit Character. Analysis unit of the survey frame:
#'   `"hh"` scales social-protection transfers by household size when an
#'   `hhsize` column is present; `"pc"` treats rows as per-capita
#'   observations. Default `"hh"`.
#'
#' @return The modified survey data frame.
#' @export
apply_policy_to_svy <- function(svy,
                                infra = NULL,
                                sp = NULL,
                                digital = NULL,
                                labor = NULL,
                                education = NULL,
                                model_vars = NULL,
                                analysis_unit = "hh",
                                seed = WISEAPP_DEFAULT_SEED) {
  if (is.null(svy)) {
    return(svy)
  }
  # R2-BUG-12: each lever draws from its own seeded stream, so toggling one
  # lever never redraws another lever's recipients, and the SP preview
  # (.sp_scenario_reach) matches the run whatever else is enabled.
  lever_seed <- function(lever) wise_seed(seed, "policy", lever)
  local({
    cols <- names(svy)

    # Columns eligible for covariate-lever manipulation. A lever whose variable
    # has been removed from the Step 1 model (its UI control is hidden) must not
    # mutate the survey, otherwise the diagnostics tab would surface phantom
    # "manipulated" variables that the model - and hence the Results and
    # Decomposition tabs - ignore. Matching is shared with the lever modules'
    # show_* logic (exact match via .lever_in_model()). SP transfers act on
    # `welfare` (the outcome, not a covariate) and are intentionally not gated.
    lever_cols <- if (is.null(model_vars)) {
      cols
    } else {
      cols[.lever_in_model(cols, model_vars)]
    }

    # Infrastructure, digital inclusion, education (and levers of other
    # groups, carried in the same lists): only levers the user has moved.
    for (cfg in list(infra, digital, education)) {
      svy <- .apply_access_levers(svy, cfg, lever_cols, lever_seed)
    }

    # Labour market: only apply if user has specified non-zero changes
    if (!is.null(labor)) {
      if (has_labor_change(labor)) {
        # Employment rate change (percentage points): unemployed -> employed/selfemployed
        # Requires the employed and unemployed columns; selfemployed is optional
        # (it splits the new jobs when present)
        emp_change <- (labor$employment_change_pp %||% 0) / 100
        has_self <- "selfemployed" %in% lever_cols
        if (emp_change != 0 && all(c("employed", "unemployed") %in%
          lever_cols)) withr::with_seed(lever_seed("labor_employment"), {
          # Find unemployed individuals and the current ratio of self-employed
          # among the employed. In survey data `selfemployed` is a subset of
          # `employed`; a file that keeps them apart (employed = wage work) is
          # read that way.
          unemp_idx <- which(svy$unemployed == 1L & !is.na(svy$unemployed))
          employed_idx <- which(svy$employed == 1L & !is.na(svy$employed))
          selfemp_idx <- if (has_self) which(svy$selfemployed == 1L & !is.na(svy$selfemployed)) else integer(0)
          self_in_employed <- length(selfemp_idx) > 0L && all(svy$employed[selfemp_idx] %in% 1L)
          all_employed_idx <- union(employed_idx, selfemp_idx)

          # emp_change is the target shift in employment rate (as a fraction of
          # total N), so multiply by nrow(svy) to get the number of workers to
          # flip - giving a true percentage-point change in employment rate.
          n_total <- nrow(svy)
          # With survey weights the change is a share of the weighted population
          # (DOC-13); without usable weights it is of the rows
          emp_w <- .sp_error_weights(svy)

          if (emp_change > 0 && length(unemp_idx) > 0) {
            # Share of the currently employed who are self-employed
            ratio_self <- if (length(all_employed_idx) > 0) {
              length(selfemp_idx) / length(all_employed_idx)
            } else {
              0
            }

            n_flip <- min(round(n_total * emp_change), length(unemp_idx))
            if (n_flip > 0) {
              flip_idx <- .pick_rows(unemp_idx, n_flip, sum(emp_w) * emp_change, emp_w)
              n_to_selfemp <- round(length(flip_idx) * ratio_self)
              svy$unemployed[flip_idx] <- 0L
              svy$employed[flip_idx] <- 1L
              if (has_self) svy$selfemployed[flip_idx] <- 0L
              if (n_to_selfemp > 0) {
                flip_selfemp <- flip_idx[seq_len(n_to_selfemp)]
                svy$selfemployed[flip_selfemp] <- 1L
                # a file that keeps the two apart counts these as self-employed only
                if (!self_in_employed) svy$employed[flip_selfemp] <- 0L
              }
            }
          } else if (emp_change < 0 && length(all_employed_idx) > 0) {
            # Decrease employment: flip some of the employed to unemployed
            n_flip <- min(round(n_total * abs(emp_change)), length(all_employed_idx))
            if (n_flip > 0) {
              flip_idx <- .pick_rows(all_employed_idx, n_flip, sum(emp_w) * abs(emp_change), emp_w)
              svy$employed[flip_idx] <- 0L
              if (has_self) svy$selfemployed[flip_idx] <- 0L
              svy$unemployed[flip_idx] <- 1L
            }
          }
        })

        # Sectoral composition: minimize reallocation to achieve target percentages
        # Only move workers from sectors exceeding their target. Runs only when
        # a sector target was actually changed (R2-BUG-05); an unset target
        # keeps that sector's current count.
        sector_set <- .sector_target_set(labor$sector_manufacturing) ||
          .sector_target_set(labor$sector_services)
        if (sector_set && all(c("employed", "agriculture", "industry", "services") %in%
            lever_cols)) withr::with_seed(lever_seed("labor_sector"), {
          working <- .labor_working(svy)

          if (any(working)) {
            working_idx <- which(working)
            # Sizes are in survey weight when the weights vary (the same
            # weighted shares the sliders start from), else in rows (unit
            # weights), so equal or absent weights give the row counts.
            w_sec <- .sp_error_weights(svy)
            wt <- if (is.null(w_sec)) rep(1, nrow(svy)) else w_sec
            to_size <- if (is.null(w_sec)) round else identity
            n_working <- sum(wt[working_idx])

            # Current sector distribution (within working population)
            n_curr_agri <- sum(wt[working_idx][svy$agriculture[working_idx] %in% 1L])
            n_curr_ind <- sum(wt[working_idx][svy$industry[working_idx] %in% 1L])
            n_curr_serv <- sum(wt[working_idx][svy$services[working_idx] %in% 1L])

            # Target sizes: manufacturing and services chosen by user (an
            # unset target keeps the current size), agriculture is the
            # residual. Clamp so targets cannot exceed 100% combined (which
            # would make target_agri negative and corrupt the reallocation).
            n_target_ind <- if (.sector_target_set(labor$sector_manufacturing)) {
              to_size(n_working * min(max(labor$sector_manufacturing, 0) / 100, 1))
            } else {
              n_curr_ind
            }
            n_target_ind <- min(n_target_ind, n_working)
            n_target_serv <- if (.sector_target_set(labor$sector_services)) {
              to_size(n_working * max(labor$sector_services, 0) / 100)
            } else {
              n_curr_serv
            }
            n_target_serv <- min(n_target_serv, n_working - n_target_ind)
            n_target_agri <- n_working - n_target_ind - n_target_serv

            # Surplus = current exceeds target; deficit = current below target
            surplus_agri <- max(0, n_curr_agri - n_target_agri)
            surplus_ind <- max(0, n_curr_ind - n_target_ind)
            surplus_serv <- max(0, n_curr_serv - n_target_serv)

            deficit_agri <- max(0, n_target_agri - n_curr_agri)
            deficit_ind <- max(0, n_target_ind - n_curr_ind)
            deficit_serv <- max(0, n_target_serv - n_curr_serv)

            # Moves `cap` of weight out of `workers`: the rows are drawn at
            # random up to the weight asked for (`.pick_rows()`; a row count
            # without weights), then the first rows up to the first deficit go
            # to `first` and the rest to `second`. A sector with no deficit
            # takes none, except that weighted rounding leaves a remainder for
            # the only sector in deficit.
            move_rows <- function(workers, cap, first, d_first, second, d_second) {
              if (!length(workers)) {
                return(NULL)
              }
              n_move <- min(cap, length(workers))
              cands <- .pick_rows(workers, n_move, min(cap, sum(wt[workers])), w_sec)
              k <- length(cands)
              cum <- cumsum(wt[cands])
              n_first <- if (d_first > 0) {
                j <- which.min(abs(cum - d_first))
                min(if (d_first <= abs(cum[j] - d_first)) 0L else j, k)
              } else {
                0L
              }
              if (!is.null(w_sec) && d_second <= 0 && d_first > 0) n_first <- k
              n_second <- if (d_second > 0 || (!is.null(w_sec) && d_first > 0)) {
                max(0L, k - n_first)
              } else {
                0L
              }
              to <- c(rep(first, n_first), rep(second, n_second))
              if (length(to) > 0 && length(to) == k) {
                list(worker = cands, to = to)
              }
            }

            # Build list of workers to reallocate and their target sectors
            # Priority: reallocate from agriculture, then industry, then services
            reallocations <- data.frame(
              worker = integer(0),
              from_sector = character(0),
              to_sector = character(0),
              stringsAsFactors = FALSE
            )
            add_moves <- function(mv, from) {
              reallocations <<- rbind(
                reallocations,
                data.frame(worker = mv$worker, from_sector = from, to_sector = mv$to, stringsAsFactors = FALSE)
              )
            }

            # Agriculture -> (deficit sectors)
            if (surplus_agri > 0) {
              mv <- move_rows(
                which(working & svy$agriculture == 1L), surplus_agri,
                "industry", deficit_ind, "services", deficit_serv
              )
              if (!is.null(mv)) {
                add_moves(mv, "agriculture")
                deficit_ind <- max(0, deficit_ind - sum(wt[mv$worker][mv$to == "industry"]))
                deficit_serv <- max(0, deficit_serv - sum(wt[mv$worker][mv$to == "services"]))
              }
            }

            # Industry -> (deficit sectors)
            if (surplus_ind > 0 && (deficit_agri > 0 || deficit_serv > 0)) {
              mv <- move_rows(
                which(working & svy$industry == 1L), min(surplus_ind, deficit_agri + deficit_serv),
                "agriculture", deficit_agri, "services", deficit_serv
              )
              if (!is.null(mv)) {
                add_moves(mv, "industry")
                deficit_agri <- max(0, deficit_agri - sum(wt[mv$worker][mv$to == "agriculture"]))
                deficit_serv <- max(0, deficit_serv - sum(wt[mv$worker][mv$to == "services"]))
              }
            }

            # Services -> (deficit sectors)
            if (surplus_serv > 0 && (deficit_agri > 0 || deficit_ind > 0)) {
              mv <- move_rows(
                which(working & svy$services == 1L), min(surplus_serv, deficit_agri + deficit_ind),
                "agriculture", deficit_agri, "industry", deficit_ind
              )
              if (!is.null(mv)) add_moves(mv, "services")
            }

            # Execute reallocations: clear all sector flags for movers then assign
            # target sector. Vectorised over sector to avoid a row-by-row loop.
            if (nrow(reallocations) > 0) {
              movers <- reallocations$worker
              svy$agriculture[movers] <- 0L
              svy$industry[movers] <- 0L
              svy$services[movers] <- 0L
              for (sec in c("agriculture", "industry", "services")) {
                targets <- reallocations$worker[reallocations$to_sector == sec]
                if (length(targets) > 0 && sec %in% names(svy)) {
                  svy[[sec]][targets] <- 1L
                }
              }
            }
          }
        })
      }
    }

    # Social protection: add per-recipient transfer as SP_TRANSFER_COL column.
    # welfare is the regression outcome (not a covariate), so we tag the
    # transfer amount here; run_sim_pipeline() (fct_simulations.R) reads the
    # column post-prediction and adds it to y_point on the level scale
    # (re-logged when so$transform == "log") so the boost flows into
    # aggregate_with_uncertainty_delta() and matches the decomposition's delta_sp.
    #
    # When analysis_unit == "hh" each row is a household and the SP "recipient"
    # is the household, but welfare is per-capita - so the per-household
    # transfer must be divided by hhsize to match scale. When analysis_unit ==
    # "ind" the SP transfer is already per-individual and applies to every
    # eligible (individual) row as-is.
    if (!is.null(sp) && "welfare" %in% cols) {
      is_shock <- identical(sp$sp_type, "shock")
      if (!is_shock || is.null(.sp_shock_problem(sp))) {
        eligible <- withr::with_seed(
          lever_seed("sp"), .determine_sp_eligibility(svy, sp)
        )
        if (is_shock) {
          # Same eligibility and seeded stream as the regular program; the
          # transfer itself is dynamic (see SP_ELIGIBLE_COL).
          svy[[SP_ELIGIBLE_COL]] <- eligible
        } else {
          transfer <- .sp_transfer_values(svy, sp, analysis_unit, eligible)
          if (!is.null(transfer)) {
            svy[[SP_TRANSFER_COL]] <- transfer
          }
        }
      }
    }

    svy
  })
}


# Policy-by-delta derivation ----

#' Apply a per-household policy delta to the baseline Step 2 pipelines
#'
#' Module 3 historically built its policy arm by calling
#' \code{resimulate_with_svy()} - a full re-prediction against the policy-
#' adjusted survey. That works, but it (a) duplicates compute for every
#' CMIP6 member, and (b) historically caused the Results pane to disagree with
#' the Decomposition pane when baseline and policy aggregation used independent
#' residual draws. Residual streams are now deterministic, but deriving the
#' policy arm from the baseline still guarantees paired household-level values
#' and avoids that duplicate prediction work.
#'
#' This helper prepares invariant central channels once and evaluates resilience
#' at the exact Step 2 weather exposure retained for each prediction row:
#'   \itemize{
#'     \item \code{y_point_policy = y_point_baseline + main + repositioning + interaction}
#'     \item All other pipeline slots (\code{F_loading}, \code{train_aug},
#'           \code{id_vec}, \code{weather_raw}, \code{sim_year},
#'           \code{weight}) are passed through unchanged. Because
#'           \code{aggregate_pipeline_per_year()} sees the same \code{id_vec}
#'           and \code{train_aug} for both arms, residual draws line up
#'           household-for-household, so a zero delta produces a zero visual
#'           effect by construction.
#'   }
#'
#' Limitations of this v1:
#'   \itemize{
#'     \item For the linear model \code{F_loading} of the policy arm is the
#'           baseline loading plus the gradient of the correction, with the
#'           policy coefficients as extra columns (\code{.policy_arm_loading()}).
#'           The quantile model keeps the baseline loading, so its SE bands
#'           do not include the policy coefficients.
#'     \item Exact retained prediction-row exposure mapping is required. Invalid
#'           mappings fail the entire run; no period-mean fallback is used.
#'   }
#'
#' @param svy_baseline           Baseline survey-weather data frame.
#' @param svy_policy             Policy-adjusted survey-weather data frame.
#' @param model_fit              Step 1 model-fit list.
#' @param so                     Selected-outcome metadata.
#' @param hist_sim_baseline      Step 2 \code{hist_sim} list (verbatim).
#' @param saved_scenarios_baseline Step 2 named \code{saved_scenarios} list.
#' @param skip_coef              Retained for API compatibility. The active
#'   correction path computes central values only, so this value does not
#'   affect the result.
#' @param deltas                 Optional pre-computed covariate deltas from
#'   \code{.compute_policy_deltas()} - weather-independent, so computed once
#'   here and reused for every pipeline/scenario instead of per call
#'   (PERF-22). Computed internally when NULL.
#' @param F_hat                  Optional pre-built ecdf of the training
#'   outcome (RIF path; see \code{.compute_rif_channels()}). Computed
#'   internally when NULL.
#' @param decomp_context Optional immutable run-owned decomposition context.
#' @param run_identity Run identity required when a context is supplied.
#' @param annual_channels Optional prepared annual source from that context.
#' @param chunk_size Maximum prediction rows evaluated in each central block.
#' @param sp Optional SP scenario list. A shock-responsive scenario
#'   (`sp_type == "shock"`) is paid per prediction row when its trigger fires;
#'   needs `SP_ELIGIBLE_COL` on `svy_policy`.
#' @param analysis_unit `"hh"`, `"ind"` or `"firm"`; used for the shock
#'   transfer arithmetic.
#' @param seed Base seed of the run (the predicted-welfare layer of a
#'   shock-responsive scenario draws its errors from it).
#'
#' @return Named list with \code{hist_sim} and \code{saved_scenarios} on the
#'   Step 2 schema, prepared \code{annual_channels}, compact future
#'   \code{decomp_scenarios}, \code{correction_version}, and
#'   \code{n_na_untreated} (survey rows with a missing outcome, lever value
#'   or transfer that were treated as untreated). Invalid inputs error.
#' @export
apply_policy_delta_to_baseline <- function(svy_baseline,
                                           svy_policy,
                                           model_fit,
                                           so,
                                           hist_sim_baseline,
                                           saved_scenarios_baseline = list(),
                                           skip_coef = FALSE,
                                           deltas = NULL,
                                           F_hat = NULL,
                                           decomp_context = NULL,
                                           run_identity = NULL,
                                           annual_channels = NULL,
                                           chunk_size = 100000L,
                                           sp = NULL,
                                           analysis_unit = "hh",
                                           seed = WISEAPP_DEFAULT_SEED) {
  if (is.null(svy_baseline) || is.null(svy_policy) ||
    is.null(model_fit) || is.null(so) ||
    is.null(hist_sim_baseline)) {
    return(NULL)
  }
  if (!is.null(decomp_context) && is.null(run_identity)) {
    stop("Current run identity is required.", call. = FALSE)
  }

  if (length(chunk_size) != 1L || !is.numeric(chunk_size) ||
    !is.finite(chunk_size) || chunk_size < 1 || chunk_size != as.integer(chunk_size)) {
    stop("Invalid annual correction chunk size.", call. = FALSE)
  }
  run_identity <- run_identity %||% "standalone-annual-policy"
  if (!model_fit$engine %in% c("rif", "fixest")) {
    stop("Annual policy correction requires RIF or linear fixest.", call. = FALSE)
  }
  decomp_context <- decomp_context %||% .build_decomposition_context(
    svy_baseline, svy_policy, model_fit, so, deltas = deltas,
    skip_coef = TRUE, F_hat = F_hat, run_identity = run_identity
  )
  .validate_run_decomposition_context(decomp_context, run_identity)
  # Shock-responsive program (P1-6): thresholds from the historical exposure and
  # the per-household transfer, once per run; the annual correction evaluates
  # the trigger per pipeline from this plain-data plan.
  shock_plan <- if (identical(sp$sp_type, "shock") && SP_ELIGIBLE_COL %in% names(svy_policy)) {
    hist_exposure <- step2_exposure_resolve(hist_sim_baseline$pipeline, hist_sim_baseline)
    sp_shock_plan(
      sp, hist_exposure$table,
      svy_policy[[SP_ELIGIBLE_COL]], svy_policy, analysis_unit,
      hist_pipeline = hist_sim_baseline$pipeline,
      is_log = identical(so$transform %||% "", "log"),
      level_factor = outcome_level_scale(
        rep(1, nrow(svy_policy)), so, .outcome_ppp(svy_policy)
      ),
      seed = seed, hist_exposure_map = hist_exposure,
      pov_line = hist_sim_baseline$pov_line
    )
  }
  annual_channels <- annual_channels %||% .prepare_policy_annual_channels(
    decomp_context, run_identity, shock = shock_plan
  )
  if (!is.environment(annual_channels) || !environmentIsLocked(annual_channels) ||
    !identical(annual_channels$status, "ok")) {
    stop("Annual policy correction unavailable: ", annual_channels$reason %||% "invalid source", call. = FALSE)
  }
  if (!identical(annual_channels$context, decomp_context)) {
    stop("Annual policy source/context mismatch.", call. = FALSE)
  }
  hist_result <- .apply_policy_annual_pipeline(
    hist_sim_baseline$pipeline, annual_channels, run_identity,
    scenario = hist_sim_baseline$hist_label %||% "Historical", member = "Historical",
    chunk_size = chunk_size, owner = hist_sim_baseline
  )
  hist_sim_new <- hist_sim_baseline
  hist_sim_new$pipeline <- hist_result$pipeline
  parts <- list(hist_result$compact)
  shock_parts <- list(hist_result$shock)
  shock_cell_parts <- list(hist_result$shock_cells)
  # Per-survey-row loss-event counts by scenario, for coverage and adequacy of
  # the shock-affected poor at any later poverty line (sp_shock_reach())
  n_svy_policy <- nrow(svy_policy)
  shock_reach <- .sp_shock_reach_add(
    list(), hist_sim_baseline$hist_label %||% "Historical", hist_result$shock_reach,
    n_svy_policy
  )
  saved_scenarios_new <- lapply(seq_along(saved_scenarios_baseline), function(i) {
    s <- saved_scenarios_baseline[[i]]
    if (is.null(s) || is.null(s$pipelines)) {
      stop("Missing saved scenario prediction pipelines.", call. = FALSE)
    }
    # Members of one scenario share timestamps: rebuild exposure tables with
    # one cached timestamp decomposition per scenario.
    exposure_cache <- new.env(parent = emptyenv())
    pipes_new <- lapply(seq_along(s$pipelines), function(j) {
      result <- .apply_policy_annual_pipeline(
        s$pipelines[[j]], annual_channels, run_identity,
        scenario = names(saved_scenarios_baseline)[i] %||% paste0("Scenario ", i),
        member = names(s$pipelines)[j] %||% paste0("Member ", j),
        year_range = s$year_range %||% c(NA_integer_, NA_integer_),
        chunk_size = chunk_size, owner = s, exposure_cache = exposure_cache
      )
      parts[[length(parts) + 1L]] <<- result$compact
      shock_parts[[length(shock_parts) + 1L]] <<- result$shock
      shock_cell_parts[[length(shock_cell_parts) + 1L]] <<- result$shock_cells
      shock_reach <<- .sp_shock_reach_add(
        shock_reach, names(saved_scenarios_baseline)[i] %||% paste0("Scenario ", i),
        result$shock_reach, n_svy_policy
      )
      result$pipeline
    })
    names(pipes_new) <- names(s$pipelines)
    s$pipelines <- pipes_new
    s$policy_correction_version <- annual_channels$correction_version
    s
  })
  names(saved_scenarios_new) <- names(saved_scenarios_baseline)
  hist_sim_new$policy_correction_version <- annual_channels$correction_version

  # Shock program outputs: one row per (scenario, member, year) and their
  # summary by scenario; NULL for a regular program.
  shock_rows <- Filter(Negate(is.null), shock_parts)
  shock_rows <- if (length(shock_rows)) {
    do.call(rbind, c(shock_rows, list(make.row.names = FALSE)))
  }

  out <- list(hist_sim = hist_sim_new, saved_scenarios = saved_scenarios_new,
    annual_channels = annual_channels,
    decomp_scenarios = .bind_compact_future_decompositions(parts, model_fit$engine,
      identical(model_fit$engine, "rif")),
    correction_version = annual_channels$correction_version,
    n_na_untreated = decomp_context$n_na_untreated %||% 0L)
  if (!is.null(shock_rows)) {
    cells <- Filter(Negate(is.null), shock_cell_parts)
    out$shock <- list(
      rows = shock_rows, summary = sp_shock_summary(shock_rows),
      # Per-cell loss data for re-scoring with another loss-event share
      cells = if (length(cells)) do.call(rbind, c(cells, list(make.row.names = FALSE))),
      # Survey rows paid in at least one historical year
      paid_historical = hist_result$shock_paid,
      # Loss-event share the reach counts were taken at (not rescored)
      reach = shock_reach, reach_loss_event_pct = annual_channels$shock$loss_event_pct,
      # Amount of one activation; under a budget linked to modelled loss the
      # mean payment of the years a household was paid in the historical arm
      per_household = if (identical(annual_channels$shock$budget_rule, "loss_share")) {
        hist_result$shock_paid_mean
      } else {
        annual_channels$shock$per_household
      }
    )
  }
  out
}
